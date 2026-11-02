--------------------------------------------------------------------------------
-- UNIVERSIDAD NACIONAL - SEDE REGIONAL BRUNCA
-- ADMINISTRACION DE BASES DE DATOS - II CICLO 2026
-- PROYECTO: BASE DE DATOS PARA UNA CADENA DE NEGOCIOS
-- ESTUDIANTE: KEYLOR PINEDA ALVAREZ
-- ENTREGABLE #2 - ARCHIVO 03: PAQUETES DE NEGOCIO (PADRON, INVENTARIO, COMPRAS,
--                             VENTAS, CIERRE DIARIO, MERCADEO) Y MONITOREO
--
-- REQUISITO PREVIO: Haber ejecutado 01 y 02.
-- ORDEN DE EJECUCION: 01 -> 02 -> 03 -> 04 -> 05 -> 06
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

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
    END IF;
END;
/

ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;

--------------------------------------------------------------------------------
-- 1. PAQUETE: PKG_PER_PADRON
--    Carga automatica del Padron Nacional Electoral (TSE) con UTL_FILE
--    y enlace automatico con PER_PERSONA, PER_PERSONA_FISICA y PER_CLIENTE.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_PER_PADRON IS

    -- Genera un archivo de padron electoral en formato oficial TSE dentro de DIR_PADRON
    PROCEDURE PR_GENERAR_ARCHIVO_PADRON_TSE (
        p_directorio IN VARCHAR2 DEFAULT 'DIR_PADRON',
        p_archivo    IN VARCHAR2 DEFAULT 'PADRON_COMPLETO.TXT'
    );

    -- Carga automaticamente el Padron Nacional desde un archivo de texto (formato TSE)
    PROCEDURE PR_CARGAR_PADRON_TSE (
        p_directorio IN VARCHAR2 DEFAULT 'DIR_PADRON',
        p_archivo    IN VARCHAR2 DEFAULT 'PADRON_COMPLETO.TXT'
    );

    -- Registra o sincroniza un cliente nacional obteniendo sus datos basicos desde CAT_PADRON
    PROCEDURE PR_CREAR_CLIENTE_DESDE_PADRON (
        p_cedula            IN  VARCHAR2,
        p_codigo_cli        IN  VARCHAR2,
        p_es_preferencial   IN  VARCHAR2 DEFAULT 'N',
        p_monto_max_credito IN  NUMBER   DEFAULT 0,
        p_dias_credito      IN  NUMBER   DEFAULT 0,
        p_id_cliente_out    OUT NUMBER
    );

END PKG_PER_PADRON;
/
SHOW ERRORS PACKAGE PKG_PER_PADRON;

CREATE OR REPLACE PACKAGE BODY PKG_PER_PADRON IS

    FUNCTION obtener_campo (
        p_linea IN VARCHAR2,
        p_pos   IN NUMBER
    ) RETURN VARCHAR2 IS
        v_tmp VARCHAR2(4000) := p_linea || ',';
        v_ini NUMBER;
        v_fin NUMBER;
    BEGIN
        IF p_pos = 1 THEN
            v_ini := 1;
        ELSE
            v_ini := INSTR(v_tmp, ',', 1, p_pos - 1) + 1;
        END IF;

        v_fin := INSTR(v_tmp, ',', 1, p_pos);
        IF v_fin = 0 THEN
            RETURN NULL;
        END IF;

        RETURN TRIM(SUBSTR(v_tmp, v_ini, v_fin - v_ini));
    END obtener_campo;

    PROCEDURE PR_GENERAR_ARCHIVO_PADRON_TSE (
        p_directorio IN VARCHAR2 DEFAULT 'DIR_PADRON',
        p_archivo    IN VARCHAR2 DEFAULT 'PADRON_COMPLETO.TXT'
    ) IS
        v_arch UTL_FILE.FILE_TYPE;
    BEGIN
        v_arch := UTL_FILE.FOPEN(p_directorio, p_archivo, 'W', 32767);

        -- Formato oficial de 8 columnas del TSE:
        -- CEDULA,CODELEC,SEXO_O_RELLENO,FECHACADUC(YYYYMMDD),JUNTA,NOMBRE,APELLIDO1,APELLIDO2
        UTL_FILE.PUT_LINE(v_arch, 'CEDULA,CODELEC,SEXO,FECHACADUC,JUNTA,NOMBRE,APELLIDO1,APELLIDO2');
        UTL_FILE.PUT_LINE(v_arch, '118540236,119001,O,20300210,00001,CLIENTE,CONTADO,GENERICO');
        UTL_FILE.PUT_LINE(v_arch, '603780145,119001,F,20320614,00102,MARISOL,VARGAS,CHINCHILLA');
        UTL_FILE.PUT_LINE(v_arch, '110230458,119001,M,20310308,00105,KEYLOR,JIMENEZ,SANABRIA');
        UTL_FILE.PUT_LINE(v_arch, '119010234,119001,F,20340520,00108,SOFIA,CALDERON,MORA');
        UTL_FILE.PUT_LINE(v_arch, '604550789,610001,M,20330815,00203,CARLOS,MONGE,HIDALGO');
        UTL_FILE.PUT_LINE(v_arch, '607110432,607001,F,20321012,00305,ANDREA,SALAS,VILLALOBOS');
        UTL_FILE.PUT_LINE(v_arch, '116540987,603001,M,20350125,00401,RODRIGO,ZUNIGA,CHAVES');
        UTL_FILE.PUT_LINE(v_arch, '114320876,101001,F,20310930,00502,LAURA,CORDERO,FONSECA');

        UTL_FILE.FCLOSE(v_arch);
        DBMS_OUTPUT.PUT_LINE('[OK] Archivo de padron TSE generado en ' || p_directorio || '/' || p_archivo);
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(v_arch) THEN
                UTL_FILE.FCLOSE(v_arch);
            END IF;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_GENERAR_ARCHIVO_PADRON_TSE', SQLCODE, SQLERRM);
            RAISE;
    END PR_GENERAR_ARCHIVO_PADRON_TSE;

    PROCEDURE PR_CARGAR_PADRON_TSE (
        p_directorio IN VARCHAR2 DEFAULT 'DIR_PADRON',
        p_archivo    IN VARCHAR2 DEFAULT 'PADRON_COMPLETO.TXT'
    ) IS
        v_archivo      UTL_FILE.FILE_TYPE;
        v_linea        VARCHAR2(4000);
        v_num_linea    NUMBER := 0;

        v_cedula       VARCHAR2(30);
        v_codelec      VARCHAR2(20);
        v_sexo         VARCHAR2(10);
        v_fechacaduc   VARCHAR2(20);
        v_junta        VARCHAR2(20);
        v_nombre       VARCHAR2(100);
        v_ape1         VARCHAR2(100);
        v_ape2         VARCHAR2(100);
        v_fecha_venc   DATE;
        v_id_distrito  NUMBER(10);

        v_correctos    NUMBER := 0;
        v_errores      NUMBER := 0;
        v_total        NUMBER := 0;
        v_msg_error    VARCHAR2(300);
        e_validacion   EXCEPTION;
    BEGIN
        SAVEPOINT sp_inicio_padron;

        v_archivo := UTL_FILE.FOPEN(p_directorio, p_archivo, 'R', 32767);

        LOOP
            BEGIN
                UTL_FILE.GET_LINE(v_archivo, v_linea);
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    EXIT;
            END;

            v_num_linea := v_num_linea + 1;

            -- Omitir encabezado en linea 1 o lineas en blanco
            IF v_num_linea = 1 AND UPPER(v_linea) LIKE 'CEDULA%' THEN
                CONTINUE;
            END IF;

            IF TRIM(REPLACE(v_linea, CHR(13), '')) IS NULL THEN
                CONTINUE;
            END IF;

            v_linea := REPLACE(v_linea, CHR(13), '');
            v_total := v_total + 1;

            BEGIN
                v_cedula     := obtener_campo(v_linea, 1);
                v_codelec    := obtener_campo(v_linea, 2);
                v_sexo       := obtener_campo(v_linea, 3);
                v_fechacaduc := obtener_campo(v_linea, 4);
                v_junta      := NVL(obtener_campo(v_linea, 5), '00000');
                v_nombre     := obtener_campo(v_linea, 6);
                v_ape1       := obtener_campo(v_linea, 7);
                v_ape2       := obtener_campo(v_linea, 8);

                IF v_cedula IS NULL OR NOT REGEXP_LIKE(v_cedula, '^[1-9][0-9]{8}$') THEN
                    v_msg_error := 'Cedula invalida en linea ' || v_num_linea || ': ' || NVL(v_cedula, 'NULL');
                    RAISE e_validacion;
                END IF;

                IF v_nombre IS NULL OR v_ape1 IS NULL THEN
                    v_msg_error := 'Nombre o primer apellido vacio en linea ' || v_num_linea;
                    RAISE e_validacion;
                END IF;

                v_sexo := CASE
                              WHEN UPPER(v_sexo) IN ('M','F','O') THEN UPPER(v_sexo)
                              WHEN v_sexo = '1' THEN 'M'
                              WHEN v_sexo = '2' THEN 'F'
                              ELSE 'O'
                          END;

                BEGIN
                    v_fecha_venc := TO_DATE(v_fechacaduc, 'YYYYMMDD');
                EXCEPTION
                    WHEN OTHERS THEN
                        v_fecha_venc := ADD_MONTHS(TRUNC(SYSDATE), 60);
                END;

                -- Resolucion inteligente del distrito electoral a partir del CODELEC del TSE
                -- Estructura TSE: Digito 1=Provincia, 2-3=Canton, 4-6=Distrito Electoral
                BEGIN
                    SELECT ID_DISTRITO INTO v_id_distrito
                      FROM (
                          SELECT d.ID_DISTRITO
                            FROM CAT_DISTRITO d
                                 JOIN CAT_CANTON c ON c.ID_CANTON = d.ID_CANTON
                                 JOIN CAT_PROVINCIA p ON p.ID_PROVINCIA = c.ID_PROVINCIA
                           WHERE d.CODIGO_POSTAL_DIST = SUBSTR(v_codelec, 1, 3) || SUBSTR(v_codelec, 5, 2)
                              OR (p.CODIGO_PROV = SUBSTR(v_codelec, 1, 1) AND c.CODIGO_CANT = SUBSTR(v_codelec, 2, 2))
                           ORDER BY CASE WHEN d.CODIGO_POSTAL_DIST = SUBSTR(v_codelec, 1, 3) || SUBSTR(v_codelec, 5, 2) THEN 1 ELSE 2 END
                      )
                     WHERE ROWNUM = 1;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN
                        SELECT MIN(ID_DISTRITO) INTO v_id_distrito FROM CAT_DISTRITO;
                END;

                MERGE INTO CAT_PADRON dest
                USING (SELECT v_cedula AS CEDULA_PADR FROM dual) src
                   ON (dest.CEDULA_PADR = src.CEDULA_PADR)
                WHEN MATCHED THEN
                    UPDATE SET dest.COD_ELECTORAL_PADR   = SUBSTR(NVL(v_codelec, '101001'), 1, 6),
                               dest.SEXO_PADR            = v_sexo,
                               dest.FECHA_VENC_CED_PADR  = v_fecha_venc,
                               dest.JUNTA_RECEPTORA_PADR = SUBSTR(v_junta, 1, 5),
                               dest.NOMBRE_PADR          = SUBSTR(UPPER(v_nombre), 1, 40),
                               dest.APELLIDO1_PADR       = SUBSTR(UPPER(v_ape1), 1, 40),
                               dest.APELLIDO2_PADR       = SUBSTR(UPPER(v_ape2), 1, 40),
                               dest.USUARIO_MOD_PADR     = USER,
                               dest.FECHA_MOD_PADR       = SYSTIMESTAMP
                WHEN NOT MATCHED THEN
                    INSERT (
                        ID_PADRON, ID_DISTRITO, CEDULA_PADR, COD_ELECTORAL_PADR,
                        SEXO_PADR, FECHA_VENC_CED_PADR, JUNTA_RECEPTORA_PADR,
                        NOMBRE_PADR, APELLIDO1_PADR, APELLIDO2_PADR, ESTADO_PADR
                    ) VALUES (
                        SEQ_CAT_PADRON.NEXTVAL,
                        v_id_distrito,
                        v_cedula,
                        SUBSTR(NVL(v_codelec, '101001'), 1, 6),
                        v_sexo,
                        v_fecha_venc,
                        SUBSTR(v_junta, 1, 5),
                        SUBSTR(UPPER(v_nombre), 1, 40),
                        SUBSTR(UPPER(v_ape1), 1, 40),
                        SUBSTR(UPPER(v_ape2), 1, 40),
                        'A'
                    );

                v_correctos := v_correctos + 1;

                -- Compromiso por lotes de 500 registros para optimizar escalabilidad ante millones de filas del TSE
                IF MOD(v_correctos, 500) = 0 THEN
                    COMMIT;
                END IF;
            EXCEPTION
                WHEN e_validacion THEN
                    v_errores := v_errores + 1;
                    PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_CARGAR_PADRON_TSE', -20030, v_msg_error, v_linea);
                WHEN OTHERS THEN
                    v_errores := v_errores + 1;
                    PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_CARGAR_PADRON_TSE', SQLCODE, SQLERRM, v_linea);
            END;
        END LOOP;

        UTL_FILE.FCLOSE(v_archivo);
        COMMIT;

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
            p_tabla       => 'CAT_PADRON',
            p_llave       => p_archivo,
            p_operacion   => 'INSERT',
            p_modulo      => 'Padron',
            p_descripcion => 'Carga de Padron TSE finalizada. Correctos: ' || v_correctos || ', Errores: ' || v_errores
        );

        DBMS_OUTPUT.PUT_LINE('============================================================');
        DBMS_OUTPUT.PUT_LINE('  CARGA AUTOMATICA DEL PADRON NACIONAL (TSE) - SUPER BRUNCA');
        DBMS_OUTPUT.PUT_LINE('============================================================');
        DBMS_OUTPUT.PUT_LINE('Archivo procesado     : ' || p_archivo);
        DBMS_OUTPUT.PUT_LINE('Registros correctos   : ' || v_correctos);
        DBMS_OUTPUT.PUT_LINE('Registros con errores : ' || v_errores);
        DBMS_OUTPUT.PUT_LINE('Total procesados      : ' || v_total);
        DBMS_OUTPUT.PUT_LINE('============================================================');
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(v_archivo) THEN
                UTL_FILE.FCLOSE(v_archivo);
            END IF;
            ROLLBACK TO sp_inicio_padron;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_CARGAR_PADRON_TSE', SQLCODE, SQLERRM);
            RAISE;
    END PR_CARGAR_PADRON_TSE;

    PROCEDURE PR_CREAR_CLIENTE_DESDE_PADRON (
        p_cedula            IN  VARCHAR2,
        p_codigo_cli        IN  VARCHAR2,
        p_es_preferencial   IN  VARCHAR2 DEFAULT 'N',
        p_monto_max_credito IN  NUMBER   DEFAULT 0,
        p_dias_credito      IN  NUMBER   DEFAULT 0,
        p_id_cliente_out    OUT NUMBER
    ) IS
        r_padron    CAT_PADRON%ROWTYPE;
        v_id_pers   NUMBER(10);
        v_id_pais   NUMBER(10);
        v_existe    NUMBER;
    BEGIN
        SAVEPOINT sp_cliente_padron;

        -- Control de concurrencia sobre el registro del padron
        SELECT * INTO r_padron
          FROM CAT_PADRON
         WHERE CEDULA_PADR = TRIM(p_cedula)
           AND ESTADO_PADR = 'A'
           FOR UPDATE WAIT 5;

        SELECT MIN(ID_PAIS) INTO v_id_pais FROM CAT_PAIS WHERE CODIGO_ISO_PAIS = 'CRI';

        -- Verificar si la persona ya existe en PER_PERSONA
        SELECT COUNT(*) INTO v_existe
          FROM PER_PERSONA
         WHERE TIPO_PERS = 'N'
           AND NUM_IDENTIFICACION_PERS = r_padron.CEDULA_PADR;

        IF v_existe = 0 THEN
            v_id_pers := SEQ_PER_PERSONA.NEXTVAL;

            INSERT INTO PER_PERSONA (
                ID_PERSONA, TIPO_PERS, NUM_IDENTIFICACION_PERS, FECHA_REGISTRO_PERS, ESTADO_PERS
            ) VALUES (
                v_id_pers, 'N', r_padron.CEDULA_PADR, SYSDATE, 'A'
            );

            INSERT INTO PER_PERSONA_FISICA (
                ID_PERSONA_FISICA, TIPO_PERS, NOMBRE_PEFI, APELLIDO1_PEFI, APELLIDO2_PEFI,
                SEXO_PEFI, FECHA_NACIMIENTO_PEFI, ID_PAIS_NACIONALIDAD, ID_PAIS_RESIDENCIA, ES_ASEGURADO_PEFI
            ) VALUES (
                v_id_pers, 'N', INITCAP(r_padron.NOMBRE_PADR), INITCAP(r_padron.APELLIDO1_PADR),
                INITCAP(r_padron.APELLIDO2_PADR), r_padron.SEXO_PADR,
                ADD_MONTHS(TRUNC(SYSDATE), -300), v_id_pais, v_id_pais, 'S'
            );
        ELSE
            SELECT ID_PERSONA INTO v_id_pers
              FROM PER_PERSONA
             WHERE TIPO_PERS = 'N'
               AND NUM_IDENTIFICACION_PERS = r_padron.CEDULA_PADR;

            UPDATE PER_PERSONA_FISICA
               SET NOMBRE_PEFI      = INITCAP(r_padron.NOMBRE_PADR),
                   APELLIDO1_PEFI   = INITCAP(r_padron.APELLIDO1_PADR),
                   APELLIDO2_PEFI   = INITCAP(r_padron.APELLIDO2_PADR),
                   SEXO_PEFI        = r_padron.SEXO_PADR,
                   USUARIO_MOD_PEFI = USER,
                   FECHA_MOD_PEFI   = SYSTIMESTAMP
             WHERE ID_PERSONA_FISICA = v_id_pers;
        END IF;

        -- Verificar si ya es cliente en PER_CLIENTE
        SELECT COUNT(*) INTO v_existe
          FROM PER_CLIENTE
         WHERE ID_PERSONA = v_id_pers;

        IF v_existe = 0 THEN
            p_id_cliente_out := SEQ_PER_CLIENTE.NEXTVAL;

            INSERT INTO PER_CLIENTE (
                ID_CLIENTE, ID_PERSONA, ID_PADRON, CODIGO_CLI, FECHA_INGRESO_CLI,
                ES_PREFERENCIAL_CLI, MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI,
                SALDO_ACTUAL_CLI, ES_DEFECTO_CLI, ESTADO_CLI
            ) VALUES (
                p_id_cliente_out, v_id_pers, r_padron.ID_PADRON, p_codigo_cli, SYSDATE,
                p_es_preferencial, p_monto_max_credito, p_dias_credito,
                0, 'N', 'A'
            );
        ELSE
            SELECT ID_CLIENTE INTO p_id_cliente_out
              FROM PER_CLIENTE
             WHERE ID_PERSONA = v_id_pers;

            UPDATE PER_CLIENTE
               SET ID_PADRON             = r_padron.ID_PADRON,
                   ES_PREFERENCIAL_CLI   = p_es_preferencial,
                   MONTO_MAX_CREDITO_CLI = p_monto_max_credito,
                   DIAS_CREDITO_CLI      = p_dias_credito,
                   USUARIO_MOD_CLI       = USER,
                   FECHA_MOD_CLI         = SYSTIMESTAMP
             WHERE ID_CLIENTE = p_id_cliente_out;
        END IF;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[OK] Cliente ' || p_codigo_cli || ' (' || r_padron.NOMBRE_PADR || ' ' ||
                             r_padron.APELLIDO1_PADR || ') enlazado con el Padron Nacional (ID_CLIENTE=' || p_id_cliente_out || ').');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            ROLLBACK TO sp_cliente_padron;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_CREAR_CLIENTE_DESDE_PADRON', -20031,
                'La cedula ' || p_cedula || ' no se encontro en CAT_PADRON.');
            RAISE_APPLICATION_ERROR(-20031, 'La cedula ' || p_cedula || ' no existe en el Padron Nacional (CAT_PADRON).');
        WHEN OTHERS THEN
            ROLLBACK TO sp_cliente_padron;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PER_PADRON', 'PR_CREAR_CLIENTE_DESDE_PADRON', SQLCODE, SQLERRM);
            RAISE;
    END PR_CREAR_CLIENTE_DESDE_PADRON;

