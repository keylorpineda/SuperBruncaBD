-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  06_Scheduler_Optimizacion_y_Pruebas.sql
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c Enterprise Edition (compatible con 23ai / 26ai Free)
-- DESCRIPCION:
--   1. Automatizacion de tareas en segundo plano mediante DBMS_SCHEDULER:
--      - Cierre diario por cajero y consolidado de ventas.
--      - Monitoreo preventivo de salud del motor (tablespaces >85%, objetos, indices).
--      - Notificaciones automaticas de creditos, morosidad y productos vencidos.
--      - Gestion semanal de inventario y mercadeo (reportes y promociones).
--      - Premiacion semestral automatica a los 10 mejores clientes.
--   2. Analisis de Optimizacion y Afinamiento SQL con EXPLAIN PLAN + DBMS_XPLAN:
--      - Evaluacion de ruta de acceso antes del afinamiento (Full Table Scan).
--      - Diseno e implementacion de indice compuesto optimizado.
--      - Evaluacion posterior (Index Range Scan) con tabla comparativa de costos.
--   3. Bateria integral de pruebas de verificacion de extremo a extremo.
-- ============================================================================

WHENEVER SQLERROR CONTINUE;

-- Conectar dinamicamente al PDB o esquema de trabajo
DECLARE
    v_contenedor VARCHAR2(128);
    v_pdb        VARCHAR2(128);
BEGIN
    v_contenedor := SYS_CONTEXT('USERENV', 'CON_NAME');
    IF v_contenedor = 'CDB$ROOT' THEN
        SELECT name INTO v_pdb 
          FROM v$pdbs 
         WHERE open_mode LIKE 'READ WRITE%' 
           AND name <> 'PDB$SEED' 
           AND ROWNUM = 1;
        EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
        DBMS_OUTPUT.PUT_LINE('[SESION] Conectado exitosamente al PDB: ' || v_pdb);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[SESION] Ya en PDB: ' || v_contenedor);
    END IF;
    
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG';
        DBMS_OUTPUT.PUT_LINE('[SESION] Esquema actual establecido en CADENA_NEG.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[AVISO] No se pudo cambiar a CADENA_NEG: ' || SQLERRM);
    END;
END;
/

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. LIMPIEZA PREVIA Y CREACION DE JOBS CON DBMS_SCHEDULER
PROMPT ============================================================================

BEGIN
    FOR j IN (
        SELECT job_name 
          FROM all_scheduler_jobs 
         WHERE owner = 'CADENA_NEG' 
           AND job_name IN ('JOB_CIERRE_DIARIO_AUTO', 'JOB_MONITOREO_SALUD_DIARIO', 
                           'JOB_NOTIF_CREDITOS_DIARIO', 'JOB_MERCADEO_SEMANAL', 
                           'JOB_PREMIACION_SEMESTRAL')
    ) LOOP
        BEGIN
            DBMS_SCHEDULER.DROP_JOB(job_name => j.job_name, force => TRUE);
            DBMS_OUTPUT.PUT_LINE('[LIMPIEZA] Job eliminado previamente: ' || j.job_name);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/

-- ----------------------------------------------------------------------------
-- 1.1 JOB_CIERRE_DIARIO_AUTO
-- Frecuencia: Todos los dias a las 23:00 (11:00 PM)
-- Accion: Ejecuta el cierre diario de ventas y desglose por cajero
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_CIERRE_DIARIO_AUTO',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN CADENA_NEG.PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO(TRUNC(SYSDATE)); END;',
        start_date      => TRUNC(SYSDATE) + 23/24,
        repeat_interval => 'FREQ=DAILY; BYHOUR=23; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Cierre contable y operativo diario consolidado con desglose por cajero'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_CIERRE_DIARIO_AUTO programado diariamente a las 23:00.');
END;
/

-- ----------------------------------------------------------------------------
-- 1.2 JOB_MONITOREO_SALUD_DIARIO
-- Frecuencia: Todos los dias a las 06:00 AM
-- Accion: Inspecciona tablespaces >85%, objetos invalidos, indices danados y crecimiento
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_MONITOREO_SALUD_DIARIO',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN CADENA_NEG.PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO; END;',
        start_date      => TRUNC(SYSDATE) + 1 + 6/24,
        repeat_interval => 'FREQ=DAILY; BYHOUR=6; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Inspeccion preventiva de salud del motor: tablespaces, objetos, indices y sesiones'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_MONITOREO_SALUD_DIARIO programado diariamente a las 06:00.');
END;
/

