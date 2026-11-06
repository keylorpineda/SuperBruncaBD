-- =====================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai
-- ARCHIVO:  sql/07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
-- CURSO:    Administracion de Bases de Datos
-- DESCRIPCION:
--   Prepara la base PRINCIPAL para alimentar al Standby:
--   redo logs de 50 MB multiplexados, cambio de log cada 5 minutos
--   (ARCHIVE_LAG_TARGET), FORCE LOGGING, destinos de archivado, standby
--   redo logs y STANDBY_FILE_MANAGEMENT. Es idempotente.
--
-- EJECUCION: como SYSDBA en CDB$ROOT, con la base en modo ARCHIVELOG.
-- =====================================================================

ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. DIAGNOSTICO INICIAL DE REDO LOGS Y ARCHIVELOG EN PRIMARIA
PROMPT ============================================================================

SELECT name, open_mode, log_mode, force_logging FROM v$database;

SELECT l.group#, l.thread#, l.sequence#, ROUND(l.bytes / 1024 / 1024, 2) AS tamano_mb,
       l.members, l.archived, l.status, f.member
  FROM v$log l
  JOIN v$logfile f ON l.group# = f.group#
 ORDER BY l.group#, f.member;

PROMPT ============================================================================
PROMPT 2. REDO LOGS DE 50 MB CON MULTIPLEXACION (GRUPOS 4, 5 Y 6)
PROMPT ============================================================================
-- Oracle no permite cambiar el tamano de un grupo existente. Procedimiento:
--   1. Crear grupos nuevos de 50 MB con 2 miembros (a y b).
--   2. Cambiar de log hasta que los grupos viejos queden INACTIVE.
--   3. Eliminar los grupos viejos cuyo tamano no sea 50 MB.
-- Los miembros se crean en la carpeta de los redo logs actuales. En produccion
-- el miembro "b" debe ir en otro disco (p.ej. /u02/oradata o D:\oradata).
DECLARE
    v_dir     VARCHAR2(512);
    v_sep     VARCHAR2(1);
    v_existe  NUMBER;
    v_estado  VARCHAR2(16);
