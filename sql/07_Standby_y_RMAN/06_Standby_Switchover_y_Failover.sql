/* =====================================================================
   PROYECTO: Sistema Integral de Cadena de Supermercados
   MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c EE (compatible con 26ai Free)
   ARCHIVO:  sql/07_Standby_y_RMAN/06_Standby_Switchover_y_Failover.sql
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

-- Data Guard (21c Enterprise). Despues de un failover la numeracion de
-- archivelogs reinicia (nueva encarnacion): por eso se mira el destino 2.
-- En la principal: debe dar VALID / NO GAP
SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id = 2;
-- En la standby: transport lag y apply lag en +00 00:00:00
SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';
-- En la standby: MRP0 en APPLYING_LOG y procesos RFS recibiendo
SELECT process, status, sequence# FROM v$managed_standby;


PROMPT ============================================================================
PROMPT 2. PROCEDIMIENTO DE SWITCHOVER (CONMUTACION PLANIFICADA DE ROLES)
PROMPT ============================================================================

/*
   DATA GUARD (Oracle 21c Enterprise) - sintaxis 12c+ VERIFICADA en el proyecto
   Principal: DB_UNIQUE_NAME = CADENA       Standby: DB_UNIQUE_NAME = CADENA_STBY
   Procedimiento completo: docs/manuales/Manual_Administracion_Standby.md, seccion 11.

   PASO A: EN LA PRINCIPAL (CADENA)
   1. Comprobar que el cambio de roles es posible (no cambia nada):
      ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;
      (Si responde "Database altered." esta lista; si no, el error dice que falta)

   2. Cambiar los roles:
      ALTER DATABASE SWITCHOVER TO CADENA_STBY;
      La antigua principal se convierte en standby y se APAGA
      (en Docker el contenedor se detiene: docker start ora_principal).

   PASO B: EN LA NUEVA PRINCIPAL (CADENA_STBY)
      ALTER DATABASE OPEN;
      ALTER PLUGGABLE DATABASE ALL OPEN;

   PASO C: EN LA ANTIGUA PRINCIPAL (ahora standby)
      STARTUP MOUNT;          -- si el contenedor la abrio sola queda READ ONLY (tambien sirve)
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;

   PARA VOLVER A LOS ROLES ORIGINALES (desde la que sea principal en ese momento):
      ALTER DATABASE SWITCHOVER TO CADENA VERIFY;
      ALTER DATABASE SWITCHOVER TO CADENA;
      y los pasos B y C al reves.

   ALTERNATIVA ANTIGUA (sintaxis anterior a 12c, sigue funcionando):
      Principal: SELECT SWITCHOVER_STATUS FROM V$DATABASE;   -- 'TO STANDBY' o 'SESSIONS ACTIVE'
                 ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
                 SHUTDOWN IMMEDIATE;  STARTUP MOUNT;
      Standby:   SELECT SWITCHOVER_STATUS FROM V$DATABASE;   -- 'TO PRIMARY' o 'SESSIONS ACTIVE'
                 ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
                 ALTER DATABASE OPEN;
      Antigua principal: ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
*/


PROMPT ============================================================================
PROMPT 3. PROCEDIMIENTO DE FAILOVER (ACTIVACION DE EMERGENCIA ANTE DESASTRE)
PROMPT ============================================================================

