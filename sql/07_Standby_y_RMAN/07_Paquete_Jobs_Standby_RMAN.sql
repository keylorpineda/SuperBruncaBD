-- =============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c EE (compatible con 26ai Free)
-- ARCHIVO:  sql/07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql
-- CURSO:    Administracion de Bases de Datos
-- DESCRIPCION:
-- Automatiza con DBMS_SCHEDULER (Requerimiento 5) todas las tareas del
-- Standby y de RMAN, leyendo sus valores de SEG_PARAMETRO (Requerimiento 10):
--
-- JOB_STANDBY_TRASLADO_ARCHIVELOG  cada STANDBY_SYNC_MIN minutos (10)
-- Copia archivelogs y respaldos RMAN de la PC principal a la PC standby.
-- JOB_RMAN_BACKUP_DIARIO           diario a la hora STANDBY_HORA_BACKUP (01:00)
-- Respaldo RMAN nivel 0 (domingo) / nivel 1 (resto) y copia al standby.
-- JOB_STANDBY_PURGA_ARCHIVELOG     diario a la hora STANDBY_HORA_PURGA (03:00)
-- Purga archivelogs > STANDBY_PURGE_DIAS (3) ya aplicados en el standby.
-- JOB_STANDBY_MONITOREO            cada hora
-- Verifica que la sincronizacion este al dia y notifica al DBA.
--
-- Los tres primeros son jobs EXECUTABLE que llaman al orquestador
-- 02_Traslado_Archivelogs_10min_y_Ondemand.ps1 (Windows) o .sh (Linux),
-- pasandole las rutas, dias y SID como argumentos.
--
-- Ejecucion a peticion del academico (revision en vivo):
-- EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
-- EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;
-- EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;
-- EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;
--
-- REQUISITO UNICO DE INSTALACION (una vez, en la PC principal):
-- Los jobs EXECUTABLE corren en el sistema operativo con una credencial.
-- EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('usuario_so', 'clave_so');
-- En Windows el usuario debe pertenecer al grupo ORA_DBA y debe estar
-- iniciado el servicio OracleJobScheduler<SID>.
--
-- EJECUCION: como SYSDBA (lo invoca 00_Master_Instalacion_Avance2.sql).
-- =============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;
WHENEVER SQLERROR CONTINUE;

-- Conectar al PDB de trabajo si la sesion esta en CDB$ROOT
DECLARE
    v_pdb VARCHAR2(128);
BEGIN
    IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
        SELECT name INTO v_pdb
          FROM v$pdbs
         WHERE open_mode LIKE 'READ WRITE%'
           AND name <> 'PDB$SEED'
           AND ROWNUM = 1;
        EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
        DBMS_OUTPUT.PUT_LINE('[SESION] Conectado al PDB: ' || v_pdb);
    END IF;
END;
/

PROMPT ============================================================================
PROMPT 1. PRIVILEGIOS DE SISTEMA PARA JOBS EXTERNOS Y MONITOREO DEL STANDBY
PROMPT ============================================================================
DECLARE
    PROCEDURE otorgar(p_sql IN VARCHAR2) IS
    BEGIN
        EXECUTE IMMEDIATE p_sql;
        DBMS_OUTPUT.PUT_LINE('[OK] ' || p_sql);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[AVISO] ' || p_sql || ': ' || SQLERRM);
    END;
BEGIN
    otorgar('GRANT CREATE JOB TO CADENA_NEG');
    otorgar('GRANT CREATE EXTERNAL JOB TO CADENA_NEG');   -- jobs EXECUTABLE (ps1 / sh / rman)
    otorgar('GRANT CREATE CREDENTIAL TO CADENA_NEG');     -- DBMS_CREDENTIAL (usuario del SO)
    otorgar('GRANT SELECT ON SYS.V_$ARCHIVED_LOG TO CADENA_NEG');
    otorgar('GRANT SELECT ON SYS.V_$ARCHIVE_DEST_STATUS TO CADENA_NEG');
    otorgar('GRANT SELECT ON SYS.V_$DATABASE TO CADENA_NEG');
END;
/

-- La bitacora de monitoreo debe aceptar el tipo STANDBY (idempotente)
BEGIN
    EXECUTE IMMEDIATE 'ALTER TABLE CADENA_NEG.AUD_MONITOREO_BD DROP CONSTRAINT CK_MOBD_TIPO';
    EXECUTE IMMEDIATE 'ALTER TABLE CADENA_NEG.AUD_MONITOREO_BD ADD CONSTRAINT CK_MOBD_TIPO CHECK '
                   || '(TIPO_VERIF_MOBD IN (''TABLESPACE'',''OBJETO_INVALIDO'',''INDICE'',''SESION'',''CRECIMIENTO'',''STANDBY''))';
    DBMS_OUTPUT.PUT_LINE('[OK] AUD_MONITOREO_BD acepta verificaciones de tipo STANDBY.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[AVISO] CK_MOBD_TIPO: ' || SQLERRM);
END;
/