END PKG_PER_PADRON;
/
SHOW ERRORS PACKAGE BODY PKG_PER_PADRON;


--------------------------------------------------------------------------------
-- 2. PAQUETE: PKG_INV_GESTION
--    Control transaccional de inventario con concurrencia (SELECT FOR UPDATE WAIT)
--    y procedimiento semanal para mercadeo (por vencer a 1 semana y >6 meses).
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_INV_GESTION IS

    -- Modifica la existencia de un producto/lote en una bodega usando bloqueo FOR UPDATE WAIT 5
    PROCEDURE PR_AFECTAR_EXISTENCIA (
        p_id_bodega       IN NUMBER,
        p_id_producto     IN NUMBER,
        p_id_lote         IN NUMBER,
        p_cantidad        IN NUMBER,
        p_es_entrada      IN VARCHAR2,
        p_tipo_movi       IN VARCHAR2 DEFAULT NULL,
        p_id_usuario      IN NUMBER   DEFAULT 1,
        p_documento_ref   IN VARCHAR2 DEFAULT NULL,
        p_registrar_kard  IN VARCHAR2 DEFAULT 'S'
    );

    -- Procedimiento semanal para Mercadeo: indica por separado productos por vencer (1 semana)
    -- y productos con mas de 6 meses en bodega, notificando al coordinador.
    PROCEDURE PR_REPORTE_SEMANAL_MERCADEO;

END PKG_INV_GESTION;
/
SHOW ERRORS PACKAGE PKG_INV_GESTION;