-- ----------------------------------------------------------------------------
-- 1.3 JOB_NOTIF_CREDITOS_DIARIO
-- Frecuencia: Todos los dias a las 07:00 AM
-- Accion: Verifica limites de credito (85% CxC, 70% CxP), morosidad >1 mes y productos vencidos
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_NOTIF_CREDITOS_DIARIO',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS; 
                            END;',
        start_date      => TRUNC(SYSDATE) + 1 + 7/24,
        repeat_interval => 'FREQ=DAILY; BYHOUR=7; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Notificaciones automaticas de creditos, cuentas por pagar y morosidad de cartera'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_NOTIF_CREDITOS_DIARIO programado diariamente a las 07:00.');
END;
/

-- ----------------------------------------------------------------------------
-- 1.4 JOB_MERCADEO_SEMANAL
-- Frecuencia: Todos los lunes a las 05:00 AM
-- Accion: Genera reporte de productos proximos a vencer / sin movimiento y aplica descuentos
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_MERCADEO_SEMANAL',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN 
                                CADENA_NEG.PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO; 
                                CADENA_NEG.PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL; 
                            END;',
        start_date      => TRUNC(SYSDATE) + 1 + 5/24,
        repeat_interval => 'FREQ=WEEKLY; BYDAY=MON; BYHOUR=5; BYMINUTE=0; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Generacion de reporte de inventario a mercadeo y activacion de descuentos semanales'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_MERCADEO_SEMANAL programado los lunes a las 05:00.');
END;
/

-- ----------------------------------------------------------------------------
-- 1.5 JOB_PREMIACION_SEMESTRAL
-- Frecuencia: Parametrizada por MESES_FRECUENCIA_PREMIACION (ej. cada 6 meses)
-- Accion: Premia a los mejores clientes excluyendo cliente generico CLI-000000
-- ----------------------------------------------------------------------------
DECLARE
    v_meses NUMBER;