BEGIN
    SELECT member INTO v_dir FROM v$logfile WHERE type = 'ONLINE' AND ROWNUM = 1;
    v_sep := CASE WHEN INSTR(v_dir, '\') > 0 THEN '\' ELSE '/' END;
    v_dir := SUBSTR(v_dir, 1, INSTR(v_dir, v_sep, -1));
    DBMS_OUTPUT.PUT_LINE('[CONFIG] Carpeta de redo logs: ' || v_dir);

    FOR g IN 4 .. 6 LOOP
        SELECT COUNT(*) INTO v_existe FROM v$log WHERE group# = g;
        IF v_existe = 0 THEN
            EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE GROUP ' || g || ' ('''
                || v_dir || 'redo0' || g || 'a.log'', ''' || v_dir || 'redo0' || g || 'b.log'') SIZE 50M REUSE';
            DBMS_OUTPUT.PUT_LINE('[OK] Grupo ' || g || ' creado: 50 MB, 2 miembros.');
        ELSE
            DBMS_OUTPUT.PUT_LINE('[EXISTE] Grupo ' || g);
        END IF;
    END LOOP;

    -- Rotar hasta que la base escriba en los grupos de 50 MB
    FOR i IN 1 .. 4 LOOP
        EXECUTE IMMEDIATE 'ALTER SYSTEM SWITCH LOGFILE';
    END LOOP;
    EXECUTE IMMEDIATE 'ALTER SYSTEM CHECKPOINT GLOBAL';

    -- Eliminar los grupos viejos de otro tamano que ya esten inactivos
    FOR r IN (SELECT group#, status FROM v$log WHERE bytes <> 50 * 1024 * 1024 ORDER BY group#) LOOP
        IF r.status = 'INACTIVE' THEN
            EXECUTE IMMEDIATE 'ALTER DATABASE DROP LOGFILE GROUP ' || r.group#;
            DBMS_OUTPUT.PUT_LINE('[OK] Grupo viejo ' || r.group# || ' eliminado (su archivo se borra a mano del disco).');
        ELSE
            DBMS_OUTPUT.PUT_LINE('[AVISO] Grupo viejo ' || r.group# || ' esta ' || r.status || '; vuelva a ejecutar el script para eliminarlo.');
        END IF;
    END LOOP;
END;
/

PROMPT ============================================================================
PROMPT 3. CAMBIO DE LOG CADA 5 MINUTOS (ARCHIVE_LAG_TARGET) Y FORCE LOGGING
PROMPT ============================================================================
-- Si en 5 minutos no se llenaron los 50 MB, Oracle cambia de log igual: se genera
-- un archivo de actualizacion cada 5 min o 50 MB sin intervencion del DBA.
-- Valores parametrizados en SEG_PARAMETRO: STANDBY_SWITCH_MIN y STANDBY_SWITCH_MB.
ALTER SYSTEM SET ARCHIVE_LAG_TARGET = 300 SCOPE = BOTH;
DECLARE
    v_force VARCHAR2(10);
BEGIN
    SELECT force_logging INTO v_force FROM v$database;
    IF v_force <> 'YES' THEN
        EXECUTE IMMEDIATE 'ALTER DATABASE FORCE LOGGING';
    END IF;
    DBMS_OUTPUT.PUT_LINE('[OK] ARCHIVE_LAG_TARGET = 300 s y FORCE LOGGING activos.');
END;
/

PROMPT ============================================================================
PROMPT 4. DESTINOS DE ARCHIVADO Y PARAMETROS DEL STANDBY
PROMPT ============================================================================
DECLARE
    v_fra      VARCHAR2(512);
    v_unico    VARCHAR2(30);
    v_banner   VARCHAR2(512);
BEGIN
    -- Destino 1 (local): la Fast Recovery Area si esta configurada; si no, se
    -- conserva el destino actual (en Docker/Free es $ORACLE_HOME/dbs).
    SELECT value INTO v_fra FROM v$parameter WHERE name = 'db_recovery_file_dest';
    IF v_fra IS NOT NULL THEN
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_DEST_1 = ''LOCATION=USE_DB_RECOVERY_FILE_DEST '
                       || 'VALID_FOR=(ALL_LOGFILES,ALL_ROLES)'' SCOPE = BOTH';
        DBMS_OUTPUT.PUT_LINE('[OK] LOG_ARCHIVE_DEST_1 en la Fast Recovery Area: ' || v_fra);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[INFO] Sin Fast Recovery Area: los archivelogs quedan en el destino por defecto.');
    END IF;

    -- Destino 2 (red hacia el Standby): solo Data Guard (Enterprise) con la entrada
    -- STANDBY_TNS en tnsnames.ora. En XE/Free/Standard se usa el MODO MANUAL
    -- (JOB_STANDBY_TRASLADO_ARCHIVELOG) y el destino 2 se deja VACIO: si existiera
    -- (aunque diferido), RMAN nunca purgaria porque la principal no puede saber
    -- que aplico el standby (RMAN-08120 "not yet applied by standby").
    SELECT db_unique_name INTO v_unico FROM v$database;
    SELECT banner INTO v_banner FROM v$version WHERE ROWNUM = 1;
    IF INSTR(UPPER(v_banner), 'ENTERPRISE') > 0 THEN
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_CONFIG = ''DG_CONFIG=(' || v_unico || ',CADENA_STBY)'' SCOPE = BOTH';
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 = ''SERVICE=STANDBY_TNS ASYNC NOAFFIRM '
                       || 'VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA_STBY'' SCOPE = BOTH';
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = ENABLE SCOPE = BOTH';
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET FAL_SERVER = ''STANDBY_TNS'' SCOPE = BOTH';
        DBMS_OUTPUT.PUT_LINE('[OK] Enterprise: Data Guard habilitado hacia CADENA_STBY.');
    ELSE
        EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 = '''' SCOPE = BOTH';
        DBMS_OUTPUT.PUT_LINE('[OK] Modo manual (sin Data Guard): traslado por JOB_STANDBY_TRASLADO_ARCHIVELOG.');
    END IF;

    -- El controlfile debe recordar los respaldos al menos tanto como la ventana
    -- de recuperacion de RMAN (14 dias), si no RMAN avisa RMAN-07553.
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET CONTROL_FILE_RECORD_KEEP_TIME = 21 SCOPE = BOTH';

    -- Replicar acciones: los datafiles nuevos se crean solos en el Standby
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT = AUTO SCOPE = BOTH';
    DBMS_OUTPUT.PUT_LINE('[OK] STANDBY_FILE_MANAGEMENT = AUTO');
END;
/

-- Standby redo logs de 50 MB (grupos actuales + 1): los usa el Standby al recibir
-- redo y la principal cuando cambia de rol en un switchover.
DECLARE
    v_dir     VARCHAR2(512);
    v_sep     VARCHAR2(1);
    v_existe  NUMBER;
BEGIN
    SELECT member INTO v_dir FROM v$logfile WHERE type = 'ONLINE' AND ROWNUM = 1;
    v_sep := CASE WHEN INSTR(v_dir, '\') > 0 THEN '\' ELSE '/' END;
    v_dir := SUBSTR(v_dir, 1, INSTR(v_dir, v_sep, -1));
    FOR g IN 11 .. 14 LOOP
        SELECT COUNT(*) INTO v_existe FROM v$standby_log WHERE group# = g;
        IF v_existe = 0 THEN
            EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP ' || g
                || ' (''' || v_dir || 'standby' || g || '.log'') SIZE 50M REUSE';
            DBMS_OUTPUT.PUT_LINE('[OK] Standby redo log grupo ' || g || ' (50 MB) creado.');
        END IF;
    END LOOP;
END;
/

-- Formato de nombres de archivelog (aplica al reiniciar la instancia)
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT = 'cadena_arch_%t_%s_%r.arc' SCOPE = SPFILE;

PROMPT ============================================================================
PROMPT 5. VERIFICACION FINAL
PROMPT ============================================================================
SELECT name, value FROM v$parameter
 WHERE name IN ('archive_lag_target', 'log_archive_dest_1', 'log_archive_dest_state_2',
                'standby_file_management', 'log_archive_config', 'log_archive_dest_2',
                'control_file_record_keep_time');

SELECT group#, thread#, sequence#, bytes / 1024 / 1024 AS tamano_mb, members, status
  FROM v$log ORDER BY group#;

SELECT group#, bytes / 1024 / 1024 AS tamano_mb, status FROM v$standby_log ORDER BY group#;

PROMPT ============================================================================
PROMPT CONFIGURACION DE LA PRINCIPAL FINALIZADA
PROMPT ============================================================================