CREATE OR REPLACE PACKAGE BODY PKG_INV_GESTION IS

    PROCEDURE PR_AFECTAR_EXISTENCIA (
        p_id_bodega       IN NUMBER,
        p_id_producto     IN NUMBER,
        p_id_lote         IN NUMBER,
        p_cantidad        IN NUMBER,
        p_es_entrada      IN VARCHAR2,
        p_tipo_movi       IN VARCHAR2 DEFAULT NULL,
        p_id_usuario      IN NUMBER   DEFAULT 1,
        p_documento_ref   IN VARCHAR2 DEFAULT NULL,
        p_registrar_kard  IN VARCHAR2 DEFAULT 'S'
    ) IS
        v_id_existencia   NUMBER(12);
        v_cant_actual     NUMBER(14,3);
        v_costo_prod      NUMBER(14,4);
        v_id_mov          NUMBER(12);
        v_lote_efectivo   NUMBER(12);
        e_recurso_ocupado EXCEPTION;
        PRAGMA EXCEPTION_INIT(e_recurso_ocupado, -30006); -- ORA-30006: resource busy; acquire with WAIT timeout expired
    BEGIN
        IF p_cantidad <= 0 THEN
            RAISE_APPLICATION_ERROR(-20014, 'La cantidad a afectar en inventario debe ser mayor a cero.');
        END IF;

        SELECT PRECIO_COSTO_PROD INTO v_costo_prod
          FROM PRO_PRODUCTO
         WHERE ID_PRODUCTO = p_id_producto;

        -- Resolucion inteligente de lote (FIFO por fecha de caducidad si p_id_lote es nulo)
        v_lote_efectivo := p_id_lote;
        IF v_lote_efectivo IS NULL THEN
            BEGIN
                SELECT ID_LOTE INTO v_lote_efectivo
                  FROM (
                      SELECT e.ID_LOTE
                        FROM INV_EXISTENCIA e
                             LEFT JOIN PRO_LOTE l ON l.ID_LOTE = e.ID_LOTE AND l.ID_PRODUCTO = e.ID_PRODUCTO
                       WHERE e.ID_BODEGA   = p_id_bodega
                         AND e.ID_PRODUCTO = p_id_producto
                         AND (UPPER(p_es_entrada) = 'S' OR e.CANTIDAD_EXIS >= p_cantidad)
                       ORDER BY NVL(l.FECHA_VENCIM_LOTE, DATE '2099-12-31') ASC, e.ID_EXISTENCIA ASC
                  )
                 WHERE ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    -- Si no hay lote con suficiente stock, tomar cualquiera existente de la bodega/producto
                    BEGIN
                        SELECT ID_LOTE INTO v_lote_efectivo
                          FROM (SELECT ID_LOTE FROM INV_EXISTENCIA 
                                 WHERE ID_BODEGA = p_id_bodega AND ID_PRODUCTO = p_id_producto 
                                 ORDER BY CANTIDAD_EXIS DESC)
                         WHERE ROWNUM = 1;
                    EXCEPTION
                        WHEN NO_DATA_FOUND THEN v_lote_efectivo := NULL;
                    END;
            END;
        END IF;

        -- Intentar bloquear la fila de existencia con FOR UPDATE WAIT 5 (Requerimiento #11 Concurrencia)
        BEGIN
            SELECT ID_EXISTENCIA, CANTIDAD_EXIS
              INTO v_id_existencia, v_cant_actual
              FROM INV_EXISTENCIA
             WHERE ID_BODEGA   = p_id_bodega
               AND ID_PRODUCTO = p_id_producto
               AND NVL(ID_LOTE, -1) = NVL(v_lote_efectivo, -1)
               FOR UPDATE WAIT 5;

            IF UPPER(p_es_entrada) = 'S' THEN
                UPDATE INV_EXISTENCIA
                   SET CANTIDAD_EXIS    = CANTIDAD_EXIS + p_cantidad,
                       USUARIO_MOD_EXIS = USER,
                       FECHA_MOD_EXIS   = SYSTIMESTAMP
                 WHERE ID_EXISTENCIA = v_id_existencia;
            ELSE
                IF v_cant_actual < p_cantidad THEN
                    RAISE_APPLICATION_ERROR(-20015,
                        'Existencia insuficiente en la bodega ' || p_id_bodega ||
                        ' para el producto ' || p_id_producto ||
                        ' (Disponible: ' || v_cant_actual || ', Solicitado: ' || p_cantidad || ').');
                END IF;

                UPDATE INV_EXISTENCIA
                   SET CANTIDAD_EXIS    = CANTIDAD_EXIS - p_cantidad,
                       USUARIO_MOD_EXIS = USER,
                       FECHA_MOD_EXIS   = SYSTIMESTAMP
                 WHERE ID_EXISTENCIA = v_id_existencia;
            END IF;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                IF UPPER(p_es_entrada) = 'S' THEN
                    INSERT INTO INV_EXISTENCIA (
                        ID_EXISTENCIA, ID_BODEGA, ID_PRODUCTO, ID_LOTE,
                        CANTIDAD_EXIS, CANTIDAD_RESERV_EXIS
                    ) VALUES (
                        SEQ_INV_EXISTENCIA.NEXTVAL, p_id_bodega, p_id_producto, v_lote_efectivo,
                        p_cantidad, 0
                    );
                ELSE
                    RAISE_APPLICATION_ERROR(-20015,
                        'No existe inventario registrado en la bodega ' || p_id_bodega ||
                        ' para el producto ' || p_id_producto || '.');
                END IF;
        END;

        -- Registrar movimiento en Kardex si se solicita
        IF UPPER(p_registrar_kard) = 'S' AND p_tipo_movi IS NOT NULL THEN
            v_id_mov := SEQ_INV_MOVIMIENTO.NEXTVAL;

            INSERT INTO INV_MOVIMIENTO (
                ID_MOVIMIENTO, ID_BODEGA, ID_USUARIO, TIPO_MOVI,
                CONSECUTIVO_MOVI, FECHA_MOVI, DOCUMENTO_REF_MOVI,
                OBSERVACION_MOVI, ESTADO_MOVI
            ) VALUES (
                v_id_mov, p_id_bodega, NVL(p_id_usuario, 1), p_tipo_movi,
                'MOV-' || LPAD(v_id_mov, 6, '0'), SYSDATE, p_documento_ref,
                'Movimiento automatico por ' || p_tipo_movi, 'A'
            );

            INSERT INTO INV_MOVIMIENTO_DET (
                ID_MOVIMIENTO_DET, ID_MOVIMIENTO, ID_PRODUCTO, ID_LOTE,
                LINEA_MODE, CANTIDAD_MODE, COSTO_UNITARIO_MODE
            ) VALUES (
                SEQ_INV_MOVIMIENTO_DET.NEXTVAL, v_id_mov, p_id_producto, v_lote_efectivo,
                1, p_cantidad, v_costo_prod
            );
        END IF;
    EXCEPTION
        WHEN e_recurso_ocupado THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_INV_GESTION', 'PR_AFECTAR_EXISTENCIA', -30006,
                'Fila de inventario bloqueada por otra sesion (WAIT 5 agotado).');
            RAISE_APPLICATION_ERROR(-20016, 'El registro de inventario esta siendo modificado por otro cajero. Intente nuevamente.');
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_INV_GESTION', 'PR_AFECTAR_EXISTENCIA', SQLCODE, SQLERRM);
            RAISE;
    END PR_AFECTAR_EXISTENCIA;

    PROCEDURE PR_REPORTE_SEMANAL_MERCADEO IS
        v_dias_vencer   NUMBER;
        v_meses_bodega  NUMBER;
        v_correo_coord  VARCHAR2(200);
        v_cuerpo        CLOB;
        v_cant_vencer   PLS_INTEGER := 0;
        v_cant_antiguos PLS_INTEGER := 0;

        -- Cursor 1: Productos proximos a vencer (en los proximos N dias = 1 semana)
        CURSOR c_por_vencer (p_dias NUMBER) IS
            SELECT b.NOMBRE_BODE,
                   p.CODIGO_PROD,
                   p.NOMBRE_PROD,
                   l.NUMERO_LOTE,
                   l.FECHA_VENCIM_LOTE,
                   TRUNC(l.FECHA_VENCIM_LOTE) - TRUNC(SYSDATE) AS DIAS_RESTANTES,
                   e.CANTIDAD_EXIS
              FROM INV_EXISTENCIA e
                   JOIN PRO_LOTE l     ON l.ID_LOTE     = e.ID_LOTE
                                      AND l.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN PRO_PRODUCTO p ON p.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN INV_BODEGA b   ON b.ID_BODEGA   = e.ID_BODEGA
             WHERE e.CANTIDAD_EXIS > 0
               AND l.FECHA_VENCIM_LOTE BETWEEN TRUNC(SYSDATE) AND TRUNC(SYSDATE) + p_dias
             ORDER BY l.FECHA_VENCIM_LOTE ASC;

        -- Cursor 2: Productos con mas de M meses (6 meses) de estar en bodega
        CURSOR c_antiguos (p_meses NUMBER) IS
            SELECT b.NOMBRE_BODE,
                   p.CODIGO_PROD,
                   p.NOMBRE_PROD,
                   l.NUMERO_LOTE,
                   l.FECHA_INGRESO_LOTE,
                   ROUND(MONTHS_BETWEEN(TRUNC(SYSDATE), TRUNC(l.FECHA_INGRESO_LOTE)), 1) AS MESES_EN_BODEGA,
                   e.CANTIDAD_EXIS
              FROM INV_EXISTENCIA e
                   JOIN PRO_LOTE l     ON l.ID_LOTE     = e.ID_LOTE
                                      AND l.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN PRO_PRODUCTO p ON p.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN INV_BODEGA b   ON b.ID_BODEGA   = e.ID_BODEGA
             WHERE e.CANTIDAD_EXIS > 0
               AND l.FECHA_INGRESO_LOTE <= ADD_MONTHS(TRUNC(SYSDATE), -p_meses)
             ORDER BY l.FECHA_INGRESO_LOTE ASC;
    BEGIN
        v_dias_vencer  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('DIAS_ALERTA_POR_VENCER');
        v_meses_bodega := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MESES_ANTIGUEDAD_BODEGA');
        v_correo_coord := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR');

        -- SECCION 1: PRODUCTOS POR VENCERSE (A UNA SEMANA)
        v_cuerpo := 'REPORTE SEMANAL PARA MERCADEO - SUPER BRUNCA' || CHR(10) ||
                    RPAD('=', 84, '=') || CHR(10) ||
                    'SECCION 1: PRODUCTOS PROXIMOS A VENCER (EN LOS PROXIMOS ' || v_dias_vencer || ' DIAS)' || CHR(10) ||
                    RPAD('-', 84, '-') || CHR(10) ||
                    RPAD('BODEGA', 22) || RPAD('PRODUCTO', 24) || RPAD('LOTE', 12) ||
                    RPAD('VENCE', 12) || LPAD('DIAS', 6) || LPAD('STOCK', 8) || CHR(10) ||
                    RPAD('-', 84, '-') || CHR(10);

        FOR r1 IN c_por_vencer(v_dias_vencer) LOOP
            v_cant_vencer := v_cant_vencer + 1;
            v_cuerpo := v_cuerpo ||
                        RPAD(SUBSTR(r1.NOMBRE_BODE, 1, 20), 22) ||
                        RPAD(SUBSTR(r1.NOMBRE_PROD, 1, 22), 24) ||
                        RPAD(r1.NUMERO_LOTE, 12) ||
                        RPAD(TO_CHAR(r1.FECHA_VENCIM_LOTE, 'YYYY-MM-DD'), 12) ||
                        LPAD(r1.DIAS_RESTANTES, 6) ||
                        LPAD(r1.CANTIDAD_EXIS, 8) || CHR(10);
        END LOOP;

        IF v_cant_vencer = 0 THEN
            v_cuerpo := v_cuerpo || '  (No hay lotes proximos a vencer en los siguientes ' || v_dias_vencer || ' dias)' || CHR(10);
        END IF;
        v_cuerpo := v_cuerpo || 'Total lotes por vencer: ' || v_cant_vencer || CHR(10) || CHR(10);

        -- SECCION 2: PRODUCTOS CON MAS DE 6 MESES EN BODEGA
        v_cuerpo := v_cuerpo ||
                    RPAD('=', 84, '=') || CHR(10) ||
                    'SECCION 2: PRODUCTOS CON MAS DE ' || v_meses_bodega || ' MESES DE ESTAR EN BODEGA' || CHR(10) ||
                    RPAD('-', 84, '-') || CHR(10) ||
                    RPAD('BODEGA', 22) || RPAD('PRODUCTO', 24) || RPAD('LOTE', 12) ||
                    RPAD('INGRESO', 12) || LPAD('MESES', 6) || LPAD('STOCK', 8) || CHR(10) ||
                    RPAD('-', 84, '-') || CHR(10);

        FOR r2 IN c_antiguos(v_meses_bodega) LOOP
            v_cant_antiguos := v_cant_antiguos + 1;
            v_cuerpo := v_cuerpo ||
                        RPAD(SUBSTR(r2.NOMBRE_BODE, 1, 20), 22) ||
                        RPAD(SUBSTR(r2.NOMBRE_PROD, 1, 22), 24) ||
                        RPAD(r2.NUMERO_LOTE, 12) ||
                        RPAD(TO_CHAR(r2.FECHA_INGRESO_LOTE, 'YYYY-MM-DD'), 12) ||
                        LPAD(r2.MESES_EN_BODEGA, 6) ||
                        LPAD(r2.CANTIDAD_EXIS, 8) || CHR(10);
        END LOOP;

        IF v_cant_antiguos = 0 THEN
            v_cuerpo := v_cuerpo || '  (No hay lotes con mas de ' || v_meses_bodega || ' meses en bodega)' || CHR(10);
        END IF;
        v_cuerpo := v_cuerpo || 'Total lotes con antiguedad > ' || v_meses_bodega || ' meses: ' || v_cant_antiguos;

        PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
            p_destinatarios => v_correo_coord,
            p_asunto        => 'Reporte Semanal Mercadeo: Por vencer (' || v_cant_vencer || ') y Antiguedad >' || v_meses_bodega || 'm (' || v_cant_antiguos || ')',
            p_cuerpo        => v_cuerpo
        );
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_INV_GESTION', 'PR_REPORTE_SEMANAL_MERCADEO', SQLCODE, SQLERRM);
            RAISE;
    END PR_REPORTE_SEMANAL_MERCADEO;

END PKG_INV_GESTION;
/
SHOW ERRORS PACKAGE BODY PKG_INV_GESTION;


--------------------------------------------------------------------------------
-- 3. PAQUETE: PKG_PRM_MERCADEO
--    Calculo automatico de acciones por patrocinadores, verificacion semanal
--    de descuentos planeados y premiacion semestral de los 10 mejores clientes.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_PRM_MERCADEO IS

    -- Calcula y muestra cuantas acciones se le deben otorgar a una factura segun los patrocinadores
    FUNCTION FN_CALCULAR_ACCIONES_FACTURA (
        p_id_factura_venta IN NUMBER
    ) RETURN NUMBER;

    -- Registra automaticamente las acciones ganadas por una factura en PRM_ACCION_CLIENTE
    PROCEDURE PR_OTORGAR_ACCIONES_LINEA (
        p_id_factura_venta IN NUMBER,
        p_id_producto      IN NUMBER,
        p_cantidad         IN NUMBER
    );

    -- Proceso semanal: verifica los descuentos planeados (por vencer o antiguedad)
    -- e incluye automaticamente los productos al detalle (PRM_DESCUENTO_DET).
    PROCEDURE PR_VERIFICAR_DESCUENTOS_SEMANAL;

    -- Proceso semestral: obtiene los 10 clientes que mas compren, les otorga una orden
    -- de compra por 100 mil colones (parametrizado) y notifica al coordinador.
    PROCEDURE PR_PREMIAR_MEJORES_CLIENTES (
        p_periodo IN VARCHAR2 DEFAULT NULL
    );

    -- Ajusta dinamicamente la frecuencia de premiacion en SEG_PARAMETRO y reconfigura
    -- en caliente el repeat_interval del job DBMS_SCHEDULER mediante SET_ATTRIBUTE
    PROCEDURE PR_CONFIGURAR_FRECUENCIA_PREMIACION (
        p_meses IN NUMBER
    );

END PKG_PRM_MERCADEO;
/
SHOW ERRORS PACKAGE PKG_PRM_MERCADEO;