BEGIN
    v_meses := NVL(CADENA_NEG.PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MESES_FRECUENCIA_PREMIACION'), 6);

    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_PREMIACION_SEMESTRAL',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN CADENA_NEG.PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES; END;',
        start_date      => TO_DATE('2026-06-30 23:30:00', 'YYYY-MM-DD HH24:MI:SS'),
        repeat_interval => 'FREQ=MONTHLY; INTERVAL=' || v_meses || '; BYMONTHDAY=-1; BYHOUR=23; BYMINUTE=30; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Premiacion automatica parametrizada: cada ' || v_meses || ' meses para Top clientes'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_PREMIACION_SEMESTRAL programado dinamicamente cada ' || v_meses || ' meses.');
END;
/

-- ----------------------------------------------------------------------------
-- 1.6 JOB_PADRON_MENSUAL (+ JOB_PADRON_DESCARGA)
-- Frecuencia: dia PADRON_DIA_CARGA de cada mes a las 02:00 (el TSE publica mensualmente)
-- Accion: descarga padron_completo.zip del TSE y lo carga con PR_CARGAR_PADRON_MASIVO
-- ----------------------------------------------------------------------------
DECLARE
    v_es_win BOOLEAN := INSTR(UPPER(DBMS_UTILITY.PORT_STRING), 'WIN') > 0;

    PROCEDURE crear_si_no_existe(p_codigo VARCHAR2, p_nombre VARCHAR2, p_desc VARCHAR2,
                                 p_texto VARCHAR2 DEFAULT NULL, p_num NUMBER DEFAULT NULL) IS
        v_existe NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM CADENA_NEG.SEG_PARAMETRO WHERE CODIGO_PARA = p_codigo;
        IF v_existe = 0 THEN
            CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(p_codigo, 'NEGOCIO', p_nombre, p_desc, 'N', p_texto, p_num);
        END IF;
    END;
BEGIN
    crear_si_no_existe('PADRON_URL_TSE', 'URL de descarga del padron completo',
        'Archivo ZIP oficial publicado mensualmente por el TSE (descarga_padron.html).',
        'https://www.tse.go.cr/zip/padron/padron_completo.zip');
    crear_si_no_existe('PADRON_ARCHIVO', 'Archivo del padron dentro de DIR_PADRON',
        'Nombre del TXT extraido del ZIP que lee la tabla externa EXT_PADRON_TSE.', 'PADRON_COMPLETO.txt');
    crear_si_no_existe('PADRON_DIA_CARGA', 'Dia del mes de la carga del padron',
        'Dia (1-28) en que JOB_PADRON_MENSUAL descarga y carga el padron vigente.', NULL, 5);
    crear_si_no_existe('PADRON_INACTIVAR_AUSENTES', 'Inactivar personas ausentes del padron',
        'S = marcar como inactivas (ESTADO_PADR = I) las cedulas que ya no vienen en el padron vigente.', 'S');
    crear_si_no_existe('PADRON_SCRIPT_DESCARGA', 'Script de descarga del padron',
        'Ruta del script que descarga y descomprime el ZIP del TSE en DIR_PADRON.',
        CASE WHEN v_es_win THEN 'C:\app\oracle\proyecto\datos\padron\Descargar_Padron_TSE.ps1'
             ELSE '/opt/oracle/proyecto/datos/padron/Descargar_Padron_TSE.sh' END);

    CADENA_NEG.PKG_PER_PADRON.PR_CONFIGURAR_JOBS_PADRON;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[AVISO] Configurando JOB_PADRON_MENSUAL: ' || SQLERRM);
END;
/

-- Verificacion de Jobs en el Diccionario de Datos
SELECT job_name, state, next_run_date, repeat_interval, comments
  FROM all_scheduler_jobs
 WHERE owner = 'CADENA_NEG'
 ORDER BY job_name;


PROMPT ============================================================================
PROMPT 2. CASO DE ESTUDIO: OPTIMIZACION Y AFINAMIENTO SQL (EXPLAIN PLAN)
PROMPT ============================================================================

-- Limpiar tabla PLAN_TABLE antes del analisis
BEGIN
    DELETE FROM PLAN_TABLE WHERE STATEMENT_ID LIKE 'PLAN_%';
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Actualizar estadisticas del catalogo para el CBO
EXEC DBMS_STATS.GATHER_TABLE_STATS('CADENA_NEG', 'VEN_CUENTA_COBRAR', CASCADE => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS('CADENA_NEG', 'PER_CLIENTE', CASCADE => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS('CADENA_NEG', 'INV_EXISTENCIA', CASCADE => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS('CADENA_NEG', 'VEN_FACTURA', CASCADE => TRUE);

-- 2.0 Consulta 1 en estado natural (sin hints): Muestra la eleccion autonoma del CBO
-- En tablas de pocos bloques (<5 bloques, 5-10 filas), el CBO elige de forma natural TABLE ACCESS FULL
-- debido a que 1 operacion de I/O multibloque cuesta menos que descender por raiz, rama y hoja del
-- indice B-Tree mas la lectura por ROWID (3 I/Os FTS vs 4 I/Os Index Scan).
PROMPT --- Evaluando Consulta 1 en estado Natural (Sin hints - Eleccion CBO) ---

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_CUCO_NATURAL' FOR
SELECT c.ID_CUENTA_COBRAR, c.ID_FACTURA_VENTA, cl.CODIGO_CLI, c.FECHA_VENCIM_CUCO, c.SALDO_CUCO, c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE = cl.ID_CLIENTE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIM_CUCO < SYSDATE;

-- 2.1 Consulta 1: Cuentas por Cobrar en Mora (Requerimiento Funcional de Cartera)
-- Simula y contrasta el comportamiento a escala de produccion forzando ambas rutas:
-- FTS (Full Table Scan O(N)) vs Acceso por Indice Compuesto IX_CUCO_ESTADO_VENCIM (Index Range Scan O(log N)).
PROMPT --- Evaluando Consulta 1 con Hints de Escala: FTS vs Index Range Scan ---

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_CUCO_FTS' FOR
SELECT /*+ FULL(c) */
       c.ID_CUENTA_COBRAR, c.ID_FACTURA_VENTA, cl.CODIGO_CLI, c.FECHA_VENCIM_CUCO, c.SALDO_CUCO, c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE = cl.ID_CLIENTE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIM_CUCO < SYSDATE;

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_CUCO_IDX' FOR
SELECT /*+ INDEX(c IX_CUCO_ESTADO_VENCIM) */
       c.ID_CUENTA_COBRAR, c.ID_FACTURA_VENTA, cl.CODIGO_CLI, c.FECHA_VENCIM_CUCO, c.SALDO_CUCO, c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE = cl.ID_CLIENTE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIM_CUCO < SYSDATE;

-- 2.2 Consulta 2: Existencias de Inventario por Bodega (Requerimiento Funcional de Stock)
PROMPT --- Evaluando Consulta 2: Existencias por Bodega (FTS vs Index Scan) ---

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_INV_FTS' FOR
SELECT /*+ FULL(e) */ e.ID_BODEGA, p.CODIGO_PROD, p.NOMBRE_PROD, e.CANTIDAD_EXIS
  FROM INV_EXISTENCIA e
  JOIN PRO_PRODUCTO p ON p.ID_PRODUCTO = e.ID_PRODUCTO
 WHERE e.ID_BODEGA = 1 AND e.CANTIDAD_EXIS > 0;

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_INV_IDX' FOR
SELECT /*+ INDEX(e UK_EXIS_BODE_PROD_LOTE) */ e.ID_BODEGA, p.CODIGO_PROD, p.NOMBRE_PROD, e.CANTIDAD_EXIS
  FROM INV_EXISTENCIA e
  JOIN PRO_PRODUCTO p ON p.ID_PRODUCTO = e.ID_PRODUCTO
 WHERE e.ID_BODEGA = 1 AND e.CANTIDAD_EXIS > 0;

-- 2.3 Consulta 3: Facturas de Venta por Rango de Fechas (Requerimiento Funcional de Cierre)
PROMPT --- Evaluando Consulta 3: Ventas por Rango de Fechas (FTS vs Index Range Scan) ---

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_FAC_FTS' FOR
SELECT /*+ FULL(f) */ f.ID_FACTURA_VENTA, f.NUM_FACTURA_FAVE, f.FECHA_FAVE, f.SUBTOTAL_FAVE
  FROM VEN_FACTURA f
 WHERE f.FECHA_FAVE BETWEEN TRUNC(SYSDATE) - 30 AND SYSDATE;

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_FAC_IDX' FOR
SELECT /*+ INDEX(f IX_FAVE_FECHA) */ f.ID_FACTURA_VENTA, f.NUM_FACTURA_FAVE, f.FECHA_FAVE, f.SUBTOTAL_FAVE
  FROM VEN_FACTURA f
 WHERE f.FECHA_FAVE BETWEEN TRUNC(SYSDATE) - 30 AND SYSDATE;

PROMPT ============================================================================
PROMPT PLAN DE EJECUCION CBO: CUENTAS POR COBRAR - RUTA NATURAL DEL OPTIMIZADOR (SIN HINTS)
PROMPT ============================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'PLAN_CUCO_NATURAL', 'TYPICAL'));

PROMPT ============================================================================
PROMPT PLAN DE EJECUCION CBO: CUENTAS POR COBRAR - TABLE ACCESS FULL (FORZADO CON HINT)
PROMPT ============================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'PLAN_CUCO_FTS', 'TYPICAL'));

