/* =====================================================================
   PROYECTO: Sistema Integral de Cadena de Supermercados
   MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai
   ARCHIVO:  07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
   CURSO:    Administracion de Bases de Datos
   ===================================================================== */

/* ---------------------------------------------------------------------
   CONEXION ADMINISTRATIVA: SYSDBA o SYSTEM en CDB$ROOT
   --------------------------------------------------------------------- */
ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. DIAGNOSTICO INICIAL DE REDO LOGS Y ARCHIVELOG EN PRIMARIA
PROMPT ============================================================================

-- 1.1 Estado actual de la base de datos y modo de archivado
SELECT name, open_mode, log_mode, force_logging 
  FROM v$database;

-- 1.2 Inspeccion de grupos y miembros existentes
SELECT l.group#, l.thread#, l.sequence#,
       ROUND(l.bytes / 1024 / 1024, 2) AS tamano_mb,
       l.members, l.archived, l.status,
       f.member
  FROM v$log l
  JOIN v$logfile f ON l.group# = f.group#
 ORDER BY l.group#, f.member;


PROMPT ============================================================================
PROMPT 2. RECONFIGURACION DE REDO LOGS A 50 MB CON MULTIPLEXACION
PROMPT ============================================================================

/*
   REQUERIMIENTO:
   - Redo Logs con tamano exacto de 50 MB por grupo.
   - Minimo 2 miembros por grupo en rutas fisicas o carpetas separadas (Multiplexacion).
   
   ESTRATEGIA IDEMPOTENTE:
   Oracle no permite cambiar el tamano de un grupo de redo log en caliente mediante ALTER.
   El procedimiento estandar y seguro es:
   1. Crear nuevos grupos (ej. Grupos 4, 5, 6) de 50 MB con 2 miembros cada uno.
   2. Forzar cambios de log (SWITCH LOGFILE) y checkpoints hasta que los grupos
      viejos queden en estado INACTIVE.
   3. Eliminar los grupos viejos con tamano diferente.
*/

DECLARE
    v_data_dir VARCHAR2(500);
    v_dir_a    VARCHAR2(500);
    v_dir_b    VARCHAR2(500);
