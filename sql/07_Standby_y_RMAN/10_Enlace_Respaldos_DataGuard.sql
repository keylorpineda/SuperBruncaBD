-- =============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c EE (Data Guard)
-- ARCHIVO:  sql/07_Standby_y_RMAN/10_Enlace_Respaldos_DataGuard.sql
-- CURSO:    Administracion de Bases de Datos
-- DESCRIPCION:
--   Configura el traslado AUTOMATICO del respaldo RMAN diario a la PC standby
--   por la misma red de Oracle (puerto 1521), sin carpetas compartidas ni USB:
--     - Directorios DIR_RESPALDOS (/opt/oracle/backups, en la principal) y
--       DIR_RESPALDOS_STBY (/opt/oracle/standby_backups, en la standby).
--       Se crean en la principal y llegan solos a la standby por el redo.
--     - Database link LNK_STANDBY hacia la standby (STANDBY_TNS).
--     - Parametros del standby en SEG_PARAMETRO para el modo Data Guard:
--         STANDBY_RUTA_ARCHIVE_DESTINO = dataguard  (los archivelogs los envia Data Guard)
--         STANDBY_RUTA_BACKUP_DESTINO  = oracle:LNK_STANDBY (respaldo por DBMS_FILE_TRANSFER)
--     - Vuelve a crear los jobs con esos valores (PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS).
--
--   Requisitos: Data Guard funcionando, la standby abierta en solo lectura
--   (READ ONLY WITH APPLY, opcion 5 del menu) y en la standby la carpeta
--   /opt/oracle/standby_backups creada y del usuario oracle.
--
-- EJECUCION (una sola vez, en la PRINCIPAL, como SYSDBA en CDB$ROOT):
--   sqlplus / as sysdba @10_Enlace_Respaldos_DataGuard.sql <clave_de_SYSTEM>
--   (&1 = clave de SYSTEM, la misma ORACLE_PWD con que se creo la principal)
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
WHENEVER SQLERROR CONTINUE

ALTER SESSION SET CONTAINER = CDB$ROOT;

PROMPT === 1. Directorios de respaldos (principal y standby) ===
CREATE OR REPLACE DIRECTORY DIR_RESPALDOS      AS '/opt/oracle/backups';
CREATE OR REPLACE DIRECTORY DIR_RESPALDOS_STBY AS '/opt/oracle/standby_backups';

PROMPT === 2. Database link hacia la standby ===
BEGIN
    EXECUTE IMMEDIATE 'DROP DATABASE LINK LNK_STANDBY';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/
CREATE DATABASE LINK LNK_STANDBY CONNECT TO SYSTEM IDENTIFIED BY "&1" USING 'STANDBY_TNS';

SELECT 'Enlace OK. La standby responde: ' || database_role || ' / ' || open_mode AS prueba
  FROM v$database@LNK_STANDBY;

PROMPT === 3. Parametros del standby para el modo Data Guard ===
DECLARE
    v_pdb  VARCHAR2(128);
    v_arch VARCHAR2(512);
BEGIN
    SELECT SUBSTR(name, 1, INSTR(name, '/', -1) - 1) INTO v_arch
      FROM (SELECT name FROM v$archived_log WHERE dest_id = 1 AND name IS NOT NULL ORDER BY completion_time DESC)
     WHERE ROWNUM = 1;
    SELECT name INTO v_pdb FROM v$pdbs WHERE open_mode = 'READ WRITE' AND name <> 'PDB$SEED' AND ROWNUM = 1;
    EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
    -- Dinamico: el bloque se compila en CDB$ROOT, donde CADENA_NEG no existe
    EXECUTE IMMEDIATE 'BEGIN
        CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(''STANDBY_RUTA_ARCHIVE_ORIGEN'', ''STANDBY'',
            ''Carpeta de archivelogs en la principal'', ''Origen de los Archived Redo Logs.'', ''N'', :1);
        CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(''STANDBY_RUTA_ARCHIVE_DESTINO'', ''STANDBY'',
            ''Destino de archivelogs'', ''dataguard = los envia Data Guard por LOG_ARCHIVE_DEST_2.'', ''N'', ''dataguard'');
        CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(''STANDBY_RUTA_BACKUP_ORIGEN'', ''STANDBY'',
            ''Carpeta de respaldos RMAN en la principal'', ''Debe coincidir con DIR_RESPALDOS.'', ''N'', ''/opt/oracle/backups'');
        CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(''STANDBY_RUTA_BACKUP_DESTINO'', ''STANDBY'',
            ''Destino del respaldo en la standby'', ''oracle:LNK_STANDBY = DBMS_FILE_TRANSFER por el database link.'', ''N'', ''oracle:LNK_STANDBY'');
        CADENA_NEG.PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS;
    END;' USING v_arch;
    DBMS_OUTPUT.PUT_LINE('[OK] Parametros del standby en modo Data Guard (archivelogs: ' || v_arch || ').');
END;
/

PROMPT
PROMPT Listo. Prueba inmediata desde el PDB:  EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;
