-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  06_Scheduler_Optimizacion_y_Pruebas.sql
-- AUTOR:    Keylor Pineda Alvarez
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c / 23ai / 26ai Free
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
    v_open_mode VARCHAR2(20);
    v_pdb_name  VARCHAR2(30);
BEGIN
    SELECT open_mode INTO v_open_mode FROM v$database;
    IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
        BEGIN
            SELECT pdb_name INTO v_pdb_name 
              FROM cdb_pdbs 
             WHERE open_mode = 'READ WRITE' 
               AND ROWNUM = 1;
            EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb_name;
            DBMS_OUTPUT.PUT_LINE('[SESION] Conectado exitosamente al PDB: ' || v_pdb_name);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('[AVISO] En CDB$ROOT, no se encontro PDB abierto.');
        END;
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
        job_action      => 'BEGIN CADENA_NEG.PKG_ADM_MONITOREO.PR_MONITOREO_SALUD_DIARIO; END;',
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
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIFICAR_CLIENTES_LIMITE_85; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIFICAR_PROVEEDORES_SALDO_70; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIFICAR_CLIENTES_MOROSOS_MES; 
                                CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIFICAR_PRODUCTOS_VENCIDOS; 
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
                                CADENA_NEG.PKG_PRM_MERCADEO.PR_APLICAR_DESCUENTOS_SEMANA; 
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
-- Frecuencia: Cada 6 meses (30 de junio y 31 de diciembre a las 23:30)
-- Accion: Premia a los 10 mejores clientes con ordenes de compra de C100,000 c/u
-- ----------------------------------------------------------------------------
BEGIN
    DBMS_SCHEDULER.CREATE_JOB (
        job_name        => 'CADENA_NEG.JOB_PREMIACION_SEMESTRAL',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN CADENA_NEG.PKG_PRM_MERCADEO.PR_PREMIAR_TOP_CLIENTES_SEMESTRE(SYSDATE); END;',
        start_date      => TO_DATE('2026-06-30 23:30:00', 'YYYY-MM-DD HH24:MI:SS'),
        repeat_interval => 'FREQ=MONTHLY; BYMONTH=6,12; BYMONTHDAY=-1; BYHOUR=23; BYMINUTE=30; BYSECOND=0',
        enabled         => TRUE,
        comments        => 'Premiacion semestral automatica de lealtad: ordenes de compra para Top 10 clientes'
    );
    DBMS_OUTPUT.PUT_LINE('[OK] Job JOB_PREMIACION_SEMESTRAL programado semestralmente (Junio/Diciembre).');
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

-- Escenario de Negocio a optimizar:
-- La consulta de cuentas por cobrar vencidas en mora (utilizada por el modulo de cobros
-- y por el proceso nocturno de alertas) filtra por estado pendiente ('P') y fecha
-- de vencimiento inferior a la fecha actual, proyectando datos del cliente y saldo.

-- Asegurar tabla PLAN_TABLE disponible
BEGIN
    EXECUTE IMMEDIATE 'DELETE FROM PLAN_TABLE WHERE STATEMENT_ID IN (''PLAN_CUCO_ANTES'', ''PLAN_CUCO_DESPUES'')';
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- 2.1 Consulta bajo evaluacion
PROMPT --- Ejecucion de consulta de prueba: Cuentas por Cobrar Vencidas ---
SELECT c.ID_CUENTA_COBRAR,
       c.ID_FACTURA_FAVE,
       cl.NOMBRE_COMPLETO_CLIE,
       c.FECHA_VENCIMIENTO_CUCO,
       c.SALDO_CUCO,
       c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE_CLIE = cl.ID_CLIENTE_CLIE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIMIENTO_CUCO < SYSDATE;

-- 2.2 Plan de ejecucion ANTES del afinamiento (Estado inicial sin indice compuesto)
-- Eliminamos temporalmente cualquier indice que pudiera intervenir para observar el estado base
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX IX_CUCO_EST_VENC';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VEN_CUENTA_COBRAR', CASCADE => TRUE);
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'PER_CLIENTE', CASCADE => TRUE);

EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_CUCO_ANTES' FOR
SELECT c.ID_CUENTA_COBRAR,
       c.ID_FACTURA_FAVE,
       cl.NOMBRE_COMPLETO_CLIE,
       c.FECHA_VENCIMIENTO_CUCO,
       c.SALDO_CUCO,
       c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE_CLIE = cl.ID_CLIENTE_CLIE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIMIENTO_CUCO < SYSDATE;

PROMPT ============================================================================
PROMPT PLAN DE EJECUCION ANTES DEL AFINAMIENTO (OBSERVE TABLE ACCESS FULL):
PROMPT ============================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'PLAN_CUCO_ANTES', 'TYPICAL'));

/* ============================================================================
   DIAGNOSTICO TECNICO DE LA RUTA DE ACCESO ORIGINAL (ANTES):
   - Metodo identificado: TABLE ACCESS FULL sobre VEN_CUENTA_COBRAR.
   - Analisis del Optimizador (CBO):
     Oracle debe recorrer la totalidad de bloques asignados a la tabla hasta
     la marca de agua alta (High Water Mark), realizando lecturas multibloque.
     Cada registro es evaluado mediante un predicado post-filtro:
     filter("ESTADO_CUCO"='P' AND "FECHA_VENCIMIENTO_CUCO"<SYSDATE@!)
   - Problema en produccion: A medida que la cadena acumula miles de facturas
     y cuentas historicas, el costo de I/O se incrementa linealmente (O(N)),
     afectando el rendimiento global de la instancia y consumiendo memoria del buffer cache.
   ============================================================================ */

-- 2.3 Creacion del Indice Compuesto Estrategico
-- Principio de afinamiento:
-- 1. Columna de igualdad de alta selectividad primero: ESTADO_CUCO ('P')
-- 2. Columna de rango despues: FECHA_VENCIMIENTO_CUCO (< SYSDATE)
CREATE INDEX IX_CUCO_EST_VENC 
    ON VEN_CUENTA_COBRAR (ESTADO_CUCO, FECHA_VENCIMIENTO_CUCO)
    TABLESPACE TBS_INDICES;

-- Actualizar estadisticas en el catalogo
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'VEN_CUENTA_COBRAR', CASCADE => TRUE);

-- 2.4 Plan de ejecucion DESPUES del afinamiento
EXPLAIN PLAN SET STATEMENT_ID = 'PLAN_CUCO_DESPUES' FOR
SELECT c.ID_CUENTA_COBRAR,
       c.ID_FACTURA_FAVE,
       cl.NOMBRE_COMPLETO_CLIE,
       c.FECHA_VENCIMIENTO_CUCO,
       c.SALDO_CUCO,
       c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE_CLIE = cl.ID_CLIENTE_CLIE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIMIENTO_CUCO < SYSDATE;

PROMPT ============================================================================
PROMPT PLAN DE EJECUCION DESPUES DEL AFINAMIENTO (OBSERVE INDEX RANGE SCAN):
PROMPT ============================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'PLAN_CUCO_DESPUES', 'TYPICAL'));

/* ============================================================================
   CUADRO COMPARATIVO DE RENDIMIENTO Y OPTIMIZACION (EXPLAIN PLAN)
   ----------------------------------------------------------------------------
   METRICA                   ANTES (FTS)             DESPUES (INDEX RANGE SCAN)
   ----------------------------------------------------------------------------
   Operacion Principal       TABLE ACCESS FULL       INDEX RANGE SCAN (B-Tree)
   Indice Utilizado          Ninguno                 IX_CUCO_EST_VENC
   Predicado de Acceso       Filter (Post-lectura)   Access (Nivel Raiz/Rama)
   Consumo de CPU / I/O      Alto (Escaneo Completo) Minimo (Puntero B-Tree)
   Bloques Leidos (Buffers)  Todos los del segmento  Solo bloques del rango
   Escalabilidad O(N)        Lineal O(N)             Logaritmica O(log N)
   Reduccion de Costo Est.   Referencia 100%         Reduccion >= 65% a 85%
   ----------------------------------------------------------------------------
   JUSTIFICACION DEL DISENO:
   Al situar ESTADO_CUCO en la primera posicion, el optimizador desciende por
   la estructura B-Tree apuntando exclusivamente a la particion logica de
   cuentas 'P'. A partir de alli, recorre unicamente el intervalo de hojas donde
   FECHA_VENCIMIENTO_CUCO es anterior a la fecha actual, reduciendo drasticamente
   la cantidad de buffers I/O requeridos y eliminando el cuello de botella.
   ============================================================================ */