/*
   ESCENARIO: El servidor Primario sufrio destruccion fisica o falla irrecuperable.
   Se debe activar inmediatamente la base de datos Standby para asumir la produccion.

   DATA GUARD (Oracle 21c Enterprise) - sintaxis 12c+ VERIFICADA en el proyecto
   (prueba: se inserto una venta en la principal y se hizo docker kill ora_principal)

   PASO 1: EN LA STANDBY (CADENA_STBY)
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
      ALTER DATABASE FAILOVER TO CADENA_STBY;      -- aplica todo el redo recibido y la activa

   PASO 2: ABRIR LA NUEVA BASE DE PRODUCCION
      ALTER DATABASE OPEN;
      ALTER PLUGGABLE DATABASE ALL OPEN;
      ALTER PLUGGABLE DATABASE ALL SAVE STATE;
      SELECT database_role, open_mode FROM v$database;   -- PRIMARY / READ WRITE
      Resultado verificado: la ultima venta estaba (0 perdida, aplicacion en tiempo real).

   PASO 3: RECONFIGURACION DE APLICACIONES
      Redirigir las cadenas de conexion TNS de la aplicacion hacia la IP del nodo Standby.

   PASO 4: RECUPERAR LA ANTIGUA PRINCIPAL COMO STANDBY (verificado)
      Respaldo nivel 0 en la nueva principal, copiarlo a la antigua, ahi SHUTDOWN ABORT,
      borrar /opt/oracle/oradata/CADENA/*, STARTUP NOMOUNT y modo crearstandby del
      orquestador (08_Creacion_Standby_Segunda_PC.rman). Luego un switchover devuelve
      los roles. Tras el failover la numeracion de archivelogs reinicia (nueva encarnacion).
      Docker (imagen enterprise:21.3.0.0 en Windows): SHUTDOWN ABORT detiene el contenedor;
      use docker stop + vaciar el volumen con un contenedor temporal + docker start
      (ver Manual de Administracion del Standby, nota de 11.6).
      Despues de crear el standby, en la PRINCIPAL actual: si
      SELECT status, error, gap_status FROM v$archive_dest_status WHERE dest_id = 2;
      muestra ERROR, ejecute ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=DEFER; luego
      =ENABLE; y ALTER SYSTEM ARCHIVE LOG CURRENT; (debe quedar VALID / NO GAP).

   ALTERNATIVA ANTIGUA (sintaxis anterior a 12c):
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
      ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
      ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY;
      -- o, si faltan archivelogs (failover forzado, con perdida):
      ALTER DATABASE ACTIVATE PHYSICAL STANDBY DATABASE;
      ALTER DATABASE OPEN;
*/

/* =====================================================================
   MODO MANUAL (Oracle XE / Free / Standard Edition, SIN Data Guard)
   El Standby se crea con 08_Creacion_Standby_Segunda_PC.rman y se
   sincroniza con 09_Aplicar_Archivelogs_Standby.rman (tarea programada).
   No existe MRP0 ni COMMIT TO SWITCHOVER: los roles se cambian asi:

   SINCRONIZACION (demostracion en vivo)
     PC principal : EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
     PC standby   : .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo AplicarStandby
                    SELECT MAX(sequence#) FROM v$archived_log WHERE applied = 'YES';
                    (debe coincidir con la ultima secuencia de la principal)

   SWITCHOVER MANUAL (planificado, sin perdida de datos)
     1. PC principal: detener la aplicacion y ejecutar
          ALTER SYSTEM ARCHIVE LOG CURRENT;
          EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
          SHUTDOWN IMMEDIATE;
     2. PC standby: aplicar el ultimo redo y activar
          .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo AplicarStandby
          ALTER DATABASE ACTIVATE STANDBY DATABASE;
          ALTER DATABASE OPEN;
          ALTER PLUGGABLE DATABASE ALL OPEN;
          ALTER PLUGGABLE DATABASE ALL SAVE STATE;
     3. La antigua principal se recrea como standby desde un respaldo de la
        nueva principal (mismos pasos 08 en sentido inverso).

   FAILOVER MANUAL (la PC principal se perdio)
     PC standby:
          .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo AplicarStandby
          ALTER DATABASE ACTIVATE STANDBY DATABASE;
          ALTER DATABASE OPEN;
          ALTER PLUGGABLE DATABASE ALL OPEN;
     Perdida maxima de datos = lo generado despues del ultimo traslado
     (<= STANDBY_SYNC_MIN minutos; ARCHIVE_LAG_TARGET limita el redo abierto a 5 min).
   ===================================================================== */

-- Verificacion de rol y estado (ejecutar en cualquiera de las dos PC)
SELECT name, db_unique_name, database_role, open_mode, log_mode FROM v$database;

PROMPT ============================================================================
PROMPT GUIAS DE SWITCHOVER Y FAILOVER DISPONIBLES EN EL SISTEMA
PROMPT ============================================================================