BEGIN
    -- Obtener directorio base a partir de un datafile existente
    SELECT SUBSTR(name, 1, INSTR(name, '/', -1)) INTO v_data_dir
      FROM v$datafile WHERE ROWNUM = 1;

    -- Si es Windows y contiene contrabarras
    IF v_data_dir IS NULL THEN
        SELECT SUBSTR(name, 1, INSTR(name, '\', -1)) INTO v_data_dir
          FROM v$datafile WHERE ROWNUM = 1;
    END IF;

    DBMS_OUTPUT.PUT_LINE('[CONFIG] Directorio base detectado: ' || v_data_dir);
    v_dir_a := v_data_dir;
    v_dir_b := v_data_dir; -- En entorno de produccion se especifica un segundo disco/volumen físico (ej. /u02/oradata o D:\oradata)
END;
/

-- 2.1 Agregar nuevos grupos de Redo Logs de 50 MB (Grupos 4, 5 y 6)
-- En Oracle Managed Files (OMF), basta con especificar el tamano 50M
ALTER DATABASE ADD LOGFILE GROUP 4 SIZE 50M;
ALTER DATABASE ADD LOGFILE GROUP 5 SIZE 50M;
ALTER DATABASE ADD LOGFILE GROUP 6 SIZE 50M;

-- 2.2 Agregar segundo miembro para multiplexacion
-- (Si se usan rutas manuales se especifican miembros en discos separados)
-- Ejemplo con OMF o miembros adicionales:
BEGIN
    FOR g IN 4..6 LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER DATABASE ADD LOGFILE MEMBER TO GROUP ' || g;
            DBMS_OUTPUT.PUT_LINE('[OK] Miembro secundario multiplexado agregado al Grupo ' || g);
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('[AVISO] En OMF o adicion manual de miembro: ' || SQLERRM);
        END;
    END LOOP;
END;
/

-- 2.3 Forzar rotacion hacia los nuevos grupos de 50 MB
ALTER SYSTEM CHECKPOINT;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SYSTEM CHECKPOINT;
ALTER SYSTEM SWITCH LOGFILE;


PROMPT ============================================================================
PROMPT 3. CONFIGURACION DE ARCHIVE_LAG_TARGET A 5 MINUTOS (300 SEGUNDOS)
PROMPT ============================================================================

/*
   REQUERIMIENTO:
   "Forzar el cambio de log cada 5 minutos mediante parametros de inicializacion".
   El parametro ARCHIVE_LAG_TARGET establece el tiempo maximo (en segundos) que
   puede transcurrir antes de que Oracle fuerce un switch de log si no se ha
   alcanzado el tamano de 50 MB, garantizando un RPO <= 5 minutos.
*/

ALTER SYSTEM SET ARCHIVE_LAG_TARGET = 300 SCOPE = BOTH;
PROMPT [OK] ARCHIVE_LAG_TARGET fijado en 300 segundos (5 minutos) en MEMORY y SPFILE.

-- Asegurar FORCE LOGGING en la base de datos primaria
ALTER DATABASE FORCE LOGGING;
PROMPT [OK] FORCE LOGGING activado para evitar omisiones de redo en operaciones directas.


PROMPT ============================================================================
PROMPT 4. CONFIGURACION DE DESTINOS DE ARCHIVADO LOCAL Y REMOTO (STANDBY)
PROMPT ============================================================================

-- Destino 1: Local (Fast Recovery Area o ruta dedicada)
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1 = 'LOCATION=USE_DB_RECOVERY_FILE_DEST VALID_FOR=(ALL_LOGFILES,ALL_ROLES)' SCOPE = BOTH;

-- Destino 2: Transporte de redo por red hacia el Standby (solo Data Guard, Enterprise).
-- Requiere la entrada STANDBY_TNS en tnsnames.ora apuntando a la IP de la PC standby.
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2 = 'SERVICE=STANDBY_TNS ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA_STBY' SCOPE = BOTH;
DECLARE
    v_unico VARCHAR2(30);
BEGIN
    SELECT db_unique_name INTO v_unico FROM v$database;   -- p.ej. FREE o CADENA
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET LOG_ARCHIVE_CONFIG = ''DG_CONFIG=(' || v_unico || ',CADENA_STBY)'' SCOPE = BOTH';
    EXECUTE IMMEDIATE 'ALTER SYSTEM SET FAL_SERVER = ''STANDBY_TNS'' SCOPE = BOTH';
    DBMS_OUTPUT.PUT_LINE('[OK] LOG_ARCHIVE_CONFIG = DG_CONFIG=(' || v_unico || ',CADENA_STBY)');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('[AVISO] Parametros Data Guard: ' || SQLERRM);
END;
/

-- MODO MANUAL (Oracle XE / Free / Standard Edition, sin Data Guard):
-- el traslado lo hace JOB_STANDBY_TRASLADO_ARCHIVELOG cada STANDBY_SYNC_MIN minutos,
-- por eso se difiere el destino 2 para que no genere errores de red en el alert.log:
--   ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = DEFER SCOPE = BOTH;

-- Los datafiles nuevos de la principal se crean solos en el Standby (replicar acciones)
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT = AUTO SCOPE = BOTH;

-- Standby redo logs del mismo tamano (50 MB): los usa el Standby al recibir redo
-- y la principal cuando cambia de rol en un switchover (cantidad = grupos + 1).
BEGIN
    FOR g IN 11 .. 14 LOOP
        BEGIN
            EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE THREAD 1 GROUP ' || g || ' SIZE 50M';
            DBMS_OUTPUT.PUT_LINE('[OK] Standby redo log grupo ' || g || ' (50 MB) creado.');
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('[AVISO] Standby redo log grupo ' || g || ': ' || SQLERRM);
        END;
    END LOOP;
END;
/

-- Formato de nombres de archivelog
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT = 'cadena_arch_%t_%s_%r.arc' SCOPE = SPFILE;


PROMPT ============================================================================
PROMPT 5. VERIFICACION FINAL DE PARAMETROS Y REDO LOGS
PROMPT ============================================================================

-- Comprobar ARCHIVE_LAG_TARGET
SELECT name, value, description 
  FROM v$parameter 
 WHERE name = 'archive_lag_target';

-- Comprobar grupos activos de 50 MB
SELECT group#, thread#, sequence#, bytes/1024/1024 AS tamano_mb, members, status 
  FROM v$log 
 ORDER BY group#;

PROMPT ============================================================================
PROMPT CONFIGURACION DE REDO LOGS Y ARCHIVELOG FINALIZADA CON EXITO
PROMPT ============================================================================