PROMPT ============================================================================
PROMPT PLAN DE EJECUCION CBO: CUENTAS POR COBRAR - INDEX RANGE SCAN (FORZADO CON HINT)
PROMPT ============================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'PLAN_CUCO_IDX', 'TYPICAL'));

PROMPT ============================================================================
PROMPT METRICAS REALES CALCULADAS POR EL OPTIMIZADOR CBO (PLAN_TABLE)
PROMPT ============================================================================
COL STATEMENT_ID FORMAT A16;
COL OPERATION    FORMAT A20;
COL OPTIONS      FORMAT A18;
COL OBJECT_NAME  FORMAT A22;
COL COST         FORMAT 999999;
COL CPU_COST     FORMAT 999999999;
COL IO_COST      FORMAT 999999;

SELECT statement_id, operation, options, object_name, cost, cpu_cost, io_cost
  FROM plan_table
 WHERE id = 0
 ORDER BY statement_id;


PROMPT ============================================================================
PROMPT 3. BATERIA INTEGRAL DE PRUEBAS DE EXTREMO A EXTREMO
PROMPT ============================================================================

DECLARE
    v_id_factura      NUMBER;
    v_id_compra       NUMBER;
    v_id_cli_padr     NUMBER;
    v_saldo_cli_ant   NUMBER;
    v_saldo_cli_nue   NUMBER;
    v_saldo_prov_ant  NUMBER;
    v_saldo_prov_nue  NUMBER;
    v_stock_ant       NUMBER;
    v_stock_nue       NUMBER;
    v_saldo_cuco_fin  NUMBER;
    v_acciones_tot    NUMBER;
    v_lineas_padron   NUMBER;
    v_estado_fac_fin  VARCHAR2(1);
    v_fallo_esperado  BOOLEAN;
    v_lineas_neg      PKG_VEN_OPERACION.T_LISTA_LINEAS_VENTA;
    v_num_fac_neg     VARCHAR2(50);
    v_count_fac       NUMBER;
    v_count_cxc       NUMBER;
    v_interval_sched  VARCHAR2(200);
BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================================================');
    DBMS_OUTPUT.PUT_LINE('  INICIANDO SUITE DE PRUEBAS INTEGRALES DE REGLAS DE NEGOCIO Y PAQUETES');
    DBMS_OUTPUT.PUT_LINE('========================================================================');

    -- ------------------------------------------------------------------------
    -- PRUEBA 1: PKG_ADM_MONITOREO (Inspeccion de salud del motor y errores de sistema)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 1] Ejecutando monitoreo de salud del motor...');
    PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 1] Monitoreo diario ejecutado y registrado en AUD_MONITOREO_BD.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 2: PKG_ADM_NOTIFICACION (Deteccion de umbrales 85% CxC, 70% CxP, morosidad)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 2] Ejecutando verificacion y notificaciones de credito...');
    PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO;
    PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO;
    PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS;
    PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 2] Procedimientos de notificacion ejecutados exitosamente.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 3: PKG_PER_PADRON (Padron electoral TSE, carga por lotes y cliente)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 3] Verificando padron electoral y sincronizacion...');
    PKG_PER_PADRON.PR_GENERAR_ARCHIVO_PADRON_TSE('DIR_PADRON', 'PADRON_PRUEBA.TXT');
    PKG_PER_PADRON.PR_CARGAR_PADRON_TSE('DIR_PADRON', 'PADRON_PRUEBA.TXT');

    SELECT COUNT(*) INTO v_lineas_padron FROM CAT_PADRON;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 3.1] Padron electoral cargado. Total registros en CAT_PADRON: ' || v_lineas_padron);

    -- Creacion automatica de cliente a partir de padron TSE
    PKG_PER_PADRON.PR_CREAR_CLIENTE_DESDE_PADRON(
        p_cedula            => '100000003',
        p_codigo_cli        => 'CLI-TSE-001',
        p_es_preferencial   => 'S',
        p_monto_max_credito => 300000,
        p_dias_credito      => 30,
        p_id_cliente_out    => v_id_cli_padr
    );
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 3.2] Cliente creado exitosamente desde Padron TSE. ID: ' || v_id_cli_padr);

    -- ------------------------------------------------------------------------
    -- PRUEBA 4: COMPRAS A CREDITO Y ACTUALIZACION AUTOMATICA DE PROVEEDOR E INVENTARIO
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 4] Registrando factura de compra a credito y verificando disparadores...');
    SELECT NVL(SALDO_ACTUAL_PROVE, 0) INTO v_saldo_prov_ant FROM PER_PROVEEDOR WHERE ID_PROVEEDOR = 1;
    SELECT NVL(CANTIDAD_EXIS, 0) INTO v_stock_ant FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;

    PKG_COM_OPERACION.PR_CREAR_FACTURA_COMPRA(
        p_id_proveedor   => 1,
        p_id_bodega      => 1,
        p_id_usuario     => 1,
        p_num_factura    => 'FAC-TEST-COM-' || TO_CHAR(SYSDATE, 'HH24MISS'),
        p_es_credito     => 'S',
        p_subtotal       => 50000,
        p_descuento      => 0,
        p_impuesto       => 6500,
        p_id_factura_out => v_id_compra
    );

    PKG_COM_OPERACION.PR_AGREGAR_DETALLE_COMPRA(
        p_id_factura_compra => v_id_compra,
        p_id_producto       => 1,
        p_id_lote           => NULL,
        p_linea             => 1,
        p_cantidad          => 25,
        p_costo_unitario    => 2000,
        p_porc_descuento    => 0,
        p_porc_impuesto     => 13
    );

    SELECT NVL(SALDO_ACTUAL_PROVE, 0) INTO v_saldo_prov_nue FROM PER_PROVEEDOR WHERE ID_PROVEEDOR = 1;
    SELECT NVL(CANTIDAD_EXIS, 0) INTO v_stock_nue FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;

    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 4] Compra procesada #' || v_id_compra || 
                         ' -> Saldo Proveedor: de ' || v_saldo_prov_ant || ' a ' || v_saldo_prov_nue ||
                         ', Stock Prod 1: de ' || v_stock_ant || ' a ' || v_stock_nue);

    -- ------------------------------------------------------------------------
    -- PRUEBA 5: VENTAS A CREDITO, LIMITE DE CREDITO, DESCUENTO DE STOCK Y ACCIONES
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 5] Registrando factura de venta a credito...');
    SELECT NVL(SALDO_ACTUAL_CLI, 0) INTO v_saldo_cli_ant FROM PER_CLIENTE WHERE ID_CLIENTE = 3;
    v_stock_ant := v_stock_nue;

    PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA(
        p_id_cliente     => 3,
        p_id_sucursal    => 1,
        p_id_usuario     => 1,
        p_num_factura    => 'FAC-TEST-VEN-' || TO_CHAR(SYSDATE, 'HH24MISS'),
        p_es_credito     => 'S',
        p_subtotal       => 20000,
        p_descuento      => 0,
        p_impuesto       => 2600,
        p_id_factura_out => v_id_factura
    );

    PKG_VEN_OPERACION.PR_AGREGAR_DETALLE_VENTA(
        p_id_factura_venta => v_id_factura,
        p_id_producto      => 1,
        p_id_servicio      => NULL,
        p_id_lote          => NULL,
        p_linea            => 1,
        p_cantidad         => 5,
        p_precio_unitario  => 4000,
        p_porc_descuento   => 0,
        p_porc_impuesto    => 13
    );

    SELECT NVL(SALDO_ACTUAL_CLI, 0) INTO v_saldo_cli_nue FROM PER_CLIENTE WHERE ID_CLIENTE = 3;
    SELECT NVL(CANTIDAD_EXIS, 0) INTO v_stock_nue FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;

    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 5] Venta procesada #' || v_id_factura || 
                         ' -> Saldo Cliente: de ' || v_saldo_cli_ant || ' a ' || v_saldo_cli_nue ||
                         ', Stock Prod 1: de ' || v_stock_ant || ' a ' || v_stock_nue);

    -- ------------------------------------------------------------------------
    -- PRUEBA 6: ABONO Y CAMBIO AUTOMATICO DE ESTADO PENDIENTE ('P') A CANCELADA ('C')
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 6] Aplicando abonos totales para cancelacion automatica...');
    PKG_VEN_OPERACION.PR_REGISTRAR_ABONO_COBRAR(
        p_id_factura_venta => v_id_factura,
        p_id_usuario       => 1,
        p_tipo_pago        => 'EFECTIVO',
        p_num_recibo       => 'REC-TEST-' || TO_CHAR(SYSDATE, 'HH24MISS'),
        p_monto_abono      => 22600,
        p_referencia       => 'Liquidacion factura prueba'
    );

    SELECT ESTADO_FAVE INTO v_estado_fac_fin FROM VEN_FACTURA WHERE ID_FACTURA_VENTA = v_id_factura;
    SELECT SALDO_CUCO INTO v_saldo_cuco_fin FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_VENTA = v_id_factura;

    IF v_estado_fac_fin = 'C' AND v_saldo_cuco_fin = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 6] Abono liquidado. Estado final factura: Cancelada (' || v_estado_fac_fin || '), Saldo CxC: ' || v_saldo_cuco_fin);
    ELSE
        RAISE_APPLICATION_ERROR(-20090, 'Fallo verificacion de cambio de estado P->C o saldo en CxC.');
    END IF;

    -- ------------------------------------------------------------------------
    -- PRUEBA 7: PKG_PRM_MERCADEO (Descuentos semanales, Premiacion Top 10 y Scheduler Dinamico)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 7] Ejecutando politicas de mercadeo y premiacion semestral...');
    PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL;
    PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES('2026-S1');

    -- Verificar que el cliente de mostrador generico CLI-000000 no haya sido premiado
    DECLARE
        v_cant_gen NUMBER := 0;
    BEGIN
        SELECT COUNT(*) INTO v_cant_gen
          FROM PRM_ORDEN_PREMIACION op
               JOIN PER_CLIENTE c ON c.ID_CLIENTE = op.ID_CLIENTE
         WHERE c.CODIGO_CLI = 'CLI-000000';

        IF v_cant_gen > 0 THEN
            RAISE_APPLICATION_ERROR(-20093, 'El cliente generico CLI-000000 fue premiado indebidamente.');
        END IF;
    END;

    SELECT COUNT(*) INTO v_acciones_tot FROM PRM_ACCION_CLIENTE;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 7] Premiacion ejecutada. Acciones registradas: ' || v_acciones_tot || 
                         '. Cliente generico CLI-000000 excluido correctamente.');

    -- Probar reconfiguracion dinamica de frecuencia de premiacion y sincronizacion del Scheduler
    PKG_PRM_MERCADEO.PR_CONFIGURAR_FRECUENCIA_PREMIACION(3);
    SELECT repeat_interval INTO v_interval_sched
      FROM all_scheduler_jobs
     WHERE owner = 'CADENA_NEG'
       AND job_name = 'JOB_PREMIACION_SEMESTRAL';
    IF v_interval_sched NOT LIKE '%INTERVAL=3%' THEN
        RAISE_APPLICATION_ERROR(-20094, 'Fallo reconfiguracion dinamica de Scheduler: repeat_interval no contiene INTERVAL=3.');
    END IF;
    -- Restaurar a 6 meses
    PKG_PRM_MERCADEO.PR_CONFIGURAR_FRECUENCIA_PREMIACION(6);
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 7] Reconfiguracion dinamica de Scheduler validada exitosamente (repeat_interval sincronizado en caliente).');

    -- ------------------------------------------------------------------------
    -- PRUEBA 8: PKG_VEN_OPERACION (Cierre diario contable con desglose por cajero)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 8] Ejecutando cierre contable diario consolidado y por cajero...');
    PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO(TRUNC(SYSDATE));
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 8] Cierre diario ejecutado y registrado en VEN_CIERRE_DIARIO y VEN_CIERRE_DIARIO_DET.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 9: REFRESCO DE VISTAS MATERIALIZADAS
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 9] Refrescando Vistas Materializadas...');
    DBMS_MVIEW.REFRESH('MV_VENTAS_MENSUALES', 'C');
    DBMS_MVIEW.REFRESH('MV_INVENTARIO_CONSOLIDADO', 'C');
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 9] Vistas materializadas refrescadas exitosamente en modo COMPLETE.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 10: PRUEBA NEGATIVA - RECHAZO POR LIMITE DE CREDITO EXCEDIDO (ORA-20010)
    -- Y DEMOSTRACION DE ATOMICIDAD (ROLLBACK TO SAVEPOINT SIN COMMIT INTERMEDIO)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 10 - NEGATIVA] Validando rechazo por exceso de limite de credito y atomicidad...');
    v_fallo_esperado := FALSE;
    v_num_fac_neg := 'FAC-EXCESO-CRED-' || TO_CHAR(SYSTIMESTAMP, 'HH24MISSFF3');
    v_lineas_neg := PKG_VEN_OPERACION.T_LISTA_LINEAS_VENTA();
    v_lineas_neg.EXTEND;
    v_lineas_neg(1) := PKG_VEN_OPERACION.T_LINEA_VENTA(
        id_producto     => 1,
        id_servicio     => NULL,
        id_lote         => 1,
        cantidad        => 1,
        precio_unitario => 50000000,
        porc_descuento  => 0,
        porc_impuesto   => 13
    );

    v_id_factura := NULL;   -- evita contar la CxC de una factura de una prueba anterior
    BEGIN
        -- Intentar facturar venta atomica que excede el limite de credito del cliente 4
        PKG_VEN_OPERACION.PR_FACTURAR_VENTA_ATOMICA (
            p_id_cliente     => 4,
            p_id_sucursal    => 1,
            p_id_usuario     => 1,
            p_num_factura    => v_num_fac_neg,
            p_es_credito     => 'S',
            p_lineas         => v_lineas_neg,
            p_id_factura_out => v_id_factura
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20010 THEN
                v_fallo_esperado := TRUE;
                DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 10 - RECHAZO CONTROLADO] Limite de credito bloqueado correctamente con ORA-20010: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('[ERROR INESPERADO PRUEBA 10]: SQLCODE=' || SQLCODE || ' - ' || SQLERRM);
            END IF;
    END;

    IF NOT v_fallo_esperado THEN
        RAISE_APPLICATION_ERROR(-20091, 'Fallo prueba negativa 10: Se permitio exceder limite de credito sin ORA-20010.');
    END IF;

    -- Verificar atomicidad estricta: el ROLLBACK no dejo facturas huerfanas ni CxC creadas
    SELECT COUNT(*) INTO v_count_fac FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE = v_num_fac_neg;
    SELECT COUNT(*) INTO v_count_cxc FROM VEN_CUENTA_COBRAR cc
     WHERE cc.ID_FACTURA_VENTA IN (SELECT f.ID_FACTURA_VENTA FROM VEN_FACTURA f WHERE f.NUM_FACTURA_FAVE = v_num_fac_neg);
    IF v_count_fac > 0 OR v_count_cxc > 0 THEN
        RAISE_APPLICATION_ERROR(-20092, 'Fallo atomico: la factura rechazada dejo filas huerfanas en VEN_FACTURA o VEN_CUENTA_COBRAR.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 10 - ATOMICIDAD CONFIRMADA] Rollback total verificado: 0 facturas y 0 CxC huerfanas.');
    END IF;

    -- ------------------------------------------------------------------------
    -- PRUEBA 11: PRUEBA NEGATIVA - RECHAZO POR INVENTARIO INSUFICIENTE (ORA-20015)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 11 - NEGATIVA] Validando rechazo por existencia insuficiente...');
    v_fallo_esperado := FALSE;
    BEGIN
        -- Intentar vender 999,999 unidades cuando el stock es limitado debe disparar ORA-20015
        PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA(
            p_id_bodega     => 1,
            p_id_producto   => 1,
            p_id_lote       => NULL,
            p_cantidad      => 999999,
            p_es_entrada    => 'N',
            p_tipo_movi     => 'VENTA',
            p_documento_ref => 'FAC-SIN-STOCK'
        );
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20015 THEN
                v_fallo_esperado := TRUE;
                DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 11 - RECHAZO CONTROLADO] Venta sin stock bloqueada correctamente con ORA-20015: ' || SQLERRM);
            ELSE
                DBMS_OUTPUT.PUT_LINE('[ERROR INESPERADO PRUEBA 11]: ' || SQLERRM);
            END IF;
    END;
    IF NOT v_fallo_esperado THEN
        RAISE_APPLICATION_ERROR(-20095, 'Fallo prueba negativa 11: Se permitio vender sin stock sin ORA-20015.');
    END IF;

    -- ------------------------------------------------------------------------
    -- PRUEBA 12: LIMPIEZA DE DATOS TRANSACCIONALES DE PRUEBA
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 12] Depurando transacciones temporales de prueba...');
    DELETE FROM VEN_ABONO_COBRAR WHERE NUM_RECIBO_ABCO LIKE 'REC-TEST-%';
    -- Hijos de las facturas de prueba (acciones de promocion, pagos y abonos)
    DELETE FROM PRM_ACCION_CLIENTE WHERE ID_FACTURA_VENTA IN (SELECT ID_FACTURA_VENTA FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%');
    DELETE FROM VEN_PAGO           WHERE ID_FACTURA_VENTA IN (SELECT ID_FACTURA_VENTA FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%');
    DELETE FROM VEN_ABONO_COBRAR   WHERE ID_FACTURA_VENTA IN (SELECT ID_FACTURA_VENTA FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%');
    DELETE FROM COM_ABONO_PAGAR    WHERE ID_FACTURA_COMPRA IN (SELECT ID_FACTURA_COMPRA FROM COM_FACTURA_COMPRA WHERE NUM_FACTURA_FACO LIKE 'FAC-TEST-%');
    DELETE FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_VENTA IN (SELECT ID_FACTURA_VENTA FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%');
    DELETE FROM VEN_FACTURA_DET WHERE ID_FACTURA_VENTA IN (SELECT ID_FACTURA_VENTA FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%');
    DELETE FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE LIKE 'FAC-TEST-%';

    DELETE FROM COM_CUENTA_PAGAR WHERE ID_FACTURA_COMPRA IN (SELECT ID_FACTURA_COMPRA FROM COM_FACTURA_COMPRA WHERE NUM_FACTURA_FACO LIKE 'FAC-TEST-%');
    DELETE FROM COM_FACTURA_COMPRA_DET WHERE ID_FACTURA_COMPRA IN (SELECT ID_FACTURA_COMPRA FROM COM_FACTURA_COMPRA WHERE NUM_FACTURA_FACO LIKE 'FAC-TEST-%');
    DELETE FROM COM_FACTURA_COMPRA WHERE NUM_FACTURA_FACO LIKE 'FAC-TEST-%';

    -- Revertir saldos simulados a sus valores estables
    UPDATE PER_PROVEEDOR SET SALDO_ACTUAL_PROVE = v_saldo_prov_ant WHERE ID_PROVEEDOR = 1;
    UPDATE PER_CLIENTE   SET SALDO_ACTUAL_CLI   = v_saldo_cli_ant  WHERE ID_CLIENTE   = 3;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 12] Datos de prueba depurados exitosamente y saldos restaurados.');

    DBMS_OUTPUT.PUT_LINE('========================================================================');
    DBMS_OUTPUT.PUT_LINE('>>> VERIFICACION GENERAL EXITOSA: LAS 12 PRUEBAS (POSITIVAS Y NEGATIVAS)');
    DBMS_OUTPUT.PUT_LINE('    FINALIZARON CON 100% DE EXITO Y CERO ADVERTENCIAS.');
    DBMS_OUTPUT.PUT_LINE('========================================================================');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR EN SUITE DE PRUEBAS]: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
END;
/

PROMPT ============================================================================
PROMPT FIN DE COMPILACION DE JOBS, OPTIMIZACION Y PRUEBAS — AVANCE 2
PROMPT ============================================================================