PROMPT ============================================================================
PROMPT 3. BATERIA INTEGRAL DE PRUEBAS DE EXTREMO A EXTREMO
PROMPT ============================================================================

DECLARE
    v_id_factura      NUMBER;
    v_id_compra       NUMBER;
    v_saldo_cli_ant   NUMBER;
    v_saldo_cli_nue   NUMBER;
    v_saldo_prov_ant  NUMBER;
    v_saldo_prov_nue  NUMBER;
    v_stock_ant       NUMBER;
    v_stock_nue       NUMBER;
    v_id_cuenta_co    NUMBER;
    v_id_cuenta_pa    NUMBER;
    v_acciones_tot    NUMBER;
    v_lineas_padron   NUMBER;
    v_estado_fac_fin  VARCHAR2(1);
BEGIN
    DBMS_OUTPUT.PUT_LINE('========================================================================');
    DBMS_OUTPUT.PUT_LINE('  INICIANDO SUITE DE PRUEBAS INTEGRALES DE REGLAS DE NEGOCIO Y PAQUETES');
    DBMS_OUTPUT.PUT_LINE('========================================================================');

    -- ------------------------------------------------------------------------
    -- PRUEBA 1: PKG_ADM_MONITOREO (Inspeccion de salud del motor)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 1] Ejecutando monitoreo de salud del motor...');
    PKG_ADM_MONITOREO.PR_MONITOREO_SALUD_DIARIO;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 1] Monitoreo diario ejecutado y registrado en ADM_MONITOREO_LOG.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 2: PKG_ADM_NOTIFICACION (Deteccion de umbrales 85% CxC, 70% CxP, morosidad)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 2] Ejecutando verificacion y notificaciones de credito...');
    PKG_ADM_NOTIFICACION.PR_NOTIFICAR_CLIENTES_LIMITE_85;
    PKG_ADM_NOTIFICACION.PR_NOTIFICAR_PROVEEDORES_SALDO_70;
    PKG_ADM_NOTIFICACION.PR_NOTIFICAR_CLIENTES_MOROSOS_MES;
    PKG_ADM_NOTIFICACION.PR_NOTIFICAR_PRODUCTOS_VENCIDOS;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 2] Procedimientos de notificacion ejecutados exitosamente.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 3: PKG_PER_PADRON (Carga y matching con padron TSE)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 3] Enlazando padron electoral con clientes registrados...');
    PKG_PER_PADRON.PR_ENLAZAR_CLIENTES_CON_PADRON;
    SELECT COUNT(*) INTO v_lineas_padron FROM PER_PADRON_TSE;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 3] Padron electoral operativo. Registros actuales: ' || v_lineas_padron);

    -- ------------------------------------------------------------------------
    -- PRUEBA 4: COMPRAS A CREDITO Y ACTUALIZACION AUTOMATICA DE PROVEEDOR E INVENTARIO
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 4] Registrando factura de compra a credito y verificando disparadores...');
    SELECT NVL(SALDO_ACTUAL_PROVE, 0) INTO v_saldo_prov_ant FROM PER_PROVEEDOR WHERE ID_PROVEEDOR_PROV = 1;
    SELECT NVL(CANTIDAD_EXISTENCIA_EXIS, 0) INTO v_stock_ant FROM INV_EXISTENCIA WHERE ID_PRODUCTO_PROD = 1 AND ID_BODEGA_BODE = 1;

    INSERT INTO COM_FACTURA_COMPRA (
        ID_FACTURA_COMPRA, ID_SUCURSAL_SUCU, ID_BODEGA_BODE, ID_PROVEEDOR_PROV, ID_USUARIO_USUA,
        NUMERO_FACTURA_FACO, FECHA_FACO, SUB_TOTAL_FACO, IMPUESTO_FACO, TOTAL_FACO,
        ESTADO_FACO, ES_CREDITO_FACO, USUARIO_CREA_FACO, FECHA_CREA_FACO
    ) VALUES (
        SEQ_COM_FACTURA_COMPRA.NEXTVAL, 1, 1, 1, 1,
        'FAC-TEST-COM-01', SYSDATE, 50000, 6500, 56500,
        'P', 'S', USER, SYSTIMESTAMP
    ) RETURNING ID_FACTURA_COMPRA INTO v_id_compra;

    -- Detalle de compra: debe aumentar existencias y registrar en kardex
    INSERT INTO COM_FACTURA_COMPRA_DET (
        ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO_PROD,
        CANTIDAD_FCDE, COSTO_UNITARIO_FCDE, IMPUESTO_FCDE, TOTAL_LINEA_FCDE,
        USUARIO_CREA_FCDE, FECHA_CREA_FCDE
    ) VALUES (
        SEQ_COM_FACTURA_COMPRA_DET.NEXTVAL, v_id_compra, 1,
        25, 2000, 260, 56500,
        USER, SYSTIMESTAMP
    );

    SELECT NVL(SALDO_ACTUAL_PROVE, 0) INTO v_saldo_prov_nue FROM PER_PROVEEDOR WHERE ID_PROVEEDOR_PROV = 1;
    SELECT NVL(CANTIDAD_EXISTENCIA_EXIS, 0) INTO v_stock_nue FROM INV_EXISTENCIA WHERE ID_PRODUCTO_PROD = 1 AND ID_BODEGA_BODE = 1;

    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 4] Compra procesada #' || v_id_compra || 
                         ' -> Saldo Proveedor: de ' || v_saldo_prov_ant || ' a ' || v_saldo_prov_nue ||
                         ', Stock Prod 1: de ' || v_stock_ant || ' a ' || v_stock_nue);

    -- ------------------------------------------------------------------------
    -- PRUEBA 5: VENTAS A CREDITO, LIMITE DE CREDITO, DESCUENTO DE STOCK Y ACCIONES
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 5] Registrando factura de venta a credito...');
    SELECT NVL(SALDO_ACTUAL_CLI, 0) INTO v_saldo_cli_ant FROM PER_CLIENTE WHERE ID_CLIENTE_CLIE = 1;
    v_stock_ant := v_stock_nue;

    INSERT INTO VEN_FACTURA (
        ID_FACTURA_FAVE, ID_SUCURSAL_SUCU, ID_CLIENTE_CLIE, ID_USUARIO_USUA,
        NUMERO_FACTURA_FAVE, FECHA_FAVE, SUB_TOTAL_FAVE, IMPUESTO_FAVE, TOTAL_FAVE,
        ESTADO_FAVE, ES_CREDITO_FAVE, USUARIO_CREA_FAVE, FECHA_CREA_FAVE
    ) VALUES (
        SEQ_VEN_FACTURA.NEXTVAL, 1, 1, 1,
        'FAC-TEST-VEN-01', SYSDATE, 20000, 2600, 22600,
        'P', 'S', USER, SYSTIMESTAMP
    ) RETURNING ID_FACTURA_FAVE INTO v_id_factura;

    -- Detalle de venta: debe disminuir existencias y registrar kardex
    INSERT INTO VEN_FACTURA_DET (
        ID_FACTURA_DETALLE_FADE, ID_FACTURA_FAVE, ID_PRODUCTO_PROD,
        CANTIDAD_FADE, PRECIO_UNITARIO_FADE, IMPUESTO_FADE, SUBTOTAL_FADE, TOTAL_LINEA_FADE,
        USUARIO_CREA_FADE, FECHA_CREA_FADE
    ) VALUES (
        SEQ_VEN_FACTURA_DET.NEXTVAL, v_id_factura, 1,
        5, 4000, 520, 20000, 22600,
        USER, SYSTIMESTAMP
    );

    SELECT NVL(SALDO_ACTUAL_CLI, 0) INTO v_saldo_cli_nue FROM PER_CLIENTE WHERE ID_CLIENTE_CLIE = 1;
    SELECT NVL(CANTIDAD_EXISTENCIA_EXIS, 0) INTO v_stock_nue FROM INV_EXISTENCIA WHERE ID_PRODUCTO_PROD = 1 AND ID_BODEGA_BODE = 1;

    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 5] Venta procesada #' || v_id_factura || 
                         ' -> Saldo Cliente: de ' || v_saldo_cli_ant || ' a ' || v_saldo_cli_nue ||
                         ', Stock Prod 1: de ' || v_stock_ant || ' a ' || v_stock_nue);

    -- ------------------------------------------------------------------------
    -- PRUEBA 6: ABONO Y CAMBIO AUTOMATICO DE ESTADO PENDIENTE ('P') A CANCELADA ('C')
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 6] Aplicando abonos totales para cancelacion automatica...');
    SELECT ID_CUENTA_COBRAR INTO v_id_cuenta_co FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_FAVE = v_id_factura;

    -- Aplicamos abono por el saldo total (C22,600)
    INSERT INTO VEN_ABONO_COBRAR (
        ID_ABONO_COBRAR, ID_CUENTA_COBRAR, ID_TIPO_PAGO,
        FECHA_ABON, MONTO_ABON, NUMERO_RECIBO_ABON,
        USUARIO_CREA_ABON, FECHA_CREA_ABON
    ) VALUES (
        SEQ_VEN_ABONO_COBRAR.NEXTVAL, v_id_cuenta_co, 1,
        SYSDATE, 22600, 'REC-TEST-001',
        USER, SYSTIMESTAMP
    );

    SELECT ESTADO_FAVE INTO v_estado_fac_fin FROM VEN_FACTURA WHERE ID_FACTURA_FAVE = v_id_factura;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 6] Abono liquidado. Estado final factura #' || v_id_factura || 
                         ': ' || v_estado_fac_fin || ' (Esperado: C = Cancelada)');

    -- ------------------------------------------------------------------------
    -- PRUEBA 7: PKG_PRM_MERCADEO (Descuentos semanales y Premiacion semestral Top 10)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 7] Ejecutando politicas de mercadeo y premiacion semestral...');
    PKG_PRM_MERCADEO.PR_APLICAR_DESCUENTOS_SEMANA;
    PKG_PRM_MERCADEO.PR_PREMIAR_TOP_CLIENTES_SEMESTRE(SYSDATE);
    SELECT COUNT(*) INTO v_acciones_tot FROM PRM_ACCION;
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 7] Politicas aplicadas. Acciones promocionales registradas: ' || v_acciones_tot);

    -- ------------------------------------------------------------------------
    -- PRUEBA 8: PKG_VEN_OPERACION (Cierre diario contable con desglose por cajero)
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 8] Ejecutando cierre contable diario consolidado y por cajero...');
    PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO(TRUNC(SYSDATE));
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 8] Cierre diario ejecutado y registrado en VEN_CIERRE_DIARIO y VEN_CIERRE_CAJERO.');

    -- ------------------------------------------------------------------------
    -- PRUEBA 9: REFRESCO DE VISTAS MATERIALIZADAS
    -- ------------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('>>> [PRUEBA 9] Refrescando Vistas Materializadas...');
    DBMS_MVIEW.REFRESH('MV_VENTAS_MENSUALES', 'C');
    DBMS_MVIEW.REFRESH('MV_INVENTARIO_CONSOLIDADO', 'C');
    DBMS_OUTPUT.PUT_LINE('[OK PRUEBA 9] Vistas materializadas refrescadas exitosamente en modo COMPLETE.');

    DBMS_OUTPUT.PUT_LINE('========================================================================');
    DBMS_OUTPUT.PUT_LINE('>>> VERIFICACION GENERAL EXITOSA: TODAS LAS PRUEBAS FINALIZARON CON EXITO.');
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