CREATE OR REPLACE PACKAGE BODY PKG_PRM_MERCADEO IS

    FUNCTION FN_CALCULAR_ACCIONES_FACTURA (
        p_id_factura_venta IN NUMBER
    ) RETURN NUMBER IS
        v_total_acciones NUMBER := 0;

        CURSOR c_acciones IS
            SELECT pr.ID_PROMOCION,
                   pr.CODIGO_PROM,
                   pr.NOMBRE_PROM,
                   p.NOMBRE_PROD,
                   d.CANTIDAD_FVDE,
                   pa.CANT_REQUERIDA_PATR,
                   pa.ACCIONES_OTORGA_PATR,
                   TRUNC(d.CANTIDAD_FVDE / pa.CANT_REQUERIDA_PATR) * pa.ACCIONES_OTORGA_PATR AS ACCIONES_GANADAS
              FROM VEN_FACTURA f
                   JOIN VEN_FACTURA_DET d   ON d.ID_FACTURA_VENTA = f.ID_FACTURA_VENTA
                   JOIN PRO_PRODUCTO p      ON p.ID_PRODUCTO      = d.ID_PRODUCTO
                   JOIN PRM_PATROCINADOR pa ON pa.ID_PRODUCTO     = d.ID_PRODUCTO
                   JOIN PRM_PROMOCION pr    ON pr.ID_PROMOCION    = pa.ID_PROMOCION
             WHERE f.ID_FACTURA_VENTA = p_id_factura_venta
               AND pr.ESTADO_PROM     = 'A'
               AND pa.ESTADO_PATR     = 'A'
               AND TRUNC(f.FECHA_FAVE) BETWEEN TRUNC(pr.FECHA_INICIO_PROM) AND TRUNC(pr.FECHA_FIN_PROM)
               AND (pr.ID_SUCURSAL IS NULL OR pr.ID_SUCURSAL = f.ID_SUCURSAL)
               AND d.CANTIDAD_FVDE >= pa.CANT_REQUERIDA_PATR;
    BEGIN
        FOR r IN c_acciones LOOP
            v_total_acciones := v_total_acciones + r.ACCIONES_GANADAS;
            DBMS_OUTPUT.PUT_LINE('[PROMOCION ' || r.CODIGO_PROM || '] Producto patrocinador: ' || r.NOMBRE_PROD ||
                                 ' (Comprado: ' || r.CANTIDAD_FVDE || ', Requerido: ' || r.CANT_REQUERIDA_PATR ||
                                 ') -> Acciones otorgadas: ' || r.ACCIONES_GANADAS);
        END LOOP;

        DBMS_OUTPUT.PUT_LINE('Total de acciones otorgadas a la factura #' || p_id_factura_venta || ': ' || v_total_acciones);
        RETURN v_total_acciones;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PRM_MERCADEO', 'FN_CALCULAR_ACCIONES_FACTURA', SQLCODE, SQLERRM);
            RETURN 0;
    END FN_CALCULAR_ACCIONES_FACTURA;

    PROCEDURE PR_OTORGAR_ACCIONES_LINEA (
        p_id_factura_venta IN NUMBER,
        p_id_producto      IN NUMBER,
        p_cantidad         IN NUMBER
    ) IS
        v_id_sucursal NUMBER(10);
        v_fecha_fave  DATE;
        v_acciones    NUMBER;

        CURSOR c_promos (p_suc NUMBER, p_fec DATE) IS
            SELECT pr.ID_PROMOCION,
                   pr.CODIGO_PROM,
                   pr.NOMBRE_PROM,
                   pa.CANT_REQUERIDA_PATR,
                   pa.ACCIONES_OTORGA_PATR
              FROM PRM_PATROCINADOR pa
                   JOIN PRM_PROMOCION pr ON pr.ID_PROMOCION = pa.ID_PROMOCION
             WHERE pa.ID_PRODUCTO = p_id_producto
               AND pa.ESTADO_PATR = 'A'
               AND pr.ESTADO_PROM = 'A'
               AND TRUNC(p_fec) BETWEEN TRUNC(pr.FECHA_INICIO_PROM) AND TRUNC(pr.FECHA_FIN_PROM)
               AND (pr.ID_SUCURSAL IS NULL OR pr.ID_SUCURSAL = p_suc);
    BEGIN
        IF p_id_producto IS NULL OR p_cantidad <= 0 THEN
            RETURN;
        END IF;

        SELECT ID_SUCURSAL, FECHA_FAVE
          INTO v_id_sucursal, v_fecha_fave
          FROM VEN_FACTURA
         WHERE ID_FACTURA_VENTA = p_id_factura_venta;

        FOR r IN c_promos(v_id_sucursal, v_fecha_fave) LOOP
            v_acciones := TRUNC(p_cantidad / r.CANT_REQUERIDA_PATR) * r.ACCIONES_OTORGA_PATR;

            IF v_acciones > 0 THEN
                MERGE INTO PRM_ACCION_CLIENTE dest
                USING (SELECT r.ID_PROMOCION AS ID_PROMOCION,
                              p_id_factura_venta AS ID_FACTURA_VENTA
                         FROM dual) src
                   ON (dest.ID_PROMOCION = src.ID_PROMOCION AND dest.ID_FACTURA_VENTA = src.ID_FACTURA_VENTA)
                WHEN MATCHED THEN
                    UPDATE SET dest.CANT_ACCIONES_ACLI = dest.CANT_ACCIONES_ACLI + v_acciones,
                               dest.USUARIO_MOD_ACLI   = USER,
                               dest.FECHA_MOD_ACLI     = SYSTIMESTAMP
                WHEN NOT MATCHED THEN
                    INSERT (
                        ID_ACCION_CLIENTE, ID_PROMOCION, ID_FACTURA_VENTA,
                        ID_PREMIO, CANT_ACCIONES_ACLI, FECHA_CANJE_ACLI
                    ) VALUES (
                        SEQ_PRM_ACCION_CLIENTE.NEXTVAL, r.ID_PROMOCION, p_id_factura_venta,
                        NULL, v_acciones, NULL
                    );

                DBMS_OUTPUT.PUT_LINE('[PROMOCION AUTOMATICA] Se otorgaron ' || v_acciones ||
                                     ' accion(es) en la promocion "' || r.NOMBRE_PROM ||
                                     '" a la factura #' || p_id_factura_venta || '.');
            END IF;
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PRM_MERCADEO', 'PR_OTORGAR_ACCIONES_LINEA', SQLCODE, SQLERRM);
            RAISE;
    END PR_OTORGAR_ACCIONES_LINEA;

    PROCEDURE PR_VERIFICAR_DESCUENTOS_SEMANAL IS
        v_incluidos PLS_INTEGER := 0;

        CURSOR c_reglas IS
            SELECT r.ID_DESCUENTO_REGLA,
                   d.ID_DESCUENTO,
                   d.CODIGO_DSCT,
                   d.NOMBRE_DSCT,
                   r.TIPO_REGLA_DSRE,
                   r.DIAS_VENCIM_DSRE,
                   r.DIAS_INGRESO_DSRE
              FROM PRM_DESCUENTO d
                   JOIN PRM_DESCUENTO_REGLA r ON r.ID_DESCUENTO = d.ID_DESCUENTO
             WHERE d.ESTADO_DSCT = 'A'
               AND r.ESTADO_DSRE = 'A'
               AND TRUNC(SYSDATE) <= TRUNC(d.FECHA_FIN_DSCT)
               AND r.TIPO_REGLA_DSRE IN ('FECHA_VENCIMIENTO', 'FECHA_INGRESO');

        CURSOR c_lotes_vencim (p_dias NUMBER) IS
            SELECT DISTINCT l.ID_PRODUCTO, l.ID_LOTE, l.NUMERO_LOTE, l.FECHA_VENCIM_LOTE
              FROM PRO_LOTE l
                   JOIN INV_EXISTENCIA e ON e.ID_LOTE = l.ID_LOTE AND e.ID_PRODUCTO = l.ID_PRODUCTO
             WHERE l.ESTADO_LOTE = 'A'
               AND e.CANTIDAD_EXIS > 0
               AND l.FECHA_VENCIM_LOTE IS NOT NULL
               AND TRUNC(l.FECHA_VENCIM_LOTE) - TRUNC(SYSDATE) <= p_dias;

        CURSOR c_lotes_ingreso (p_dias NUMBER) IS
            SELECT DISTINCT l.ID_PRODUCTO, l.ID_LOTE, l.NUMERO_LOTE, l.FECHA_INGRESO_LOTE
              FROM PRO_LOTE l
                   JOIN INV_EXISTENCIA e ON e.ID_LOTE = l.ID_LOTE AND e.ID_PRODUCTO = l.ID_PRODUCTO
             WHERE l.ESTADO_LOTE = 'A'
               AND e.CANTIDAD_EXIS > 0
               AND TRUNC(SYSDATE) - TRUNC(l.FECHA_INGRESO_LOTE) >= p_dias;
    BEGIN
        SAVEPOINT sp_descuentos_sem;

        FOR reg IN c_reglas LOOP
            IF reg.TIPO_REGLA_DSRE = 'FECHA_VENCIMIENTO' THEN
                FOR lv IN c_lotes_vencim(reg.DIAS_VENCIM_DSRE) LOOP
                    MERGE INTO PRM_DESCUENTO_DET dest
                    USING (SELECT reg.ID_DESCUENTO AS ID_DESCUENTO,
                                  lv.ID_PRODUCTO   AS ID_PRODUCTO,
                                  lv.ID_LOTE       AS ID_LOTE
                             FROM dual) src
                       ON (dest.ID_DESCUENTO = src.ID_DESCUENTO
                           AND dest.ID_PRODUCTO = src.ID_PRODUCTO
                           AND NVL(dest.ID_LOTE, -1) = NVL(src.ID_LOTE, -1))
                    WHEN NOT MATCHED THEN
                        INSERT (
                            ID_DESCUENTO_DET, ID_DESCUENTO, ID_PRODUCTO, ID_LOTE,
                            MOTIVO_INCLUSION_DSDE, FECHA_INCLUSION_DSDE, ESTADO_DSDE
                        ) VALUES (
                            SEQ_PRM_DESCUENTO_DET.NEXTVAL, reg.ID_DESCUENTO, lv.ID_PRODUCTO, lv.ID_LOTE,
                            'Incluido automaticamente por vencer (<= ' || reg.DIAS_VENCIM_DSRE || ' dias) - Lote ' || lv.NUMERO_LOTE,
                            SYSDATE, 'A'
                        );
                    IF SQL%ROWCOUNT > 0 THEN
                        v_incluidos := v_incluidos + 1;
                    END IF;
                END LOOP;

            ELSIF reg.TIPO_REGLA_DSRE = 'FECHA_INGRESO' THEN
                FOR li IN c_lotes_ingreso(reg.DIAS_INGRESO_DSRE) LOOP
                    MERGE INTO PRM_DESCUENTO_DET dest
                    USING (SELECT reg.ID_DESCUENTO AS ID_DESCUENTO,
                                  li.ID_PRODUCTO   AS ID_PRODUCTO,
                                  li.ID_LOTE       AS ID_LOTE
                             FROM dual) src
                       ON (dest.ID_DESCUENTO = src.ID_DESCUENTO
                           AND dest.ID_PRODUCTO = src.ID_PRODUCTO
                           AND NVL(dest.ID_LOTE, -1) = NVL(src.ID_LOTE, -1))
                    WHEN NOT MATCHED THEN
                        INSERT (
                            ID_DESCUENTO_DET, ID_DESCUENTO, ID_PRODUCTO, ID_LOTE,
                            MOTIVO_INCLUSION_DSDE, FECHA_INCLUSION_DSDE, ESTADO_DSDE
                        ) VALUES (
                            SEQ_PRM_DESCUENTO_DET.NEXTVAL, reg.ID_DESCUENTO, li.ID_PRODUCTO, li.ID_LOTE,
                            'Incluido automaticamente por antiguedad (>= ' || reg.DIAS_INGRESO_DSRE || ' dias) - Lote ' || li.NUMERO_LOTE,
                            SYSDATE, 'A'
                        );
                    IF SQL%ROWCOUNT > 0 THEN
                        v_incluidos := v_incluidos + 1;
                    END IF;
                END LOOP;
            END IF;
        END LOOP;

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[OK] Verificacion semanal de descuentos planeados completada. Nuevos lotes incluidos al detalle: ' || v_incluidos);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_descuentos_sem;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PRM_MERCADEO', 'PR_VERIFICAR_DESCUENTOS_SEMANAL', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_DESCUENTOS_SEMANAL;

    PROCEDURE PR_PREMIAR_MEJORES_CLIENTES (
        p_periodo IN VARCHAR2 DEFAULT NULL
    ) IS
        v_top_n         NUMBER;
        v_monto_orden   NUMBER(14,2);
        v_meses_frec    NUMBER;
        v_correo_coord  VARCHAR2(200);
        v_periodo       VARCHAR2(20);
        v_anio          NUMBER(4);
        v_sem           NUMBER(1);
        v_fecha_ini     DATE;
        v_fecha_fin     DATE;
        v_cuerpo        CLOB;
        v_posicion      PLS_INTEGER := 0;

        CURSOR c_top_clientes (p_fec_ini DATE, p_fec_fin DATE, p_limite NUMBER) IS
            SELECT *
              FROM (
                  SELECT c.ID_CLIENTE,
                         c.CODIGO_CLI,
                         NVL(pj.RAZON_SOCIAL_PEJU,
                             pf.NOMBRE_PEFI || ' ' || pf.APELLIDO1_PEFI) AS NOMBRE_CLIENTE,
                         SUM(NVL(f.SUBTOTAL_FAVE, 0) - NVL(f.DESCUENTO_FAVE, 0) + NVL(f.IMPUESTO_FAVE, 0)) AS TOTAL_COMPRADO,
                         COUNT(f.ID_FACTURA_VENTA)                       AS CANT_FACTURAS
                    FROM VEN_FACTURA f
                         JOIN PER_CLIENTE c ON c.ID_CLIENTE = f.ID_CLIENTE
                         LEFT JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = c.ID_PERSONA
                         LEFT JOIN PER_PERSONA_FISICA pf   ON pf.ID_PERSONA_FISICA   = c.ID_PERSONA
                   WHERE f.ESTADO_FAVE <> 'N'
                     AND NVL(c.ES_DEFECTO_CLI, 'N') = 'N' -- Excluir cliente de mostrador generico CLI-000000
                     AND f.FECHA_FAVE BETWEEN p_fec_ini AND p_fec_fin
                   GROUP BY c.ID_CLIENTE, c.CODIGO_CLI, pj.RAZON_SOCIAL_PEJU,
                            pf.NOMBRE_PEFI, pf.APELLIDO1_PEFI
                   ORDER BY TOTAL_COMPRADO DESC
              )
             WHERE ROWNUM <= p_limite;
    BEGIN
        SAVEPOINT sp_premiar_clientes;

        v_top_n        := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('TOP_CLIENTES_PREMIADOS');
        v_monto_orden  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MONTO_ORDEN_PREMIACION');
        v_meses_frec   := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MESES_FRECUENCIA_PREMIACION');
        v_correo_coord := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR');

        -- Determinar semestre calendario estricto (no ventana rodante)
        IF p_periodo IS NOT NULL AND INSTR(p_periodo, '-S') > 0 THEN
            v_periodo := p_periodo;
            v_anio    := TO_NUMBER(SUBSTR(v_periodo, 1, 4));
            v_sem     := TO_NUMBER(SUBSTR(v_periodo, INSTR(v_periodo, '-S') + 2, 1));
        ELSE
            v_anio := TO_NUMBER(TO_CHAR(SYSDATE, 'YYYY'));
            v_sem  := CASE WHEN TO_NUMBER(TO_CHAR(SYSDATE, 'MM')) <= 6 THEN 1 ELSE 2 END;
            v_periodo := v_anio || '-S' || v_sem;
        END IF;

        IF v_sem = 1 THEN
            v_fecha_ini := TO_DATE(v_anio || '-01-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS');
            v_fecha_fin := TO_DATE(v_anio || '-06-30 23:59:59', 'YYYY-MM-DD HH24:MI:SS');
        ELSE
            v_fecha_ini := TO_DATE(v_anio || '-07-01 00:00:00', 'YYYY-MM-DD HH24:MI:SS');
            v_fecha_fin := TO_DATE(v_anio || '-12-31 23:59:59', 'YYYY-MM-DD HH24:MI:SS');
        END IF;

        v_cuerpo := 'SELECCION AUTOMATICA DE LOS ' || v_top_n || ' MEJORES CLIENTES (PERIODO ' || v_periodo || ')' || CHR(10) ||
                    'Rango evaluado: ' || TO_CHAR(v_fecha_ini, 'YYYY-MM-DD') || ' al ' || TO_CHAR(v_fecha_fin, 'YYYY-MM-DD') || CHR(10) ||
                    'Orden de compra otorgada a cada cliente: CRC ' || TO_CHAR(v_monto_orden, 'FM999G999G990D00') || CHR(10) ||
                    RPAD('=', 80, '=') || CHR(10) ||
                    RPAD('POS', 5) || RPAD('CODIGO', 12) || RPAD('CLIENTE', 32) ||
                    LPAD('COMPRAS PERIODO', 16) || LPAD('ORDEN PREMIO', 15) || CHR(10) ||
                    RPAD('-', 80, '-') || CHR(10);

        FOR r IN c_top_clientes(v_fecha_ini, v_fecha_fin, v_top_n) LOOP
            v_posicion := v_posicion + 1;

            MERGE INTO PRM_ORDEN_PREMIACION dest
            USING (SELECT r.ID_CLIENTE AS ID_CLIENTE, v_periodo AS PERIODO_ORPR FROM dual) src
               ON (dest.ID_CLIENTE = src.ID_CLIENTE AND dest.PERIODO_ORPR = src.PERIODO_ORPR)
            WHEN MATCHED THEN
                UPDATE SET dest.POSICION_RANK_ORPR  = v_posicion,
                           dest.TOTAL_COMPRADO_ORPR = r.TOTAL_COMPRADO,
                           dest.MONTO_ORDEN_ORPR    = v_monto_orden,
                           dest.USUARIO_MOD_ORPR    = USER,
                           dest.FECHA_MOD_ORPR      = SYSTIMESTAMP
            WHEN NOT MATCHED THEN
                INSERT (
                    ID_ORDEN_PREMIACION, ID_CLIENTE, PERIODO_ORPR,
                    POSICION_RANK_ORPR, TOTAL_COMPRADO_ORPR, MONTO_ORDEN_ORPR,
                    FECHA_EMISION_ORPR, FECHA_VENCIM_ORPR, ESTADO_ORPR
                ) VALUES (
                    SEQ_PRM_ORDEN_PREMIACION.NEXTVAL, r.ID_CLIENTE, v_periodo,
                    v_posicion, r.TOTAL_COMPRADO, v_monto_orden,
                    SYSDATE, ADD_MONTHS(SYSDATE, v_meses_frec), 'D'
                );

            v_cuerpo := v_cuerpo ||
                        RPAD('#' || v_posicion, 5) ||
                        RPAD(r.CODIGO_CLI, 12) ||
                        RPAD(SUBSTR(r.NOMBRE_CLIENTE, 1, 30), 32) ||
                        LPAD(TO_CHAR(r.TOTAL_COMPRADO, 'FM999G999G990D00'), 16) ||
                        LPAD(TO_CHAR(v_monto_orden, 'FM999G999G990D00'), 15) || CHR(10);
        END LOOP;

        COMMIT;

        IF v_posicion > 0 THEN
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_coord,
                p_asunto        => 'Premiacion Semestral (' || v_periodo || '): Top ' || v_posicion || ' Clientes Seleccionados',
                p_cuerpo        => v_cuerpo
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_premiar_clientes;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PRM_MERCADEO', 'PR_PREMIAR_MEJORES_CLIENTES', SQLCODE, SQLERRM);
            RAISE;
    END PR_PREMIAR_MEJORES_CLIENTES;

    PROCEDURE PR_CONFIGURAR_FRECUENCIA_PREMIACION (
        p_meses IN NUMBER
    ) IS
    BEGIN
        IF p_meses IS NULL OR p_meses <= 0 THEN
            RAISE_APPLICATION_ERROR(-20035, 'La frecuencia de premiacion en meses debe ser mayor a cero.');
        END IF;

        -- 1. Actualizar el parametro en SEG_PARAMETRO
        UPDATE SEG_PARAMETRO
           SET VALOR_NUM_PARA   = p_meses,
               USUARIO_MOD_PARA = USER,
               FECHA_MOD_PARA   = SYSTIMESTAMP
         WHERE CODIGO_PARA = 'MESES_FRECUENCIA_PREMIACION';
        COMMIT;

        -- 2. Modificar dinamicamente el atributo repeat_interval del job DBMS_SCHEDULER
        BEGIN
            DBMS_SCHEDULER.SET_ATTRIBUTE (
                name      => 'CADENA_NEG.JOB_PREMIACION_SEMESTRAL',
                attribute => 'repeat_interval',
                value     => 'FREQ=MONTHLY; INTERVAL=' || p_meses || '; BYMONTHDAY=-1; BYHOUR=23; BYMINUTE=30; BYSECOND=0'
            );
            DBMS_OUTPUT.PUT_LINE('[OK] repeat_interval del job JOB_PREMIACION_SEMESTRAL actualizado a cada ' || p_meses || ' meses.');
        EXCEPTION
            WHEN OTHERS THEN
                PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_PRM_MERCADEO', 'PR_CONFIGURAR_FRECUENCIA_PREMIACION', SQLCODE, SQLERRM);
        END;

        -- 3. Registrar auditoria del cambio de parametro
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'SEG_PARAMETRO',
            p_modulo      => 'PARAMETROS',
            p_operacion   => 'UPDATE',
            p_llave       => 'MESES_FRECUENCIA_PREMIACION',
            p_descripcion => 'Reconfiguracion dinamica de frecuencia de premiacion a cada ' || p_meses || ' meses con ajuste de DBMS_SCHEDULER'
        );
    END PR_CONFIGURAR_FRECUENCIA_PREMIACION;