PROMPT ============================================================================
PROMPT 2. PARAMETROS DEL STANDBY EN SEG_PARAMETRO (Requerimiento 10)
PROMPT ============================================================================
-- Los valores del entorno (SO, SID, ORACLE_HOME, ruta de archivelogs) se detectan
-- del motor. Las rutas hacia la PC standby se crean con un valor de ejemplo y el
-- DBA las ajusta con PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO (no se sobrescriben
-- si ya existen).
DECLARE
    v_es_win   BOOLEAN := INSTR(UPPER(DBMS_UTILITY.PORT_STRING), 'WIN') > 0;
    v_sep      VARCHAR2(1);
    v_sid      VARCHAR2(30);
    v_home     VARCHAR2(500);
    v_fra      VARCHAR2(500);
    v_dbname   VARCHAR2(30);
    v_arch_dir VARCHAR2(500);

    -- Crea el parametro solo si no existe (respeta valores ajustados por el DBA)
    PROCEDURE crear_si_no_existe(p_codigo VARCHAR2, p_nombre VARCHAR2, p_desc VARCHAR2,
                                 p_texto VARCHAR2 DEFAULT NULL, p_num NUMBER DEFAULT NULL) IS
        v_existe NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_existe FROM CADENA_NEG.SEG_PARAMETRO WHERE CODIGO_PARA = p_codigo;
        IF v_existe = 0 THEN
            CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(p_codigo, 'STANDBY', p_nombre, p_desc, 'N', p_texto, p_num);
            DBMS_OUTPUT.PUT_LINE('[NUEVO] ' || RPAD(p_codigo, 30) || NVL(p_texto, TO_CHAR(p_num)));
        ELSE
            DBMS_OUTPUT.PUT_LINE('[EXISTE] ' || p_codigo || ' (se conserva su valor)');
        END IF;
    END;

    -- Valores detectados del entorno: siempre se actualizan
    PROCEDURE guardar(p_codigo VARCHAR2, p_nombre VARCHAR2, p_desc VARCHAR2, p_texto VARCHAR2) IS
    BEGIN
        CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(p_codigo, 'STANDBY', p_nombre, p_desc, 'N', p_texto, NULL);
        DBMS_OUTPUT.PUT_LINE('[DETECTADO] ' || RPAD(p_codigo, 26) || p_texto);
    END;
BEGIN
    v_sep := CASE WHEN v_es_win THEN '\' ELSE '/' END;

    SELECT instance_name INTO v_sid FROM v$instance;
    SELECT name INTO v_dbname FROM v$database;
    BEGIN
        SYS.DBMS_SYSTEM.GET_ENV('ORACLE_HOME', v_home);
    EXCEPTION
        WHEN OTHERS THEN v_home := NULL;
    END;
    BEGIN
        SELECT value INTO v_fra FROM v$parameter WHERE name = 'db_recovery_file_dest';
    EXCEPTION
        WHEN OTHERS THEN v_fra := NULL;
    END;
    -- Carpeta real donde Oracle esta dejando los archivelogs (la del ultimo generado)
    BEGIN
        SELECT SUBSTR(name, 1, INSTR(name, v_sep, -1) - 1) INTO v_arch_dir
          FROM (SELECT name FROM v$archived_log WHERE dest_id = 1 AND name IS NOT NULL ORDER BY completion_time DESC)
         WHERE ROWNUM = 1;
    EXCEPTION
        WHEN OTHERS THEN v_arch_dir := NULL;
    END;

    guardar('STANDBY_SO', 'Sistema operativo del servidor principal',
            'WINDOWS o LINUX: define si los jobs usan el orquestador .ps1 o .sh.',
            CASE WHEN v_es_win THEN 'WINDOWS' ELSE 'LINUX' END);
    guardar('STANDBY_ORACLE_SID', 'ORACLE_SID de la base principal',
            'Instancia a la que se conecta RMAN (rman target /) desde los jobs externos.', v_sid);
    IF v_home IS NOT NULL THEN
        guardar('STANDBY_ORACLE_HOME', 'ORACLE_HOME del servidor principal',
                'Ruta de instalacion de Oracle; los jobs externos no heredan variables de entorno.', v_home);
    END IF;

    crear_si_no_existe('STANDBY_RUTA_SCRIPTS', 'Carpeta de scripts 07_Standby_y_RMAN',
        'Ruta en la PC principal donde estan el orquestador .ps1/.sh y los scripts .rman.',
        CASE WHEN v_es_win THEN 'C:\app\oracle\proyecto\sql\07_Standby_y_RMAN'
             ELSE '/opt/oracle/proyecto/sql/07_Standby_y_RMAN' END);
    crear_si_no_existe('STANDBY_RUTA_ARCHIVE_ORIGEN', 'Carpeta de archivelogs en la principal',
        'Origen de los Archived Redo Logs que se trasladan al standby.',
        CASE WHEN v_fra IS NOT NULL THEN v_fra || v_sep || UPPER(v_dbname) || v_sep || 'ARCHIVELOG'
             ELSE NVL(v_arch_dir, CASE WHEN v_es_win THEN 'C:\app\oracle\recovery_area' ELSE '/opt/oracle/fast_recovery_area' END)
        END);
    crear_si_no_existe('STANDBY_RUTA_ARCHIVE_DESTINO', 'Carpeta de archivelogs en la PC standby',
        'Carpeta compartida (Windows UNC) o destino rsync (Linux) de la segunda computadora.',
        CASE WHEN v_es_win THEN '\\PC-STANDBY\standby_archive'
             ELSE 'oracle@pc-standby:/opt/oracle/standby_archive' END);
    crear_si_no_existe('STANDBY_RUTA_BACKUP_ORIGEN', 'Carpeta de respaldos RMAN en la principal',
        'Directorio donde RMAN escribe los respaldos diarios (FORMAT &1).',
        CASE WHEN v_es_win THEN 'C:\app\oracle\backups' ELSE '/opt/oracle/backups' END);
    crear_si_no_existe('STANDBY_RUTA_BACKUP_DESTINO', 'Carpeta de respaldos RMAN en la PC standby',
        'Destino en la segunda computadora al que se traslada el respaldo diario.',
        CASE WHEN v_es_win THEN '\\PC-STANDBY\standby_backups'
             ELSE 'oracle@pc-standby:/opt/oracle/standby_backups' END);
    crear_si_no_existe('STANDBY_HORA_BACKUP', 'Hora del respaldo RMAN diario',
        'Hora (0-23) en que se ejecuta JOB_RMAN_BACKUP_DIARIO.', NULL, 1);
    crear_si_no_existe('STANDBY_HORA_PURGA', 'Hora de la purga diaria de archivelogs',
        'Hora (0-23) en que se ejecuta JOB_STANDBY_PURGA_ARCHIVELOG.', NULL, 3);
    crear_si_no_existe('STANDBY_MAX_LAG_MIN', 'Atraso maximo tolerado del standby',
        'Minutos sin un traslado exitoso antes de notificar al DBA (JOB_STANDBY_MONITOREO).', NULL, 30);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[ERROR] Registrando parametros del standby: ' || SQLERRM);
