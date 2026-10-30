-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  00_Master_Instalacion_Avance2.sql
-- AUTOR:    Keylor Pineda Alvarez
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c / 23ai / 26ai Free
-- DESCRIPCION:
--   Script Maestro de Instalacion y Despliegue Automatizado.
--   Ejecuta en el orden correcto y de forma limpia los 6 scripts principales
--   del Avance #2, finalizando con la suite de pruebas integral.
--
-- INSTRUCCION DE USO:
--   sqlplus system/oracle@localhost:1521/FREEPDB1 @00_Master_Instalacion_Avance2.sql
-- ============================================================================

SET ECHO OFF;
SET FEEDBACK ON;
SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;
WHENEVER SQLERROR CONTINUE;

PROMPT ============================================================================
PROMPT   INICIANDO DESPLIEGUE INTEGRAL DEL AVANCE #2 — CADENA DE SUPERMERCADOS
PROMPT ============================================================================
PROMPT Fecha y hora de inicio: 
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS fecha_inicio FROM dual;

-- Conectar dinamicamente al PDB en caso de estar en CDB$ROOT
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
        DBMS_OUTPUT.PUT_LINE('[SESION MASTER] Conectado exitosamente al PDB: ' || v_pdb);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[SESION MASTER] Ya en PDB: ' || v_contenedor);
    END IF;
END;
/

-- ----------------------------------------------------------------------------
-- PASO 1: ESTRUCTURAS DDL, 11 TABLAS NUEVAS Y VISTAS MATERIALIZADAS
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 1: 01_Estructuras_Avance2.sql ...
PROMPT ----------------------------------------------------------------------------
@@01_Estructuras_Avance2.sql

-- ----------------------------------------------------------------------------
-- PASO 2: PAQUETES DE SEGURIDAD (AES-256), AUDITORIA Y NOTIFICACIONES
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 2: 02_Paquetes_Seguridad_Auditoria_Notificaciones.sql ...
PROMPT ----------------------------------------------------------------------------
@@02_Paquetes_Seguridad_Auditoria_Notificaciones.sql

-- ----------------------------------------------------------------------------
-- PASO 3: PAQUETES DE NEGOCIO (PADRON, INVENTARIOS, COMPRAS, VENTAS, MERCADEO, MONITOREO)
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 3: 03_Paquetes_Negocio_Monitoreo.sql ...
PROMPT ----------------------------------------------------------------------------
@@03_Paquetes_Negocio_Monitoreo.sql

-- ----------------------------------------------------------------------------
-- PASO 4: DISPARADORES DE REGLAS DE NEGOCIO Y AUDITORIA PROFUNDA
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 4: 04_Triggers_Negocio_y_Auditoria.sql ...
PROMPT ----------------------------------------------------------------------------
@@04_Triggers_Negocio_y_Auditoria.sql

-- ----------------------------------------------------------------------------
-- PASO 5: SEGURIDAD, PERFILES, ROLES PROTEGIDOS Y USUARIOS OPERATIVOS
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 5: 05_Seguridad_Perfiles_Roles_Usuarios.sql ...
PROMPT ----------------------------------------------------------------------------
@@05_Seguridad_Perfiles_Roles_Usuarios.sql

-- ----------------------------------------------------------------------------
-- PASO 6: AUTOMATIZACION CON DBMS_SCHEDULER, OPTIMIZACION SQL Y BATERIA DE PRUEBAS
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 6: 06_Scheduler_Optimizacion_y_Pruebas.sql ...
PROMPT ----------------------------------------------------------------------------
@@06_Scheduler_Optimizacion_y_Pruebas.sql

PROMPT 
PROMPT ============================================================================
PROMPT   RESUMEN FINAL DE OBJETOS CREADOS EN EL ESQUEMA CADENA_NEG
PROMPT ============================================================================

SELECT object_type, status, COUNT(*) AS cantidad
  FROM all_objects
 WHERE owner = 'CADENA_NEG'
 GROUP BY object_type, status
 ORDER BY object_type, status;

PROMPT 
PROMPT ============================================================================
PROMPT   DESPLIEGUE DEL AVANCE #2 FINALIZADO CON EXITO
PROMPT ============================================================================
PROMPT Fecha y hora de finalizacion:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS fecha_fin FROM dual;