END PKG_PRM_MERCADEO;
/
SHOW ERRORS PACKAGE BODY PKG_PRM_MERCADEO;


--------------------------------------------------------------------------------
-- 4. PAQUETE: PKG_COM_OPERACION
--    Operaciones transaccionales de compras a proveedores, abonos a cuentas
--    por pagar y devoluciones a proveedor con SAVEPOINT / COMMIT / ROLLBACK.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_COM_OPERACION IS

    -- Tipo para lineas de detalle en facturacion atomica
    TYPE T_LINEA_COMPRA IS RECORD (
        id_producto      NUMBER,
        id_lote          NUMBER,
        cantidad         NUMBER,
        costo_unitario   NUMBER,
        porc_descuento   NUMBER,
        porc_impuesto    NUMBER
    );
    TYPE T_LISTA_LINEAS_COMPRA IS TABLE OF T_LINEA_COMPRA;

    -- Registra el encabezado de una factura de compra a proveedor
    PROCEDURE PR_CREAR_FACTURA_COMPRA (
        p_id_proveedor       IN  NUMBER,
        p_id_bodega          IN  NUMBER,
        p_id_usuario         IN  NUMBER,
        p_num_factura        IN  VARCHAR2,
        p_es_credito         IN  VARCHAR2,
        p_subtotal           IN  NUMBER,
        p_descuento          IN  NUMBER,
        p_impuesto           IN  NUMBER,
        p_id_factura_out     OUT NUMBER,
        p_auto_commit        IN  VARCHAR2 DEFAULT 'S'
    );

    -- Agrega una linea de detalle a una factura de compra
    PROCEDURE PR_AGREGAR_DETALLE_COMPRA (
        p_id_factura_compra  IN NUMBER,
        p_id_producto        IN NUMBER,
        p_id_lote            IN NUMBER,
        p_linea              IN NUMBER,
        p_cantidad           IN NUMBER,
        p_costo_unitario     IN NUMBER,
        p_porc_descuento     IN NUMBER DEFAULT 0,
        p_porc_impuesto      IN NUMBER DEFAULT 13,
        p_auto_commit        IN VARCHAR2 DEFAULT 'S'
    );

    -- Procedimiento atomico integral: registra compra y lineas con SAVEPOINT unico
    PROCEDURE PR_FACTURAR_COMPRA_ATOMICA (
        p_id_proveedor       IN  NUMBER,
        p_id_bodega          IN  NUMBER,
        p_id_usuario         IN  NUMBER,
        p_num_factura        IN  VARCHAR2,
        p_es_credito         IN  VARCHAR2,
        p_lineas             IN  T_LISTA_LINEAS_COMPRA,
        p_id_factura_out     OUT NUMBER
    );

    -- Registra un abono a una factura de compra pendiente (Cuentas por Pagar)
    PROCEDURE PR_REGISTRAR_ABONO_PAGAR (
        p_id_factura_compra  IN NUMBER,
        p_id_usuario         IN NUMBER,
        p_num_comprobante    IN VARCHAR2,
        p_monto_abono        IN NUMBER,
        p_observacion        IN VARCHAR2 DEFAULT NULL
    );

END PKG_COM_OPERACION;
/
SHOW ERRORS PACKAGE PKG_COM_OPERACION;