END;
/

ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;

PROMPT ============================================================================
PROMPT 3. PAQUETE PKG_ADM_STANDBY
PROMPT ============================================================================
CREATE OR REPLACE PACKAGE CADENA_NEG.PKG_ADM_STANDBY IS
    -- -------------------------------------------------------------------------
    -- Administracion, sincronizacion y monitoreo del Standby y de RMAN.
    -- -------------------------------------------------------------------------

    -- Nombres de los jobs administrados por el paquete
    c_job_traslado CONSTANT VARCHAR2(128) := 'JOB_STANDBY_TRASLADO_ARCHIVELOG';
    c_job_backup   CONSTANT VARCHAR2(128) := 'JOB_RMAN_BACKUP_DIARIO';
    c_job_purga    CONSTANT VARCHAR2(128) := 'JOB_STANDBY_PURGA_ARCHIVELOG';
    c_job_monitor  CONSTANT VARCHAR2(128) := 'JOB_STANDBY_MONITOREO';
    c_credencial   CONSTANT VARCHAR2(128) := 'CRED_STANDBY_OS';

    -- Registra (cifrada por Oracle) la credencial del SO con la que corren los
    -- jobs externos y vuelve a crear los jobs ya habilitados.
    PROCEDURE PR_REGISTRAR_CREDENCIAL_OS (
        p_usuario_so IN VARCHAR2,
        p_clave_so   IN VARCHAR2,
        p_dominio    IN VARCHAR2 DEFAULT NULL
    );

    -- Crea o recrea los 4 jobs leyendo SEG_PARAMETRO. Llamarlo despues de
    -- cambiar un parametro (p.ej. STANDBY_SYNC_MIN) para aplicarlo en caliente.
    PROCEDURE PR_CONFIGURAR_JOBS;

    -- Ejecucion inmediata a peticion del academico (sincrona, muestra resultado)
    PROCEDURE PR_SINCRONIZAR_AHORA;
    PROCEDURE PR_RESPALDAR_AHORA;
    PROCEDURE PR_PURGAR_AHORA;

    -- Revisa atraso y fallos; registra en AUD_MONITOREO_BD y notifica al DBA
    PROCEDURE PR_VERIFICAR_SINCRONIZACION;

    -- Reporte por DBMS_OUTPUT del estado de jobs, ejecuciones y redo aplicado
    PROCEDURE PR_ESTADO_STANDBY;
END PKG_ADM_STANDBY;
/
SHOW ERRORS PACKAGE CADENA_NEG.PKG_ADM_STANDBY;

