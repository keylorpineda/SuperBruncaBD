/* =====================================================================
   PROYECTO: Sistema Integral de Cadena de Supermercados
   MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c EE (compatible con 26ai Free)
   ARCHIVO:  sql/07_Standby_y_RMAN/03_Purga_Archivelogs_3Dias.sql
   CURSO:    Administracion de Bases de Datos
   DESCRIPCION:
     Consulta administrativa y procedimiento de monitoreo para identificar
     y purgar registros de Archived Redo Logs con mas de 3 dias de antiguedad.
   ===================================================================== */

ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. CONSULTA DE ARCHIVED LOGS CANDIDATOS A PURGA (> 3 DIAS)
PROMPT ============================================================================

SELECT sequence#, name,
       ROUND(blocks * block_size / 1024 / 1024, 2) AS tamano_mb,
       TO_CHAR(first_time, 'YYYY-MM-DD HH24:MI:SS') AS inicio,
       TO_CHAR(completion_time, 'YYYY-MM-DD HH24:MI:SS') AS completado,
       archived, backup_count, deleted,
       ROUND(SYSDATE - completion_time, 1) AS dias_antiguedad
  FROM v$archived_log
 WHERE completion_time < (SYSDATE - 3)
   AND deleted = 'NO'
 ORDER BY completion_time ASC;

PROMPT ============================================================================
PROMPT 2. REPORTE DE USO DEL FAST RECOVERY AREA (FRA)
PROMPT ============================================================================

SELECT name,
       ROUND(space_limit / 1024 / 1024 / 1024, 2) AS limite_gb,
       ROUND(space_used  / 1024 / 1024 / 1024, 2) AS usado_gb,
       ROUND(space_reclaimable / 1024 / 1024 / 1024, 2) AS recuperable_gb,
       ROUND((space_used / space_limit) * 100, 2) AS pct_ocupado
  FROM v$recovery_file_dest;

SELECT file_type,
       percent_space_used,
       percent_space_reclaimable,
       number_of_files
  FROM v$recovery_area_usage;

PROMPT ============================================================================
PROMPT NOTA DE ADMINISTRACION:
PROMPT Para ejecutar la purga fisica de archivos en disco, utilice el script RMAN:
PROMPT   rman target / cmdfile=sql/07_Standby_y_RMAN/03_Purga_Archivelogs_3Dias.rman
PROMPT ============================================================================