CREATE OR REPLACE PACKAGE BODY PKG_COM_OPERACION IS

    PROCEDURE PR_CREAR_FACTURA_COMPRA (
        p_id_proveedor       IN  NUMBER,
        p_id_bodega          IN  NUMBER,
        p_id_usuario         IN  NUMBER,
        p_num_factura        IN  VARCHAR2,
        p_es_credito         IN  VARCHAR2,
        p_subtotal           IN  NUMBER,
        p_descuento          IN  NUMBER,
        p_impuesto           IN  NUMBER,
        p_id_factura_out     OUT NUMBER,
        p_auto_commit        IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_dias_cred   NUMBER(4);
        v_fecha_venc  DATE;
        v_estado      VARCHAR2(1);
    BEGIN
        SAVEPOINT sp_crear_compra;

        -- Bloqueo concurrente sobre el proveedor (SELECT FOR UPDATE WAIT 5)
        SELECT DIAS_CREDITO_PROVE
          INTO v_dias_cred
          FROM PER_PROVEEDOR
         WHERE ID_PROVEEDOR = p_id_proveedor
           FOR UPDATE WAIT 5;

        IF UPPER(p_es_credito) = 'S' THEN
            v_fecha_venc := TRUNC(SYSDATE) + GREATEST(NVL(v_dias_cred, 30), 1);
            v_estado     := 'P'; -- Pendiente de pago
        ELSE
            v_fecha_venc := NULL;
            v_estado     := 'C'; -- Cancelada de contado
        END IF;

        p_id_factura_out := SEQ_COM_FACTURA_COMPRA.NEXTVAL;

        INSERT INTO COM_FACTURA_COMPRA (
            ID_FACTURA_COMPRA, ID_PROVEEDOR, ID_BODEGA, ID_USUARIO,
            NUM_FACTURA_FACO, FECHA_FACO, ES_CREDITO_FACO, FECHA_VENCIM_FACO,
            SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO, ESTADO_FACO
        ) VALUES (
            p_id_factura_out, p_id_proveedor, p_id_bodega, p_id_usuario,
            p_num_factura, SYSDATE, UPPER(p_es_credito), v_fecha_venc,
            p_subtotal, p_descuento, p_impuesto, v_estado
        );

        IF UPPER(p_auto_commit) = 'S' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_crear_compra;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_COM_OPERACION', 'PR_CREAR_FACTURA_COMPRA', SQLCODE, SQLERRM);
            RAISE;
    END PR_CREAR_FACTURA_COMPRA;

    PROCEDURE PR_AGREGAR_DETALLE_COMPRA (
        p_id_factura_compra  IN NUMBER,
        p_id_producto        IN NUMBER,
        p_id_lote            IN NUMBER,
        p_linea              IN NUMBER,
        p_cantidad           IN NUMBER,
        p_costo_unitario     IN NUMBER,
        p_porc_descuento     IN NUMBER DEFAULT 0,
        p_porc_impuesto      IN NUMBER DEFAULT 13,
        p_auto_commit        IN VARCHAR2 DEFAULT 'S'
    ) IS
    BEGIN
        SAVEPOINT sp_det_compra;

        INSERT INTO COM_FACTURA_COMPRA_DET (
            ID_FACTURA_COMPRA_DET, ID_FACTURA_COMPRA, ID_PRODUCTO, ID_LOTE,
            LINEA_FCDE, CANTIDAD_FCDE, COSTO_UNITARIO_FCDE,
            PORC_DESCUENTO_FCDE, PORC_IMPUESTO_FCDE
        ) VALUES (
            SEQ_COM_FACTURA_COMPRA_DET.NEXTVAL, p_id_factura_compra, p_id_producto, p_id_lote,
            p_linea, p_cantidad, p_costo_unitario,
            p_porc_descuento, p_porc_impuesto
        );

        IF UPPER(p_auto_commit) = 'S' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_det_compra;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_COM_OPERACION', 'PR_AGREGAR_DETALLE_COMPRA', SQLCODE, SQLERRM);
            RAISE;
    END PR_AGREGAR_DETALLE_COMPRA;

    PROCEDURE PR_FACTURAR_COMPRA_ATOMICA (
        p_id_proveedor       IN  NUMBER,
        p_id_bodega          IN  NUMBER,
        p_id_usuario         IN  NUMBER,
        p_num_factura        IN  VARCHAR2,
        p_es_credito         IN  VARCHAR2,
        p_lineas             IN  T_LISTA_LINEAS_COMPRA,
        p_id_factura_out     OUT NUMBER
    ) IS
        v_subtotal  NUMBER(14,2) := 0;
        v_descuento NUMBER(14,2) := 0;
        v_impuesto  NUMBER(14,2) := 0;
        v_linea_num NUMBER := 0;
    BEGIN
        SAVEPOINT sp_compra_atomica;

        IF p_lineas IS NULL OR p_lineas.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20042, 'No se puede emitir una factura de compra sin lineas de detalle.');
        END IF;

        FOR i IN 1..p_lineas.COUNT LOOP
            DECLARE
                v_lin_sub NUMBER := ROUND(p_lineas(i).cantidad * p_lineas(i).costo_unitario, 2);
                v_lin_des NUMBER := ROUND(v_lin_sub * (NVL(p_lineas(i).porc_descuento, 0) / 100), 2);
                v_lin_imp NUMBER := ROUND((v_lin_sub - v_lin_des) * (NVL(p_lineas(i).porc_impuesto, 13) / 100), 2);
            BEGIN
                v_subtotal  := v_subtotal + v_lin_sub;
                v_descuento := v_descuento + v_lin_des;
                v_impuesto  := v_impuesto + v_lin_imp;
            END;
        END LOOP;

        PR_CREAR_FACTURA_COMPRA (
            p_id_proveedor   => p_id_proveedor,
            p_id_bodega      => p_id_bodega,
            p_id_usuario     => p_id_usuario,
            p_num_factura    => p_num_factura,
            p_es_credito     => p_es_credito,
            p_subtotal       => v_subtotal,
            p_descuento      => v_descuento,
            p_impuesto       => v_impuesto,
            p_id_factura_out => p_id_factura_out,
            p_auto_commit    => 'N'
        );

        FOR i IN 1..p_lineas.COUNT LOOP
            v_linea_num := v_linea_num + 1;
            PR_AGREGAR_DETALLE_COMPRA (
                p_id_factura_compra => p_id_factura_out,
                p_id_producto       => p_lineas(i).id_producto,
                p_id_lote           => p_lineas(i).id_lote,
                p_linea             => v_linea_num,
                p_cantidad          => p_lineas(i).cantidad,
                p_costo_unitario    => p_lineas(i).costo_unitario,
                p_porc_descuento    => NVL(p_lineas(i).porc_descuento, 0),
                p_porc_impuesto     => NVL(p_lineas(i).porc_impuesto, 13),
                p_auto_commit       => 'N'
            );
        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_compra_atomica;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_COM_OPERACION', 'PR_FACTURAR_COMPRA_ATOMICA', SQLCODE, SQLERRM);
            RAISE;
    END PR_FACTURAR_COMPRA_ATOMICA;

    PROCEDURE PR_REGISTRAR_ABONO_PAGAR (
        p_id_factura_compra  IN NUMBER,
        p_id_usuario         IN NUMBER,
        p_num_comprobante    IN VARCHAR2,
        p_monto_abono        IN NUMBER,
        p_observacion        IN VARCHAR2 DEFAULT NULL
    ) IS
        v_saldo_actual NUMBER(14,2);
    BEGIN
        SAVEPOINT sp_abono_pagar;

        -- Bloqueo NOWAIT sobre la cuenta por pagar para evitar doble pago simultaneo
        SELECT SALDO_CUPA
          INTO v_saldo_actual
          FROM COM_CUENTA_PAGAR
         WHERE ID_FACTURA_COMPRA = p_id_factura_compra
           FOR UPDATE NOWAIT;

        IF p_monto_abono > v_saldo_actual THEN
            RAISE_APPLICATION_ERROR(-20041,
                'El monto del abono (' || p_monto_abono || ') supera el saldo pendiente de la factura (' || v_saldo_actual || ').');
        END IF;

        INSERT INTO COM_ABONO_PAGAR (
            ID_ABONO_PAGAR, ID_FACTURA_COMPRA, ID_USUARIO,
            NUM_COMPROBANTE_ABPA, FECHA_ABPA, MONTO_ABPA,
            OBSERVACION_ABPA, ESTADO_ABPA
        ) VALUES (
            SEQ_COM_ABONO_PAGAR.NEXTVAL, p_id_factura_compra, p_id_usuario,
            p_num_comprobante, SYSDATE, p_monto_abono,
            p_observacion, 'A'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_abono_pagar;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_COM_OPERACION', 'PR_REGISTRAR_ABONO_PAGAR', SQLCODE, SQLERRM);
            RAISE;
    END PR_REGISTRAR_ABONO_PAGAR;

END PKG_COM_OPERACION;
/
SHOW ERRORS PACKAGE BODY PKG_COM_OPERACION;


--------------------------------------------------------------------------------
-- 5. PAQUETE: PKG_VEN_OPERACION
--    Facturacion a clientes, abonos a cuentas por cobrar y proceso automatico
--    de Cierre Diario con detalle por cajero y notificacion a Gerente/Coord.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_VEN_OPERACION IS

    -- Tipo para lineas de detalle en facturacion atomica de venta
    TYPE T_LINEA_VENTA IS RECORD (
        id_producto      NUMBER,
        id_servicio      NUMBER,
        id_lote          NUMBER,
        cantidad         NUMBER,
        precio_unitario  NUMBER,
        porc_descuento   NUMBER,
        porc_impuesto    NUMBER
    );
    TYPE T_LISTA_LINEAS_VENTA IS TABLE OF T_LINEA_VENTA;

    -- Crea el encabezado de una factura de venta
    PROCEDURE PR_CREAR_FACTURA_VENTA (
        p_id_cliente       IN  NUMBER,
        p_id_sucursal      IN  NUMBER,
        p_id_usuario       IN  NUMBER,
        p_num_factura      IN  VARCHAR2,
        p_es_credito       IN  VARCHAR2,
        p_subtotal         IN  NUMBER,
        p_descuento        IN  NUMBER,
        p_impuesto         IN  NUMBER,
        p_id_factura_out   OUT NUMBER,
        p_auto_commit      IN  VARCHAR2 DEFAULT 'S'
    );

    -- Agrega una linea de detalle a una factura de venta
    PROCEDURE PR_AGREGAR_DETALLE_VENTA (
        p_id_factura_venta IN NUMBER,
        p_id_producto      IN NUMBER,
        p_id_servicio      IN NUMBER,
        p_id_lote          IN NUMBER,
        p_linea            IN NUMBER,
        p_cantidad         IN NUMBER,
        p_precio_unitario  IN NUMBER,
        p_porc_descuento   IN NUMBER DEFAULT 0,
        p_porc_impuesto    IN NUMBER DEFAULT 13,
        p_auto_commit      IN VARCHAR2 DEFAULT 'S'
    );

    -- Procedimiento atomico integral: registra venta y lineas con SAVEPOINT unico
    PROCEDURE PR_FACTURAR_VENTA_ATOMICA (
        p_id_cliente       IN  NUMBER,
        p_id_sucursal      IN  NUMBER,
        p_id_usuario       IN  NUMBER,
        p_num_factura      IN  VARCHAR2,
        p_es_credito       IN  VARCHAR2,
        p_lineas           IN  T_LISTA_LINEAS_VENTA,
        p_id_factura_out   OUT NUMBER
    );

    -- Registra un abono de cliente a una factura en Cuentas por Cobrar
    PROCEDURE PR_REGISTRAR_ABONO_COBRAR (
        p_id_factura_venta IN NUMBER,
        p_id_usuario       IN NUMBER,
        p_tipo_pago        IN VARCHAR2,
        p_num_recibo       IN VARCHAR2,
        p_monto_abono      IN NUMBER,
        p_referencia       IN VARCHAR2 DEFAULT NULL
    );

    -- Ejecuta el cierre diario automatico con detalle por cajero y notifica a Coordinador y Gerente
    PROCEDURE PR_EJECUTAR_CIERRE_DIARIO (
        p_fecha IN DATE DEFAULT TRUNC(SYSDATE)
    );

END PKG_VEN_OPERACION;
/
SHOW ERRORS PACKAGE PKG_VEN_OPERACION;

CREATE OR REPLACE PACKAGE BODY PKG_VEN_OPERACION IS

    PROCEDURE PR_CREAR_FACTURA_VENTA (
        p_id_cliente       IN  NUMBER,
        p_id_sucursal      IN  NUMBER,
        p_id_usuario       IN  NUMBER,
        p_num_factura      IN  VARCHAR2,
        p_es_credito       IN  VARCHAR2,
        p_subtotal         IN  NUMBER,
        p_descuento        IN  NUMBER,
        p_impuesto         IN  NUMBER,
        p_id_factura_out   OUT NUMBER,
        p_auto_commit      IN  VARCHAR2 DEFAULT 'S'
    ) IS
        v_dias_cred   NUMBER(4);
        v_fecha_venc  DATE;
        v_estado      VARCHAR2(1);
    BEGIN
        SAVEPOINT sp_crear_venta;

        -- Bloqueo concurrente sobre el cliente (SELECT FOR UPDATE WAIT 5)
        SELECT DIAS_CREDITO_CLI
          INTO v_dias_cred
          FROM PER_CLIENTE
         WHERE ID_CLIENTE = p_id_cliente
           FOR UPDATE WAIT 5;

        IF UPPER(p_es_credito) = 'S' THEN
            v_fecha_venc := TRUNC(SYSDATE) + GREATEST(NVL(v_dias_cred, 30), 1);
            v_estado     := 'P'; -- Pendiente de cancelar
        ELSE
            v_fecha_venc := NULL;
            v_estado     := 'C'; -- Cancelada de contado
        END IF;

        p_id_factura_out := SEQ_VEN_FACTURA.NEXTVAL;

        INSERT INTO VEN_FACTURA (
            ID_FACTURA_VENTA, ID_CLIENTE, ID_SUCURSAL, ID_USUARIO,
            NUM_FACTURA_FAVE, FECHA_FAVE, ES_CREDITO_FAVE, FECHA_VENCIM_FAVE,
            SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE, ESTADO_FAVE
        ) VALUES (
            p_id_factura_out, p_id_cliente, p_id_sucursal, p_id_usuario,
            p_num_factura, SYSDATE, UPPER(p_es_credito), v_fecha_venc,
            p_subtotal, p_descuento, p_impuesto, v_estado
        );

        IF UPPER(p_auto_commit) = 'S' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_crear_venta;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_VEN_OPERACION', 'PR_CREAR_FACTURA_VENTA', SQLCODE, SQLERRM);
            RAISE;
    END PR_CREAR_FACTURA_VENTA;

    PROCEDURE PR_AGREGAR_DETALLE_VENTA (
        p_id_factura_venta IN NUMBER,
        p_id_producto      IN NUMBER,
        p_id_servicio      IN NUMBER,
        p_id_lote          IN NUMBER,
        p_linea            IN NUMBER,
        p_cantidad         IN NUMBER,
        p_precio_unitario  IN NUMBER,
        p_porc_descuento   IN NUMBER DEFAULT 0,
        p_porc_impuesto    IN NUMBER DEFAULT 13,
        p_auto_commit      IN VARCHAR2 DEFAULT 'S'
    ) IS
    BEGIN
        SAVEPOINT sp_det_venta;

        INSERT INTO VEN_FACTURA_DET (
            ID_FACTURA_VENTA_DET, ID_FACTURA_VENTA, ID_PRODUCTO, ID_SERVICIO,
            ID_LOTE, LINEA_FVDE, CANTIDAD_FVDE, PRECIO_UNITARIO_FVDE,
            PORC_DESCUENTO_FVDE, PORC_IMPUESTO_FVDE
        ) VALUES (
            SEQ_VEN_FACTURA_DET.NEXTVAL, p_id_factura_venta, p_id_producto, p_id_servicio,
            p_id_lote, p_linea, p_cantidad, p_precio_unitario,
            p_porc_descuento, p_porc_impuesto
        );

        IF UPPER(p_auto_commit) = 'S' THEN
            COMMIT;
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_det_venta;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_VEN_OPERACION', 'PR_AGREGAR_DETALLE_VENTA', SQLCODE, SQLERRM);
            RAISE;
    END PR_AGREGAR_DETALLE_VENTA;

    PROCEDURE PR_FACTURAR_VENTA_ATOMICA (
        p_id_cliente       IN  NUMBER,
        p_id_sucursal      IN  NUMBER,
        p_id_usuario       IN  NUMBER,
        p_num_factura      IN  VARCHAR2,
        p_es_credito       IN  VARCHAR2,
        p_lineas           IN  T_LISTA_LINEAS_VENTA,
        p_id_factura_out   OUT NUMBER
    ) IS
        v_subtotal  NUMBER(14,2) := 0;
        v_descuento NUMBER(14,2) := 0;
        v_impuesto  NUMBER(14,2) := 0;
        v_linea_num NUMBER := 0;
    BEGIN
        SAVEPOINT sp_venta_atomica;

        IF p_lineas IS NULL OR p_lineas.COUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20043, 'No se puede emitir una factura de venta sin lineas de detalle.');
        END IF;

        FOR i IN 1..p_lineas.COUNT LOOP
            DECLARE
                v_lin_sub NUMBER := ROUND(p_lineas(i).cantidad * p_lineas(i).precio_unitario, 2);
                v_lin_des NUMBER := ROUND(v_lin_sub * (NVL(p_lineas(i).porc_descuento, 0) / 100), 2);
                v_lin_imp NUMBER := ROUND((v_lin_sub - v_lin_des) * (NVL(p_lineas(i).porc_impuesto, 13) / 100), 2);
            BEGIN
                v_subtotal  := v_subtotal + v_lin_sub;
                v_descuento := v_descuento + v_lin_des;
                v_impuesto  := v_impuesto + v_lin_imp;
            END;
        END LOOP;

        PR_CREAR_FACTURA_VENTA (
            p_id_cliente     => p_id_cliente,
            p_id_sucursal    => p_id_sucursal,
            p_id_usuario     => p_id_usuario,
            p_num_factura    => p_num_factura,
            p_es_credito     => p_es_credito,
            p_subtotal       => v_subtotal,
            p_descuento      => v_descuento,
            p_impuesto       => v_impuesto,
            p_id_factura_out => p_id_factura_out,
            p_auto_commit    => 'N'
        );

        FOR i IN 1..p_lineas.COUNT LOOP
            v_linea_num := v_linea_num + 1;
            PR_AGREGAR_DETALLE_VENTA (
                p_id_factura_venta => p_id_factura_out,
                p_id_producto      => p_lineas(i).id_producto,
                p_id_servicio      => p_lineas(i).id_servicio,
                p_id_lote          => p_lineas(i).id_lote,
                p_linea            => v_linea_num,
                p_cantidad         => p_lineas(i).cantidad,
                p_precio_unitario  => p_lineas(i).precio_unitario,
                p_porc_descuento   => NVL(p_lineas(i).porc_descuento, 0),
                p_porc_impuesto    => NVL(p_lineas(i).porc_impuesto, 13),
                p_auto_commit      => 'N'
            );
        END LOOP;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_venta_atomica;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_VEN_OPERACION', 'PR_FACTURAR_VENTA_ATOMICA', SQLCODE, SQLERRM);
            RAISE;
    END PR_FACTURAR_VENTA_ATOMICA;

    PROCEDURE PR_REGISTRAR_ABONO_COBRAR (
        p_id_factura_venta IN NUMBER,
        p_id_usuario       IN NUMBER,
        p_tipo_pago        IN VARCHAR2,
        p_num_recibo       IN VARCHAR2,
        p_monto_abono      IN NUMBER,
        p_referencia       IN VARCHAR2 DEFAULT NULL
    ) IS
        v_saldo_actual NUMBER(14,2);
    BEGIN
        SAVEPOINT sp_abono_cobrar;

        SELECT SALDO_CUCO
          INTO v_saldo_actual
          FROM VEN_CUENTA_COBRAR
         WHERE ID_FACTURA_VENTA = p_id_factura_venta
           FOR UPDATE NOWAIT;

        IF p_monto_abono > v_saldo_actual THEN
            RAISE_APPLICATION_ERROR(-20042,
                'El monto del abono (' || p_monto_abono || ') supera el saldo pendiente de la factura (' || v_saldo_actual || ').');
        END IF;

        INSERT INTO VEN_ABONO_COBRAR (
            ID_ABONO_COBRAR, ID_FACTURA_VENTA, ID_USUARIO,
            TIPO_PAGO_ABCO, NUM_RECIBO_ABCO, FECHA_ABCO,
            MONTO_ABCO, REFERENCIA_ABCO, ESTADO_ABCO
        ) VALUES (
            SEQ_VEN_ABONO_COBRAR.NEXTVAL, p_id_factura_venta, p_id_usuario,
            UPPER(p_tipo_pago), p_num_recibo, SYSDATE,
            p_monto_abono, p_referencia, 'A'
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_abono_cobrar;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_VEN_OPERACION', 'PR_REGISTRAR_ABONO_COBRAR', SQLCODE, SQLERRM);
            RAISE;
    END PR_REGISTRAR_ABONO_COBRAR;

    PROCEDURE PR_EJECUTAR_CIERRE_DIARIO (
        p_fecha IN DATE DEFAULT TRUNC(SYSDATE)
    ) IS
        v_fecha          DATE := TRUNC(NVL(p_fecha, SYSDATE));
        v_id_cierre      NUMBER(12);
        v_cant_fac       NUMBER(10);
        v_cant_vendida   NUMBER(14,3);
        v_monto_ventas   NUMBER(14,2);
        v_cant_devol     NUMBER(14,3);
        v_monto_devol    NUMBER(14,2);
        v_destinatarios  VARCHAR2(400);
        v_cuerpo         CLOB;

        CURSOR c_sucursales IS
            SELECT ID_SUCURSAL, CODIGO_SUC, NOMBRE_SUC
              FROM SEG_SUCURSAL
             WHERE ESTADO_SUC = 'A'
             ORDER BY ID_SUCURSAL;

        CURSOR c_cajeros (p_id_suc NUMBER, p_fec DATE) IS
            SELECT u.ID_USUARIO,
                   u.NOMBRE_USUARIO_USU,
                   pf.NOMBRE_PEFI || ' ' || pf.APELLIDO1_PEFI AS NOMBRE_CAJERO,
                   NVL(v.CANT_FAC, 0)     AS CANT_FAC,
                   NVL(v.CANT_VEND, 0)    AS CANT_VEND,
                   NVL(v.MONTO_VEND, 0)   AS MONTO_VEND,
                   NVL(dv.CANT_DEV, 0)    AS CANT_DEV,
                   NVL(dv.MONTO_DEV, 0)   AS MONTO_DEV
              FROM SEG_USUARIO u
                   JOIN PER_PERSONA_FISICA pf ON pf.ID_PERSONA_FISICA = u.ID_PERSONA_FISICA
                   LEFT JOIN (
                       SELECT f.ID_USUARIO,
                              COUNT(DISTINCT f.ID_FACTURA_VENTA) AS CANT_FAC,
                              NVL(SUM(fd.CANTIDAD_FVDE), 0)      AS CANT_VEND,
                              NVL(SUM(fd.SUBTOTAL_FVDE - fd.MONTO_DESCUENTO_FVDE + fd.MONTO_IMPUESTO_FVDE), 0) AS MONTO_VEND
                         FROM VEN_FACTURA f
                              LEFT JOIN VEN_FACTURA_DET fd ON fd.ID_FACTURA_VENTA = f.ID_FACTURA_VENTA
                        WHERE f.ID_SUCURSAL = p_id_suc
                          AND TRUNC(f.FECHA_FAVE) = p_fec
                          AND f.ESTADO_FAVE <> 'N'
                        GROUP BY f.ID_USUARIO
                   ) v ON v.ID_USUARIO = u.ID_USUARIO
                   LEFT JOIN (
                       SELECT d.ID_USUARIO,
                              NVL(SUM(dd.CANTIDAD_DVVD), 0) AS CANT_DEV,
                              NVL(SUM(ROUND(dd.CANTIDAD_DVVD * fd.PRECIO_UNITARIO_FVDE *
                                      (1 - fd.PORC_DESCUENTO_FVDE/100) * (1 + fd.PORC_IMPUESTO_FVDE/100), 2)), 0) AS MONTO_DEV
                         FROM VEN_DEVOLUCION d
                              JOIN VEN_FACTURA f        ON f.ID_FACTURA_VENTA      = d.ID_FACTURA_VENTA
                              JOIN VEN_DEVOLUCION_DET dd ON dd.ID_DEVOLUCION_VENTA = d.ID_DEVOLUCION_VENTA
                              JOIN VEN_FACTURA_DET fd   ON fd.ID_FACTURA_VENTA_DET = dd.ID_FACTURA_VENTA_DET
                        WHERE f.ID_SUCURSAL = p_id_suc
                          AND TRUNC(d.FECHA_DEVV) = p_fec
                          AND d.ESTADO_DEVV = 'A'
                        GROUP BY d.ID_USUARIO
                   ) dv ON dv.ID_USUARIO = u.ID_USUARIO
             WHERE NVL(v.CANT_FAC, 0) > 0
                OR NVL(dv.CANT_DEV, 0) > 0
                OR EXISTS (SELECT 1 FROM SEG_USUARIO_SUCURSAL us
                            WHERE us.ID_USUARIO = u.ID_USUARIO
                              AND us.ID_SUCURSAL = p_id_suc
                              AND us.ESTADO_USSU = 'A')
             ORDER BY u.ID_USUARIO;
    BEGIN
        SAVEPOINT sp_cierre_diario;

        v_destinatarios := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR') || ',' ||
                           PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_GERENTE');

        v_cuerpo := 'REPORTE DE CIERRE DIARIO AUTOMATICO - FECHA: ' || TO_CHAR(v_fecha, 'YYYY-MM-DD') || CHR(10) ||
                    RPAD('=', 82, '=') || CHR(10);

        FOR s IN c_sucursales LOOP
            -- Calcular totales del encabezado de cierre para la sucursal
            SELECT COUNT(DISTINCT f.ID_FACTURA_VENTA),
                   NVL(SUM(fd.CANTIDAD_FVDE), 0),
                   NVL(SUM(fd.SUBTOTAL_FVDE - fd.MONTO_DESCUENTO_FVDE + fd.MONTO_IMPUESTO_FVDE), 0)
              INTO v_cant_fac, v_cant_vendida, v_monto_ventas
              FROM VEN_FACTURA f
                   LEFT JOIN VEN_FACTURA_DET fd ON fd.ID_FACTURA_VENTA = f.ID_FACTURA_VENTA
             WHERE f.ID_SUCURSAL = s.ID_SUCURSAL
               AND TRUNC(f.FECHA_FAVE) = v_fecha
               AND f.ESTADO_FAVE <> 'N';

            SELECT NVL(SUM(dd.CANTIDAD_DVVD), 0),
                   NVL(SUM(ROUND(dd.CANTIDAD_DVVD * fd.PRECIO_UNITARIO_FVDE *
                           (1 - fd.PORC_DESCUENTO_FVDE/100) * (1 + fd.PORC_IMPUESTO_FVDE/100), 2)), 0)
              INTO v_cant_devol, v_monto_devol
              FROM VEN_DEVOLUCION d
                   JOIN VEN_FACTURA f         ON f.ID_FACTURA_VENTA      = d.ID_FACTURA_VENTA
                   JOIN VEN_DEVOLUCION_DET dd ON dd.ID_DEVOLUCION_VENTA  = d.ID_DEVOLUCION_VENTA
                   JOIN VEN_FACTURA_DET fd    ON fd.ID_FACTURA_VENTA_DET = dd.ID_FACTURA_VENTA_DET
             WHERE f.ID_SUCURSAL = s.ID_SUCURSAL
               AND TRUNC(d.FECHA_DEVV) = v_fecha
               AND d.ESTADO_DEVV = 'A';

            -- Insertar o actualizar el encabezado VEN_CIERRE_DIARIO
            BEGIN
                SELECT ID_CIERRE_DIARIO INTO v_id_cierre
                  FROM VEN_CIERRE_DIARIO
                 WHERE ID_SUCURSAL = s.ID_SUCURSAL
                   AND FECHA_CIDI  = v_fecha;

                UPDATE VEN_CIERRE_DIARIO
                   SET CANT_FACTURAS_CIDI = v_cant_fac,
                       CANT_VENDIDA_CIDI  = v_cant_vendida,
                       MONTO_VENTAS_CIDI  = v_monto_ventas,
                       CANT_DEVOL_CIDI    = v_cant_devol,
                       MONTO_DEVOL_CIDI   = v_monto_devol,
                       USUARIO_MOD_CIDI   = USER,
                       FECHA_MOD_CIDI     = SYSTIMESTAMP
                 WHERE ID_CIERRE_DIARIO = v_id_cierre;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_id_cierre := SEQ_VEN_CIERRE_DIARIO.NEXTVAL;
                    INSERT INTO VEN_CIERRE_DIARIO (
                        ID_CIERRE_DIARIO, ID_SUCURSAL, FECHA_CIDI,
                        CANT_FACTURAS_CIDI, CANT_VENDIDA_CIDI, MONTO_VENTAS_CIDI,
                        CANT_DEVOL_CIDI, MONTO_DEVOL_CIDI, OBSERVACION_CIDI, ESTADO_CIDI
                    ) VALUES (
                        v_id_cierre, s.ID_SUCURSAL, v_fecha,
                        v_cant_fac, v_cant_vendida, v_monto_ventas,
                        v_cant_devol, v_monto_devol,
                        'Cierre diario automatico ejecutado el ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI'), 'A'
                    );
            END;

            v_cuerpo := v_cuerpo ||
                        'SUCURSAL: ' || s.CODIGO_SUC || ' - ' || s.NOMBRE_SUC || CHR(10) ||
                        '  Fecha: ' || TO_CHAR(v_fecha, 'YYYY-MM-DD') ||
                        ' | Cant. Vendida: ' || v_cant_vendida ||
                        ' | Ventas: CRC ' || TO_CHAR(v_monto_ventas, 'FM999G999G990D00') ||
                        ' | Devoluciones: CRC ' || TO_CHAR(v_monto_devol, 'FM999G999G990D00') ||
                        ' | TOTAL NETO: CRC ' || TO_CHAR(v_monto_ventas - v_monto_devol, 'FM999G999G990D00') || CHR(10) ||
                        '  Detalle por Cajero:' || CHR(10);

            FOR cj IN c_cajeros(s.ID_SUCURSAL, v_fecha) LOOP
                MERGE INTO VEN_CIERRE_DIARIO_DET dest
                USING (SELECT v_id_cierre AS ID_CIERRE_DIARIO, cj.ID_USUARIO AS ID_USUARIO FROM dual) src
                   ON (dest.ID_CIERRE_DIARIO = src.ID_CIERRE_DIARIO AND dest.ID_USUARIO = src.ID_USUARIO)
                WHEN MATCHED THEN
                    UPDATE SET dest.CANT_FACTURAS_CIDE = cj.CANT_FAC,
                               dest.CANT_VENDIDA_CIDE  = cj.CANT_VEND,
                               dest.MONTO_VENTAS_CIDE  = cj.MONTO_VEND,
                               dest.CANT_DEVOL_CIDE    = cj.CANT_DEV,
                               dest.MONTO_DEVOL_CIDE   = cj.MONTO_DEV,
                               dest.USUARIO_MOD_CIDE   = USER,
                               dest.FECHA_MOD_CIDE     = SYSTIMESTAMP
                WHEN NOT MATCHED THEN
                    INSERT (
                        ID_CIERRE_DIARIO_DET, ID_CIERRE_DIARIO, ID_USUARIO,
                        CANT_FACTURAS_CIDE, CANT_VENDIDA_CIDE, MONTO_VENTAS_CIDE,
                        CANT_DEVOL_CIDE, MONTO_DEVOL_CIDE
                    ) VALUES (
                        SEQ_VEN_CIERRE_DIARIO_DET.NEXTVAL, v_id_cierre, cj.ID_USUARIO,
                        cj.CANT_FAC, cj.CANT_VEND, cj.MONTO_VEND,
                        cj.CANT_DEV, cj.MONTO_DEV
                    );

                v_cuerpo := v_cuerpo ||
                            '    - Cajero: ' || RPAD(cj.NOMBRE_USUARIO_USU || ' (' || cj.NOMBRE_CAJERO || ')', 32) ||
                            ' | Cant. Vendida: ' || LPAD(cj.CANT_VEND, 6) ||
                            ' | Devoluciones: ' || LPAD(cj.CANT_DEV, 5) ||
                            ' | Neto: CRC ' || TO_CHAR(cj.MONTO_VEND - cj.MONTO_DEV, 'FM999G999G990D00') || CHR(10);
            END LOOP;

            v_cuerpo := v_cuerpo || RPAD('-', 82, '-') || CHR(10);
        END LOOP;

        COMMIT;

        -- Refrescar las 2 Vistas Materializadas al finalizar el cierre diario
        BEGIN
            DBMS_MVIEW.REFRESH('MV_VENTAS_MENSUALES', 'C');
            DBMS_MVIEW.REFRESH('MV_INVENTARIO_CONSOLIDADO', 'C');
        EXCEPTION WHEN OTHERS THEN NULL;
        END;

        PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
            p_destinatarios => v_destinatarios,
            p_asunto        => 'Cierre Diario Automatico Super Brunca - ' || TO_CHAR(v_fecha, 'YYYY-MM-DD'),
            p_cuerpo        => v_cuerpo
        );
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_cierre_diario;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_VEN_OPERACION', 'PR_EJECUTAR_CIERRE_DIARIO', SQLCODE, SQLERRM);
            RAISE;
    END PR_EJECUTAR_CIERRE_DIARIO;

