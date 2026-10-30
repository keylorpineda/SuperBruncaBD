/* =====================================================================
   PROYECTO: Sistema Integral de Cadena de Supermercados
   MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai
   ARCHIVO:  07_Standby_y_RMAN/06_Standby_Switchover_y_Failover.sql
   AUTOR:    Keylor Pineda Alvarez
   CURSO:    Administracion de Bases de Datos
   DESCRIPCION:
     Guia operativa y sentencias SQL para la ejecucion de Switchover
     (transicion planificada de roles sin perdida de datos) y Failover
     (activacion forzada por desastre del servidor principal).
   ===================================================================== */

ALTER SESSION SET CONTAINER = CDB$ROOT;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. MONITOREO DE BRECHA DE REDO LOGS (REDO GAP) ENTRE PRIMARIA Y STANDBY
PROMPT ============================================================================

-- En la Base de Datos Primaria:
SELECT thread#, MAX(sequence#) AS ultima_secuencia_primaria
  FROM v$archived_log
 WHERE status = 'A'
 GROUP BY thread#;

-- En la Base de Datos Standby:
SELECT thread#, MAX(sequence#) AS ultima_secuencia_recibida,
       MAX(sequence#) KEEP (DENSE_RANK LAST ORDER BY first_time) AS ultima_aplicada
  FROM v$archived_log
 WHERE applied = 'YES'
 GROUP BY thread#;

-- Consultar si existen gaps en la Standby
SELECT * FROM v$archive_gap;


PROMPT ============================================================================
PROMPT 2. PROCEDIMIENTO DE SWITCHOVER (CONMUTACION PLANIFICADA DE ROLES)
PROMPT ============================================================================

/*
   PASO A: EN EL SERVIDOR PRIMARIO (CADENA_PRIM)
   1. Verificar si la base de datos esta lista para el switchover:
      SELECT SWITCHOVER_STATUS FROM V$DATABASE;
      (Debe devolver 'TO STANDBY' o 'SESSIONS ACTIVE')

   2. Cambiar la Primaria a rol Standby:
      ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;

   3. Reiniciar la antigua primaria en modo MOUNT como Standby:
      SHUTDOWN IMMEDIATE;
      STARTUP MOUNT;

   PASO B: EN EL SERVIDOR STANDBY (CADENA_STBY)
   1. Verificar estado de la standby:
      SELECT SWITCHOVER_STATUS FROM V$DATABASE;
      (Debe devolver 'TO PRIMARY' o 'SWITCHOVER PENDING')

   2. Promover la Standby a Primaria:
      ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;

   3. Abrir la nueva base de datos primaria:
      ALTER DATABASE OPEN;

   PASO C: ACTIVAR APLICACION DE REDO EN LA NUEVA STANDBY
   1. En la antigua primaria (ahora Standby):
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
*/


PROMPT ============================================================================
PROMPT 3. PROCEDIMIENTO DE FAILOVER (ACTIVACION DE EMERGENCIA ANTE DESASTRE)
PROMPT ============================================================================

/*
   ESCENARIO: El servidor Primario sufrio destruccion fisica o falla irrecuperable.
   Se debe activar inmediatamente la base de datos Standby para asumir la produccion.

   PASO 1: EN EL SERVIDOR STANDBY
   1. Detener el proceso de recuperacion continua:
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;

   2. Aplicar todos los archivelogs pendientes que hayan sido transferidos:
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;

   3. Si faltan archivelogs y es un failover forzado con minima perdida:
      ALTER DATABASE ACTIVATE PHYSICAL STANDBY;

   PASO 2: ABRIR LA NUEVA BASE DE DATOS DE PRODUCCION
   ALTER DATABASE OPEN;

   PASO 3: RECONFIGURACION DE APLICACIONES
   Redirigir las cadenas de conexion TNS de la aplicacion hacia la IP del nodo Standby
   (o el Listener automatico mediante el servicio TNS transparente).
*/

PROMPT ============================================================================
PROMPT GUIAS DE SWITCHOVER Y FAILOVER DISPONIBLES EN EL SISTEMA
PROMPT ============================================================================