CREATE OR REPLACE PACKAGE BODY CADENA_NEG.PKG_ADM_STANDBY IS

    TYPE t_args IS TABLE OF VARCHAR2(1000);

    c_ps1 CONSTANT VARCHAR2(60) := '02_Traslado_Archivelogs_10min_y_Ondemand.ps1';
    c_sh  CONSTANT VARCHAR2(60) := '02_Traslado_Archivelogs_10min_y_Ondemand.sh';
    c_powershell CONSTANT VARCHAR2(100) := 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';

    -- -------------------------------------------------------------------------
    -- Utilidades privadas
    -- -------------------------------------------------------------------------
    FUNCTION fn_txt(p_codigo IN VARCHAR2, p_defecto IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 IS
        v_valor SEG_PARAMETRO.VALOR_TEXTO_PARA%TYPE;
    BEGIN
        SELECT VALOR_TEXTO_PARA INTO v_valor
          FROM SEG_PARAMETRO
         WHERE CODIGO_PARA = p_codigo AND ESTADO_PARA = 'A';
        RETURN NVL(v_valor, p_defecto);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN p_defecto;
    END fn_txt;

    FUNCTION fn_num(p_codigo IN VARCHAR2, p_defecto IN NUMBER) RETURN NUMBER IS
        v_valor SEG_PARAMETRO.VALOR_NUM_PARA%TYPE;
    BEGIN
        SELECT VALOR_NUM_PARA INTO v_valor
          FROM SEG_PARAMETRO
         WHERE CODIGO_PARA = p_codigo AND ESTADO_PARA = 'A';
        RETURN NVL(v_valor, p_defecto);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN p_defecto;
    END fn_num;

    FUNCTION fn_es_windows RETURN BOOLEAN IS
    BEGIN
        RETURN fn_txt('STANDBY_SO', 'LINUX') = 'WINDOWS';
    END fn_es_windows;

    FUNCTION fn_existe_credencial RETURN BOOLEAN IS
        v_cant NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cant FROM USER_CREDENTIALS WHERE CREDENTIAL_NAME = c_credencial;
        RETURN v_cant > 0;
    END fn_existe_credencial;

    FUNCTION fn_existe_job(p_job IN VARCHAR2) RETURN BOOLEAN IS
        v_cant NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_cant FROM USER_SCHEDULER_JOBS WHERE JOB_NAME = p_job;
        RETURN v_cant > 0;
    END fn_existe_job;

    PROCEDURE pr_eliminar_job(p_job IN VARCHAR2) IS
    BEGIN
        IF fn_existe_job(p_job) THEN
            DBMS_SCHEDULER.DROP_JOB(job_name => p_job, force => TRUE);
        END IF;
    END pr_eliminar_job;

    -- Argumentos del orquestador para el modo indicado, con valores de SEG_PARAMETRO
    FUNCTION fn_argumentos(p_modo IN VARCHAR2) RETURN t_args IS
        v_scripts VARCHAR2(500) := fn_txt('STANDBY_RUTA_SCRIPTS');
        v_args    t_args;
    BEGIN
        IF fn_es_windows THEN
            v_args := t_args('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                             '-File',               v_scripts || '\' || c_ps1,
                             '-Modo',               p_modo,
                             '-RutaOrigen',         fn_txt('STANDBY_RUTA_ARCHIVE_ORIGEN'),
                             '-RutaDestinoStandby', fn_txt('STANDBY_RUTA_ARCHIVE_DESTINO'),
                             '-RutaBackups',        fn_txt('STANDBY_RUTA_BACKUP_ORIGEN'),
                             '-RutaBackupsStandby', fn_txt('STANDBY_RUTA_BACKUP_DESTINO'),
                             '-DiasRetencion',      TO_CHAR(fn_num('STANDBY_PURGE_DIAS', 3)),
                             '-IntervaloMin',       TO_CHAR(fn_num('STANDBY_SYNC_MIN', 10)),
                             '-OracleSid',          fn_txt('STANDBY_ORACLE_SID', ' '));
            IF fn_txt('STANDBY_ORACLE_HOME') IS NOT NULL THEN
                v_args.EXTEND(2);
                v_args(v_args.COUNT - 1) := '-OracleHome';
                v_args(v_args.COUNT)     := fn_txt('STANDBY_ORACLE_HOME');
            END IF;
        ELSE
            v_args := t_args(v_scripts || '/' || c_sh,
                             LOWER(p_modo),
                             fn_txt('STANDBY_RUTA_ARCHIVE_ORIGEN'),
                             fn_txt('STANDBY_RUTA_ARCHIVE_DESTINO'),
                             fn_txt('STANDBY_RUTA_BACKUP_ORIGEN'),
                             fn_txt('STANDBY_RUTA_BACKUP_DESTINO'),
                             TO_CHAR(fn_num('STANDBY_PURGE_DIAS', 3)),
                             fn_txt('STANDBY_ORACLE_SID', ' '),
                             fn_txt('STANDBY_ORACLE_HOME', ' '),
                             TO_CHAR(fn_num('STANDBY_SYNC_MIN', 10)));
        END IF;
        RETURN v_args;
    END fn_argumentos;

    -- Crea un job EXECUTABLE que invoca al orquestador en el modo indicado
    PROCEDURE pr_crear_job_externo(p_job IN VARCHAR2, p_modo IN VARCHAR2,
                                   p_intervalo IN VARCHAR2, p_comentario IN VARCHAR2) IS
        v_args t_args := fn_argumentos(p_modo);
    BEGIN
        pr_eliminar_job(p_job);

        DBMS_SCHEDULER.CREATE_JOB(
            job_name            => p_job,
            job_type            => 'EXECUTABLE',
            job_action          => CASE WHEN fn_es_windows THEN c_powershell ELSE '/bin/bash' END,
            number_of_arguments => v_args.COUNT,
            start_date          => SYSTIMESTAMP,
            repeat_interval     => p_intervalo,
            enabled             => FALSE,
            auto_drop           => FALSE,
            comments            => p_comentario);

        FOR i IN 1 .. v_args.COUNT LOOP
            DBMS_SCHEDULER.SET_JOB_ARGUMENT_VALUE(job_name => p_job, argument_position => i,
                                                  argument_value => v_args(i));
        END LOOP;

        -- Guardar la salida del script en USER_SCHEDULER_JOB_RUN_DETAILS
        DBMS_SCHEDULER.SET_ATTRIBUTE(p_job, 'store_output', TRUE);

        IF fn_existe_credencial THEN
            DBMS_SCHEDULER.SET_ATTRIBUTE(p_job, 'credential_name', c_credencial);
            DBMS_SCHEDULER.ENABLE(p_job);
            DBMS_OUTPUT.PUT_LINE('[OK] ' || RPAD(p_job, 33) || 'HABILITADO  ' || p_intervalo);
        ELSE
            DBMS_OUTPUT.PUT_LINE('[PENDIENTE] ' || RPAD(p_job, 33) || 'creado DESHABILITADO: falta PR_REGISTRAR_CREDENCIAL_OS');
        END IF;
    END pr_crear_job_externo;

    -- Ejecuta un job en la sesion actual y muestra el resultado de la corrida
    PROCEDURE pr_ejecutar_job(p_job IN VARCHAR2, p_descripcion IN VARCHAR2) IS
        v_estado  USER_SCHEDULER_JOB_RUN_DETAILS.STATUS%TYPE;
        v_error   USER_SCHEDULER_JOB_RUN_DETAILS.ERROR#%TYPE;
        v_info    VARCHAR2(4000);
        v_salida  VARCHAR2(4000);
    BEGIN
        IF NOT fn_existe_job(p_job) THEN
            RAISE_APPLICATION_ERROR(-20131, 'El job ' || p_job || ' no existe. Ejecute PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS.');
        END IF;
        IF p_job <> c_job_monitor AND NOT fn_existe_credencial THEN
            RAISE_APPLICATION_ERROR(-20132, 'Falta la credencial del sistema operativo. Ejecute '
                || 'PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS(''usuario'', ''clave'').');
        END IF;

        DBMS_OUTPUT.PUT_LINE('>>> ' || p_descripcion || ' (' || p_job || ') ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
        DBMS_SCHEDULER.RUN_JOB(job_name => p_job, use_current_session => TRUE);

        SELECT status, error#, SUBSTR(additional_info, 1, 4000), SUBSTR(output, 1, 4000)
          INTO v_estado, v_error, v_info, v_salida
          FROM (SELECT status, error#, additional_info, output
                  FROM USER_SCHEDULER_JOB_RUN_DETAILS
                 WHERE job_name = p_job
                 ORDER BY log_date DESC)
         WHERE ROWNUM = 1;

        DBMS_OUTPUT.PUT_LINE('Resultado: ' || v_estado || CASE WHEN v_error <> 0 THEN ' (error ' || v_error || ')' END);
        IF v_salida IS NOT NULL THEN DBMS_OUTPUT.PUT_LINE(v_salida); END IF;
        IF v_estado <> 'SUCCEEDED' AND v_info IS NOT NULL THEN DBMS_OUTPUT.PUT_LINE(v_info); END IF;

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
            p_tabla       => 'USER_SCHEDULER_JOBS',
            p_llave       => p_job,
            p_operacion   => 'INSERT',
            p_modulo      => 'Standby',
            p_descripcion => 'Ejecucion bajo demanda: ' || p_descripcion || ' -> ' || v_estado);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('El job se ejecuto; aun no hay detalle en USER_SCHEDULER_JOB_RUN_DETAILS.');
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_STANDBY', 'PR_EJECUTAR_JOB:' || p_job, SQLCODE, SQLERRM);
            RAISE;
    END pr_ejecutar_job;

    -- -------------------------------------------------------------------------
    -- Procedimientos publicos
    -- -------------------------------------------------------------------------
    PROCEDURE PR_REGISTRAR_CREDENCIAL_OS (
        p_usuario_so IN VARCHAR2,
        p_clave_so   IN VARCHAR2,
        p_dominio    IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        IF p_usuario_so IS NULL OR p_clave_so IS NULL THEN
            RAISE_APPLICATION_ERROR(-20133, 'Usuario y clave del sistema operativo son obligatorios.');
        END IF;

        IF fn_existe_credencial THEN
            DBMS_CREDENTIAL.DROP_CREDENTIAL(credential_name => c_credencial, force => TRUE);
        END IF;

        -- Oracle guarda la clave cifrada en el diccionario; nunca queda en texto plano
        DBMS_CREDENTIAL.CREATE_CREDENTIAL(
            credential_name => c_credencial,
            username        => p_usuario_so,
            password        => p_clave_so,
            windows_domain  => p_dominio,
            comments        => 'Usuario del SO para los jobs externos del Standby y RMAN');

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
            p_tabla       => 'USER_CREDENTIALS',
            p_llave       => c_credencial,
            p_operacion   => 'UPDATE',
            p_modulo      => 'Standby',
            p_descripcion => 'Credencial del SO registrada para el usuario ' || p_usuario_so);

        DBMS_OUTPUT.PUT_LINE('[OK] Credencial ' || c_credencial || ' registrada para ' || p_usuario_so || '.');
        PR_CONFIGURAR_JOBS;
        -- La misma credencial habilita la descarga automatica mensual del padron del TSE
        PKG_PER_PADRON.PR_CONFIGURAR_JOBS_PADRON;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_STANDBY', 'PR_REGISTRAR_CREDENCIAL_OS', SQLCODE, SQLERRM);
            RAISE;
    END PR_REGISTRAR_CREDENCIAL_OS;

    PROCEDURE PR_CONFIGURAR_JOBS IS
        v_sync  NUMBER := fn_num('STANDBY_SYNC_MIN', 10);
        v_hbak  NUMBER := fn_num('STANDBY_HORA_BACKUP', 1);
        v_hpur  NUMBER := fn_num('STANDBY_HORA_PURGA', 3);
        v_dias  NUMBER := fn_num('STANDBY_PURGE_DIAS', 3);
    BEGIN
        IF fn_txt('STANDBY_RUTA_SCRIPTS') IS NULL THEN
            RAISE_APPLICATION_ERROR(-20134, 'Falta el parametro STANDBY_RUTA_SCRIPTS en SEG_PARAMETRO.');
        END IF;

        pr_crear_job_externo(c_job_traslado, 'Archivelogs',
            'FREQ=MINUTELY; INTERVAL=' || v_sync,
            'Traslado de archivelogs y respaldos RMAN al Standby cada ' || v_sync || ' min (STANDBY_SYNC_MIN)');

        pr_crear_job_externo(c_job_backup, 'Backup',
            'FREQ=DAILY; BYHOUR=' || v_hbak || '; BYMINUTE=0; BYSECOND=0',
            'Respaldo RMAN diario (nivel 0 domingo / nivel 1) trasladado al Standby (STANDBY_HORA_BACKUP)');

        pr_crear_job_externo(c_job_purga, 'Purga',
            'FREQ=DAILY; BYHOUR=' || v_hpur || '; BYMINUTE=0; BYSECOND=0',
            'Purga de archivelogs > ' || v_dias || ' dias ya aplicados en el Standby (STANDBY_PURGE_DIAS)');

        -- Monitoreo: PL/SQL puro, no necesita credencial del SO
        pr_eliminar_job(c_job_monitor);
        DBMS_SCHEDULER.CREATE_JOB(
            job_name        => c_job_monitor,
            job_type        => 'PLSQL_BLOCK',
            job_action      => 'BEGIN CADENA_NEG.PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION; END;',
            start_date      => SYSTIMESTAMP,
            repeat_interval => 'FREQ=HOURLY; INTERVAL=1',
            enabled         => TRUE,
            auto_drop       => FALSE,
            comments        => 'Monitoreo de sincronizacion del Standby con notificacion al DBA');
        DBMS_OUTPUT.PUT_LINE('[OK] ' || RPAD(c_job_monitor, 33) || 'HABILITADO  FREQ=HOURLY');

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
            p_tabla       => 'USER_SCHEDULER_JOBS',
            p_llave       => 'STANDBY',
            p_operacion   => 'UPDATE',
            p_modulo      => 'Standby',
            p_descripcion => 'Jobs del Standby configurados: traslado ' || v_sync || ' min, backup ' || v_hbak
                             || 'h, purga ' || v_hpur || 'h (' || v_dias || ' dias)');
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_STANDBY', 'PR_CONFIGURAR_JOBS', SQLCODE, SQLERRM);
            RAISE;
    END PR_CONFIGURAR_JOBS;

    PROCEDURE PR_SINCRONIZAR_AHORA IS
    BEGIN
        pr_ejecutar_job(c_job_traslado, 'Traslado inmediato de archivelogs y respaldos al Standby');
    END PR_SINCRONIZAR_AHORA;

    PROCEDURE PR_RESPALDAR_AHORA IS
    BEGIN
        pr_ejecutar_job(c_job_backup, 'Respaldo RMAN inmediato y traslado al Standby');
    END PR_RESPALDAR_AHORA;

    PROCEDURE PR_PURGAR_AHORA IS
    BEGIN
        pr_ejecutar_job(c_job_purga, 'Purga inmediata de archivelogs ya aplicados');
    END PR_PURGAR_AHORA;

    PROCEDURE PR_VERIFICAR_SINCRONIZACION IS
        v_max_lag     NUMBER := fn_num('STANDBY_MAX_LAG_MIN', 30);
        v_ult_ok      TIMESTAMP WITH TIME ZONE;
        v_min_atraso  NUMBER;
        v_fallos      NUMBER := 0;
        v_seq_prim    NUMBER;
        v_seq_stby    NUMBER;
        v_regs_dest2  NUMBER;
        v_gap         VARCHAR2(30);
        v_estado_dest VARCHAR2(30);
        v_error_dest  VARCHAR2(256);
        v_problemas   VARCHAR2(4000);
        v_cuerpo      CLOB;

        PROCEDURE registrar(p_objeto VARCHAR2, p_valor NUMBER, p_umbral NUMBER, p_inconsistente VARCHAR2, p_detalle VARCHAR2) IS
        BEGIN
            INSERT INTO AUD_MONITOREO_BD (ID_MONITOREO_BD, TIPO_VERIF_MOBD, NOMBRE_OBJETO_MOBD,
                                          VALOR_ACTUAL_MOBD, UMBRAL_MAX_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD)
            VALUES (SEQ_AUD_MONITOREO_BD.NEXTVAL, 'STANDBY', p_objeto, p_valor, p_umbral, p_inconsistente,
                    SUBSTR(p_detalle, 1, 500));
            IF p_inconsistente = 'S' THEN
                v_problemas := SUBSTR(v_problemas || '- ' || p_detalle || CHR(10), 1, 4000);
            END IF;
        END;
    BEGIN
        SAVEPOINT sp_verificar_standby;

        -- 1) Ultimo traslado exitoso
        SELECT MAX(log_date) INTO v_ult_ok
          FROM USER_SCHEDULER_JOB_RUN_DETAILS
         WHERE job_name = c_job_traslado AND status = 'SUCCEEDED';

        IF v_ult_ok IS NULL THEN
            registrar(c_job_traslado, NULL, v_max_lag, 'S', 'No existe ningun traslado exitoso hacia el Standby.');
        ELSE
            v_min_atraso := ROUND((CAST(SYSTIMESTAMP AS DATE) - CAST(v_ult_ok AS DATE)) * 1440);
            registrar(c_job_traslado, v_min_atraso, v_max_lag,
                      CASE WHEN v_min_atraso > v_max_lag THEN 'S' ELSE 'N' END,
                      'Ultimo traslado exitoso hace ' || v_min_atraso || ' min (maximo ' || v_max_lag || ').');
        END IF;

        -- 2) Fallos de los jobs del Standby en las ultimas 24 horas
        SELECT COUNT(*) INTO v_fallos
          FROM USER_SCHEDULER_JOB_RUN_DETAILS
         WHERE job_name IN (c_job_traslado, c_job_backup, c_job_purga)
           AND status = 'FAILED'   -- STOPPED (job reconfigurado mientras corria) no es un fallo
           AND log_date > SYSTIMESTAMP - INTERVAL '1' DAY;
        registrar('JOBS_STANDBY', v_fallos, 0, CASE WHEN v_fallos > 0 THEN 'S' ELSE 'N' END,
                  v_fallos || ' ejecucion(es) fallida(s) de traslado/backup/purga en 24 horas.');

        -- 3) Redo aplicado en el Standby (destino 2) frente al generado (SQL dinamico:
        --    las vistas V$ pueden no estar disponibles en todos los entornos)
        --    Con Data Guard (destino 2 activo) se compara lo generado con lo aplicado.
        --    En modo manual (XE/Free) la principal no ve el standby: el avance lo
        --    garantiza el traslado (punto 1) y se revisa en la PC standby.
        BEGIN
            -- Destino 2 configurado = Data Guard (Enterprise). V$ARCHIVE_DEST_STATUS da lo
            -- enviado y lo aplicado de la encarnacion actual (sirve tambien tras un failover).
            EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM v$archive_dest_status WHERE dest_id = 2 AND status <> ''INACTIVE'''
                         INTO v_regs_dest2;
            IF v_regs_dest2 > 0 THEN
                EXECUTE IMMEDIATE 'SELECT archived_seq# FROM v$archive_dest_status WHERE dest_id = 1' INTO v_seq_prim;
                EXECUTE IMMEDIATE 'SELECT status, error, applied_seq#, gap_status FROM v$archive_dest_status WHERE dest_id = 2'
                             INTO v_estado_dest, v_error_dest, v_seq_stby, v_gap;
                -- APPLIED_SEQ# visto desde la principal se actualiza con retraso y
                -- 'LOG SWITCH GAP' es pasajero: solo se alerta un hueco real de archivelogs.
                registrar('REDO_APLICADO', v_seq_prim - v_seq_stby, NULL,
                          CASE WHEN v_gap IN ('RESOLVABLE GAP', 'UNRESOLVABLE GAP', 'LOCALLY UNRESOLVABLE GAP')
                               THEN 'S' ELSE 'N' END,
                          'Data Guard: archivada ' || v_seq_prim || ', aplicada en Standby ' || v_seq_stby
                          || ', huecos: ' || NVL(v_gap, 'N/D') || '.');
                registrar('LOG_ARCHIVE_DEST_2', NULL, NULL,
                          CASE WHEN v_estado_dest IN ('VALID', 'DEFERRED') THEN 'N' ELSE 'S' END,
                          'Destino Standby: ' || v_estado_dest || NVL2(v_error_dest, ' - ' || v_error_dest, ''));
            ELSE
                registrar('REDO_APLICADO', NULL, NULL, 'N',
                          'Modo manual: el redo se aplica en la PC standby con 09_Aplicar_Archivelogs_Standby.rman.');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                registrar('V$ARCHIVED_LOG', NULL, NULL, 'N', 'No se pudo leer el estado del redo: ' || SQLERRM);
        END;

        COMMIT;

        IF v_problemas IS NOT NULL THEN
            v_cuerpo := 'ALERTA DE SINCRONIZACION DEL STANDBY' || CHR(10) || RPAD('=', 60, '=') || CHR(10)
                     || 'Fecha: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI') || CHR(10) || CHR(10)
                     || v_problemas || CHR(10)
                     || 'Revise: EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;';
            PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO(
                p_destinatarios => fn_txt('CORREO_DBA'),
                p_asunto        => 'Alerta DBA: inconsistencia en la sincronizacion del Standby',
                p_cuerpo        => v_cuerpo);
        ELSE
            DBMS_OUTPUT.PUT_LINE('[OK] Standby sincronizado: sin inconsistencias.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                ROLLBACK TO sp_verificar_standby;   -- el savepoint no existe si el fallo fue despues del COMMIT
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_STANDBY', 'PR_VERIFICAR_SINCRONIZACION', SQLCODE, SQLERRM);
            RAISE;
    END PR_VERIFICAR_SINCRONIZACION;

    PROCEDURE PR_ESTADO_STANDBY IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('==================== ESTADO DEL STANDBY ====================');
        DBMS_OUTPUT.PUT_LINE('Credencial SO      : ' || CASE WHEN fn_existe_credencial THEN 'REGISTRADA' ELSE 'FALTA (PR_REGISTRAR_CREDENCIAL_OS)' END);
        DBMS_OUTPUT.PUT_LINE('Traslado cada      : ' || fn_num('STANDBY_SYNC_MIN', 10) || ' min');
        DBMS_OUTPUT.PUT_LINE('Retencion purga    : ' || fn_num('STANDBY_PURGE_DIAS', 3) || ' dias');
        DBMS_OUTPUT.PUT_LINE('Destino archivelogs: ' || fn_txt('STANDBY_RUTA_ARCHIVE_DESTINO'));
        DBMS_OUTPUT.PUT_LINE('Destino respaldos  : ' || fn_txt('STANDBY_RUTA_BACKUP_DESTINO'));
        DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
        FOR j IN (SELECT job_name, enabled, state, failure_count,
                         TO_CHAR(last_start_date, 'YYYY-MM-DD HH24:MI') AS ultima,
                         TO_CHAR(next_run_date,  'YYYY-MM-DD HH24:MI') AS proxima
                    FROM USER_SCHEDULER_JOBS
                   WHERE job_name IN (c_job_traslado, c_job_backup, c_job_purga, c_job_monitor)
                   ORDER BY job_name) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(j.job_name, 33) || RPAD(j.state, 11) || 'fallos=' || RPAD(j.failure_count, 4)
                                 || 'ultima=' || NVL(j.ultima, '-') || '  proxima=' || NVL(j.proxima, '-'));
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('-------------------- Ultimas 10 ejecuciones ----------------');
        FOR r IN (SELECT * FROM (SELECT job_name, status, TO_CHAR(log_date, 'YYYY-MM-DD HH24:MI') AS fecha
                                   FROM USER_SCHEDULER_JOB_RUN_DETAILS
                                  WHERE job_name IN (c_job_traslado, c_job_backup, c_job_purga, c_job_monitor)
                                  ORDER BY log_date DESC)
                   WHERE ROWNUM <= 10) LOOP
            DBMS_OUTPUT.PUT_LINE(r.fecha || '  ' || RPAD(r.job_name, 33) || r.status);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('-------------------- Ultimas verificaciones ----------------');
        FOR m IN (SELECT * FROM (SELECT NOMBRE_OBJETO_MOBD, ES_INCONSISTENTE_MOBD, DETALLE_MOBD
                                   FROM AUD_MONITOREO_BD
                                  WHERE TIPO_VERIF_MOBD = 'STANDBY'
                                  ORDER BY FECHA_CREA_MOBD DESC)
                   WHERE ROWNUM <= 4) LOOP
            DBMS_OUTPUT.PUT_LINE(CASE m.ES_INCONSISTENTE_MOBD WHEN 'S' THEN '[ALERTA] ' ELSE '[OK]     ' END
                                 || RPAD(m.NOMBRE_OBJETO_MOBD, 22) || m.DETALLE_MOBD);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_STANDBY', 'PR_ESTADO_STANDBY', SQLCODE, SQLERRM);
            RAISE;
    END PR_ESTADO_STANDBY;

END PKG_ADM_STANDBY;
/
SHOW ERRORS PACKAGE BODY CADENA_NEG.PKG_ADM_STANDBY;

GRANT EXECUTE ON CADENA_NEG.PKG_ADM_STANDBY TO ROL_GERENTE;

PROMPT ============================================================================
PROMPT 4. CREACION DE LOS JOBS DEL STANDBY (DBMS_SCHEDULER)
PROMPT ============================================================================
BEGIN
    CADENA_NEG.PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS;
END;
/

SELECT job_name, job_type, enabled, state, repeat_interval
  FROM dba_scheduler_jobs
 WHERE owner = 'CADENA_NEG'
   AND job_name IN ('JOB_STANDBY_TRASLADO_ARCHIVELOG', 'JOB_RMAN_BACKUP_DIARIO',
                    'JOB_STANDBY_PURGA_ARCHIVELOG', 'JOB_STANDBY_MONITOREO')
 ORDER BY job_name;

PROMPT
PROMPT ----------------------------------------------------------------------------
PROMPT  SIGUIENTES PASOS (una sola vez en la PC principal):
PROMPT   1. Ajustar las rutas hacia la PC standby si es necesario:
PROMPT      EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_ARCHIVE_DESTINO','STANDBY',
PROMPT           'Carpeta de archivelogs en la PC standby','Destino de la segunda PC','N','\\192.168.1.20\standby_archive');
PROMPT   2. Registrar el usuario del sistema operativo (habilita los jobs):
PROMPT      EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('usuario_so','clave_so');
PROMPT   3. Probar a peticion:  EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
PROMPT                          EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;
PROMPT ----------------------------------------------------------------------------