END PKG_VEN_OPERACION;
/
SHOW ERRORS PACKAGE BODY PKG_VEN_OPERACION;


--------------------------------------------------------------------------------
-- 6. PAQUETE: PKG_ADM_MONITOREO
--    Monitoreo diario de tablespaces (<= 85%), objetos invalidos, estado de
--    indices, errores de sistema, sesiones y crecimiento de la BD (Requerimiento #13).
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_ADM_MONITOREO IS

    -- Verifica que ningun tablespace del proyecto supere el 85% (parametrizado)
    PROCEDURE PR_VERIFICAR_TABLESPACES;

    -- Verifica si existen objetos invalidos en el esquema CADENA_NEG
    PROCEDURE PR_VERIFICAR_OBJETOS_INVALIDOS;

    -- Verifica si existen indices danados o en estado UNUSABLE
    PROCEDURE PR_VERIFICAR_INDICES_DANADOS;

    -- Monitorea errores de sistema registrados en las ultimas 24 horas (AUD_ERROR_SISTEMA)
    PROCEDURE PR_VERIFICAR_ERRORES_SISTEMA;

    -- Monitorea el crecimiento de la BD comparando contra medicion anterior y sesiones
    PROCEDURE PR_MONITOREAR_SESIONES_Y_CRECIMIENTO;

    -- Proceso diario integral invocado por DBMS_SCHEDULER con aislamiento de fallos
    PROCEDURE PR_EJECUTAR_MONITOREO_DIARIO;

END PKG_ADM_MONITOREO;
/
SHOW ERRORS PACKAGE PKG_ADM_MONITOREO;

CREATE OR REPLACE PACKAGE BODY PKG_ADM_MONITOREO IS

    PROCEDURE PR_VERIFICAR_TABLESPACES IS
        v_umbral_max    NUMBER;
        v_correo_dba    VARCHAR2(200);
        v_cuerpo_alerta CLOB;
        v_inconsist     PLS_INTEGER := 0;
        v_flag          VARCHAR2(1);

        CURSOR c_tbs IS
            SELECT df.tablespace_name,
                   ROUND(SUM(df.bytes) / 1024 / 1024, 2) AS mb_asignados,
                   ROUND((SUM(df.bytes) - NVL(fs.bytes_libres, 0)) / 1024 / 1024, 2) AS mb_usados,
                   ROUND(((SUM(df.bytes) - NVL(fs.bytes_libres, 0)) /
                         DECODE(SUM(CASE WHEN df.maxbytes > df.bytes THEN df.maxbytes ELSE df.bytes END), 0, 1,
                                SUM(CASE WHEN df.maxbytes > df.bytes THEN df.maxbytes ELSE df.bytes END))) * 100, 2) AS porc_uso_max,
                   ROUND(((SUM(df.bytes) - NVL(fs.bytes_libres, 0)) / NULLIF(SUM(df.bytes), 0)) * 100, 2) AS porc_uso_actual
              FROM sys.dba_data_files df
                   LEFT JOIN (
                       SELECT tablespace_name, SUM(bytes) AS bytes_libres
                         FROM sys.dba_free_space
                        GROUP BY tablespace_name
                   ) fs ON fs.tablespace_name = df.tablespace_name
             WHERE df.tablespace_name LIKE 'TBS_%'
             GROUP BY df.tablespace_name, fs.bytes_libres
             ORDER BY df.tablespace_name;
    BEGIN
        v_umbral_max := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('PORC_MAX_TABLESPACE');
        v_correo_dba := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_DBA');

        v_cuerpo_alerta := 'ALERTA DE CAPACIDAD DE TABLESPACES (> ' || v_umbral_max || '%)' || CHR(10) ||
                           RPAD('=', 72, '=') || CHR(10);

        FOR r IN c_tbs LOOP
            IF r.porc_uso_actual > v_umbral_max THEN
                v_flag      := 'S';
                v_inconsist := v_inconsist + 1;
                v_cuerpo_alerta := v_cuerpo_alerta ||
                                   'Tablespace: ' || r.tablespace_name ||
                                   ' | Usado: ' || r.mb_usados || ' MB de ' || r.mb_asignados || ' MB (' ||
                                   r.porc_uso_actual || '% > ' || v_umbral_max || '%)' || CHR(10);
            ELSE
                v_flag := 'N';
            END IF;

            INSERT INTO AUD_MONITOREO_BD (
                ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
            ) VALUES (
                SEQ_AUD_MONITOREO_BD.NEXTVAL, 'TABLESPACE', r.tablespace_name,
                r.porc_uso_actual, v_umbral_max, v_flag,
                'Usado: ' || r.mb_usados || ' MB / ' || r.mb_asignados || ' MB (' || r.porc_uso_actual || '% actual, ' || r.porc_uso_max || '% sobre maxsize).'
            );
        END LOOP;

        COMMIT;

        IF v_inconsist > 0 THEN
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_dba,
                p_asunto        => 'INCONSISTENCIA BD: ' || v_inconsist || ' Tablespace(s) superan el ' || v_umbral_max || '%',
                p_cuerpo        => v_cuerpo_alerta
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('[OK] Monitoreo Tablespaces: Todos por debajo del ' || v_umbral_max || '%.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_MONITOREO', 'PR_VERIFICAR_TABLESPACES', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_TABLESPACES;

    PROCEDURE PR_VERIFICAR_OBJETOS_INVALIDOS IS
        v_correo_dba    VARCHAR2(200);
        v_cuerpo_alerta CLOB;
        v_inconsist     PLS_INTEGER := 0;

        CURSOR c_invalidos IS
            SELECT object_type, object_name, status, last_ddl_time
              FROM all_objects
             WHERE owner  = 'CADENA_NEG'
               AND status <> 'VALID'
             ORDER BY object_type, object_name;
    BEGIN
        v_correo_dba := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_DBA');
        v_cuerpo_alerta := 'INCONSISTENCIA DETECTADA: OBJETOS INVALIDOS EN ESQUEMA CADENA_NEG' || CHR(10) ||
                           RPAD('=', 72, '=') || CHR(10);

        FOR r IN c_invalidos LOOP
            v_inconsist := v_inconsist + 1;
            v_cuerpo_alerta := v_cuerpo_alerta ||
                               RPAD(r.object_type, 20) || RPAD(r.object_name, 32) || 'Estado: ' || r.status || CHR(10);

            INSERT INTO AUD_MONITOREO_BD (
                ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
            ) VALUES (
                SEQ_AUD_MONITOREO_BD.NEXTVAL, 'OBJETO_INVALIDO', r.object_name,
                1, 0, 'S', 'Objeto ' || r.object_type || ' ' || r.object_name || ' en estado ' || r.status
            );
        END LOOP;

        IF v_inconsist = 0 THEN
            INSERT INTO AUD_MONITOREO_BD (
                ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
            ) VALUES (
                SEQ_AUD_MONITOREO_BD.NEXTVAL, 'OBJETO_INVALIDO', 'ESQUEMA_CADENA_NEG',
                0, 0, 'N', 'Verificacion diaria: 0 objetos invalidos.'
            );
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('[OK] Monitoreo Objetos Invalidos: 0 objetos invalidos encontrados.');
        ELSE
            COMMIT;
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_dba,
                p_asunto        => 'INCONSISTENCIA BD: ' || v_inconsist || ' Objeto(s) Invalido(s) en CADENA_NEG',
                p_cuerpo        => v_cuerpo_alerta
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_MONITOREO', 'PR_VERIFICAR_OBJETOS_INVALIDOS', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_OBJETOS_INVALIDOS;

    PROCEDURE PR_VERIFICAR_INDICES_DANADOS IS
        v_correo_dba    VARCHAR2(200);
        v_cuerpo_alerta CLOB;
        v_inconsist     PLS_INTEGER := 0;

        CURSOR c_indices_danados IS
            SELECT index_name, table_name, tablespace_name, status
              FROM all_indexes
             WHERE owner  = 'CADENA_NEG'
               AND status <> 'VALID'
             ORDER BY index_name;
    BEGIN
        v_correo_dba := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_DBA');
        v_cuerpo_alerta := 'INCONSISTENCIA DETECTADA: INDICES DANADOS O UNUSABLE EN CADENA_NEG' || CHR(10) ||
                           RPAD('=', 72, '=') || CHR(10);

        FOR r IN c_indices_danados LOOP
            v_inconsist := v_inconsist + 1;
            v_cuerpo_alerta := v_cuerpo_alerta ||
                               'Indice: ' || RPAD(r.index_name, 28) ||
                               ' | Tabla: ' || RPAD(r.table_name, 24) ||
                               ' | Estado: ' || r.status || CHR(10);

            INSERT INTO AUD_MONITOREO_BD (
                ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
            ) VALUES (
                SEQ_AUD_MONITOREO_BD.NEXTVAL, 'INDICE', r.index_name,
                1, 0, 'S', 'Indice sobre ' || r.table_name || ' se encuentra en estado ' || r.status
            );
        END LOOP;

        IF v_inconsist = 0 THEN
            INSERT INTO AUD_MONITOREO_BD (
                ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
            ) VALUES (
                SEQ_AUD_MONITOREO_BD.NEXTVAL, 'INDICE', 'TODOS_LOS_INDICES',
                0, 0, 'N', 'Verificacion diaria: Todos los indices del esquema estan VALID.'
            );
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('[OK] Monitoreo Indices: Todos los indices se encuentran VALID.');
        ELSE
            COMMIT;
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_dba,
                p_asunto        => 'INCONSISTENCIA BD: ' || v_inconsist || ' Indice(s) Danado(s) / UNUSABLE',
                p_cuerpo        => v_cuerpo_alerta
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_MONITOREO', 'PR_VERIFICAR_INDICES_DANADOS', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_INDICES_DANADOS;

    PROCEDURE PR_VERIFICAR_ERRORES_SISTEMA IS
        v_correo_dba    VARCHAR2(200);
        v_cuerpo_alerta CLOB;
        v_cant_errores  NUMBER := 0;

        CURSOR c_errores_recientes IS
            SELECT ID_ERROR_SISTEMA, OBJETO_ERSI, SUBPROGRAMA_ERSI, CODIGO_ERROR_ERSI,
                   SUBSTR(MENSAJE_ERROR_ERSI, 1, 100) AS MENSAJE_CORTO, FECHA_ERSI
              FROM AUD_ERROR_SISTEMA
             WHERE FECHA_ERSI >= SYSTIMESTAMP - INTERVAL '1' DAY
             ORDER BY FECHA_ERSI DESC;
    BEGIN
        v_correo_dba := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_DBA');
        v_cuerpo_alerta := 'INCONSISTENCIA DETECTADA: ERRORES DE SISTEMA EN LAS ULTIMAS 24 HORAS' || CHR(10) ||
                           RPAD('=', 80, '=') || CHR(10);

        FOR e IN c_errores_recientes LOOP
            v_cant_errores := v_cant_errores + 1;
            IF v_cant_errores <= 20 THEN
                v_cuerpo_alerta := v_cuerpo_alerta ||
                                   TO_CHAR(e.FECHA_ERSI, 'HH24:MI:SS') || ' | ' ||
                                   RPAD(NVL(e.OBJETO_ERSI, 'N/A') || '.' || NVL(e.SUBPROGRAMA_ERSI, 'N/A'), 35) ||
                                   ' | ORA' || LPAD(e.CODIGO_ERROR_ERSI, 6) || ' | ' || e.MENSAJE_CORTO || CHR(10);
            END IF;
        END LOOP;

        INSERT INTO AUD_MONITOREO_BD (
            ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
            VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
        ) VALUES (
            SEQ_AUD_MONITOREO_BD.NEXTVAL, 'ERROR_SISTEMA', 'AUD_ERROR_SISTEMA',
            v_cant_errores, 0, CASE WHEN v_cant_errores > 0 THEN 'S' ELSE 'N' END,
            'Errores registrados en ultimas 24h: ' || v_cant_errores
        );
        COMMIT;

        IF v_cant_errores > 0 THEN
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_dba,
                p_asunto        => 'ALERTA BD: ' || v_cant_errores || ' Error(es) de Sistema en ultimas 24h',
                p_cuerpo        => v_cuerpo_alerta
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('[OK] Monitoreo Errores: 0 errores detectados en las ultimas 24 horas.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_MONITOREO', 'PR_VERIFICAR_ERRORES_SISTEMA', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_ERRORES_SISTEMA;

    PROCEDURE PR_MONITOREAR_SESIONES_Y_CRECIMIENTO IS
        v_mb_esquema      NUMBER(14,2);
        v_mb_anterior     NUMBER(14,2);
        v_dif_mb          NUMBER(14,2);
        v_max_crecimiento NUMBER;
        v_max_sesiones    NUMBER;
        v_correo_dba      VARCHAR2(200);
        v_sesiones_tot    NUMBER;
        v_bloqueadas      NUMBER;
    BEGIN
        v_max_crecimiento := NVL(PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MB_MAX_CRECIMIENTO'), 3000);
        v_max_sesiones    := NVL(PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MAX_SESIONES_ACTIVAS'), 100);
        v_correo_dba      := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_DBA');

        SELECT ROUND(NVL(SUM(bytes), 0) / 1024 / 1024, 2)
          INTO v_mb_esquema
          FROM user_segments;

        -- Comparar contra la medicion anterior en AUD_MONITOREO_BD
        BEGIN
            SELECT VALOR_ACTUAL_MOBD INTO v_mb_anterior
              FROM (
                  SELECT VALOR_ACTUAL_MOBD
                    FROM AUD_MONITOREO_BD
                   WHERE TIPO_VERIF_MOBD = 'CRECIMIENTO'
                     AND NOMBRE_OBJETO_MOBD = 'SEGMENTOS_CADENA_NEG'
                   ORDER BY FECHA_HORA_MOBD DESC
              )
             WHERE ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_mb_anterior := v_mb_esquema;
        END;

        v_dif_mb := ROUND(v_mb_esquema - v_mb_anterior, 2);

        SELECT COUNT(*),
               NVL(SUM(CASE WHEN blocking_session IS NOT NULL THEN 1 ELSE 0 END), 0)
          INTO v_sesiones_tot, v_bloqueadas
          FROM sys.v_$session
         WHERE type = 'USER';

        INSERT INTO AUD_MONITOREO_BD (
            ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
            VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
        ) VALUES (
            SEQ_AUD_MONITOREO_BD.NEXTVAL, 'CRECIMIENTO', 'SEGMENTOS_CADENA_NEG',
            v_mb_esquema, v_max_crecimiento, CASE WHEN v_mb_esquema > v_max_crecimiento THEN 'S' ELSE 'N' END,
            'Espacio total: ' || v_mb_esquema || ' MB (Umbral: ' || v_max_crecimiento || ' MB). Variacion vs anterior: ' ||
            CASE WHEN v_dif_mb >= 0 THEN '+' ELSE '' END || v_dif_mb || ' MB.'
        );

        INSERT INTO AUD_MONITOREO_BD (
            ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
            VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
        ) VALUES (
            SEQ_AUD_MONITOREO_BD.NEXTVAL, 'SESION', 'SESIONES_USUARIO',
            v_sesiones_tot, v_max_sesiones, CASE WHEN v_bloqueadas > 0 OR v_sesiones_tot > v_max_sesiones THEN 'S' ELSE 'N' END,
            'Sesiones conectadas: ' || v_sesiones_tot || ' (Maximo: ' || v_max_sesiones || ') | Bloqueadas: ' || v_bloqueadas
        );

        COMMIT;

        -- Alerta automatica por correo al DBA si se detectan bloqueos o exceso de concurrencia
        IF v_bloqueadas > 0 OR v_sesiones_tot > v_max_sesiones THEN
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_dba,
                p_asunto        => 'ALERTA SESIONES: ' || v_sesiones_tot || ' activas / ' || v_bloqueadas || ' bloqueadas',
                p_cuerpo        => 'Alerta de concurrencia y bloqueo de sesiones:' || CHR(10) ||
                                   'Total sesiones de usuario: ' || v_sesiones_tot || ' (Umbral maximo: ' || v_max_sesiones || ')' || CHR(10) ||
                                   'Sesiones bloqueadas detectadas: ' || v_bloqueadas || CHR(10) ||
                                   'Fecha/Hora: ' || TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS')
            );
        END IF;

        DBMS_OUTPUT.PUT_LINE('[OK] Monitoreo Crecimiento y Sesiones: ' || v_mb_esquema ||
                             ' MB (Var: ' || v_dif_mb || ' MB) | ' || v_sesiones_tot || ' sesiones (' || v_bloqueadas || ' bloqueadas).');
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_MONITOREO', 'PR_MONITOREAR_SESIONES_Y_CRECIMIENTO', SQLCODE, SQLERRM);
            RAISE;
    END PR_MONITOREAR_SESIONES_Y_CRECIMIENTO;

    PROCEDURE PR_EJECUTAR_MONITOREO_DIARIO IS
    BEGIN
        -- Aislamiento de pasos: cada modulo de monitoreo se ejecuta en su propio bloque protegido
        BEGIN PR_VERIFICAR_TABLESPACES;             EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PR_VERIFICAR_OBJETOS_INVALIDOS;       EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PR_VERIFICAR_INDICES_DANADOS;         EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PR_VERIFICAR_ERRORES_SISTEMA;         EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PR_MONITOREAR_SESIONES_Y_CRECIMIENTO; EXCEPTION WHEN OTHERS THEN NULL; END;
        BEGIN PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS; EXCEPTION WHEN OTHERS THEN NULL; END;
    END PR_EJECUTAR_MONITOREO_DIARIO;

END PKG_ADM_MONITOREO;
/
SHOW ERRORS PACKAGE BODY PKG_ADM_MONITOREO;

PROMPT === FIN DE 03_Paquetes_Negocio_Monitoreo.sql ===
