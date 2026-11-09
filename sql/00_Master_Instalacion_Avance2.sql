-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  sql/00_Master_Instalacion_Avance2.sql
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c Enterprise Edition (compatible con 23ai / 26ai Free)
-- DESCRIPCION:
--   Script Maestro de Instalacion y Despliegue Automatizado.
--   Ejecuta en el orden correcto y de forma limpia los 6 scripts principales
--   del Avance #2 (con su suite de pruebas) y el paquete de jobs del Standby.
--
-- INSTRUCCION DE USO:
--   (desde la carpeta sql/ del repositorio, para que @@07_Standby_y_RMAN/... se resuelva)
--   cd sql
--   sqlplus system/<clave>@localhost:1521/<SERVICIO_DEL_PDB> @00_Master_Instalacion_Avance2.sql
--   (SERVICIO_DEL_PDB: PDBCADENA en Oracle 21c EE; FREEPDB1 en Oracle Free.
--    Verifiquelo con: SELECT name FROM v$pdbs;)
--   Al final imprime una VALIDACION: debe decir "FINALIZADO CON EXITO".
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

-- ----------------------------------------------------------------------------
-- PASO 7: JOBS DBMS_SCHEDULER DEL STANDBY Y RMAN (TRASLADO, BACKUP, PURGA, MONITOREO)
-- ----------------------------------------------------------------------------
PROMPT 
PROMPT >>> EJECUTANDO PASO 7: 07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql ...
PROMPT ----------------------------------------------------------------------------
@@07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql

-- Recompilar vistas y vistas materializadas invalidadas por los ALTER TABLE de los pasos previos
EXEC DBMS_UTILITY.COMPILE_SCHEMA('CADENA_NEG', FALSE);

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
PROMPT   VALIDACION FINAL DE LA INSTALACION (por nombre de objeto)
PROMPT ============================================================================
-- El instalador usa WHENEVER SQLERROR CONTINUE para poder re-ejecutarse sin
-- abortar, por lo que un fallo intermedio no detiene el proceso. Este bloque
-- confirma que lo esencial quedo instalado y avisa si algo fallo.
DECLARE
    v_fallas NUMBER := 0;
    v_n      NUMBER;
    PROCEDURE chequear(p_nombre IN VARCHAR2, p_ok IN BOOLEAN, p_detalle IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        IF NOT p_ok THEN v_fallas := v_fallas + 1; END IF;
        DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 44) || CASE WHEN p_ok THEN '[OK]' ELSE '[FALLA] ' || p_detalle END);
    END;
BEGIN
    SELECT COUNT(*) INTO v_n FROM all_objects WHERE owner = 'CADENA_NEG' AND status <> 'VALID';
    chequear('Objetos invalidos en CADENA_NEG: ' || v_n, v_n = 0, 'revise con SELECT object_name, object_type FROM all_objects WHERE owner=''CADENA_NEG'' AND status<>''VALID''');

    FOR p IN (SELECT column_value AS nombre FROM TABLE(SYS.ODCIVARCHAR2LIST(
                  'PKG_AUD_CONTROL', 'PKG_SEG_SEGURIDAD', 'PKG_ADM_NOTIFICACION', 'PKG_VEN_OPERACION',
                  'PKG_COM_OPERACION', 'PKG_INV_GESTION', 'PKG_PRM_MERCADEO', 'PKG_ADM_MONITOREO',
                  'PKG_PER_PADRON', 'PKG_ADM_STANDBY'))) LOOP
        SELECT COUNT(*) INTO v_n FROM all_objects
         WHERE owner = 'CADENA_NEG' AND object_name = p.nombre
           AND object_type IN ('PACKAGE', 'PACKAGE BODY') AND status = 'VALID';
        chequear('Paquete ' || p.nombre || ' (spec + body)', v_n = 2, 'falta o esta invalido');
    END LOOP;

    SELECT COUNT(*) INTO v_n FROM all_tables WHERE owner = 'CADENA_NEG';
    chequear('Tablas en el diccionario: ' || v_n || ' (minimo 65)', v_n >= 65, 'faltan tablas; revise los pasos 0 y 1');

    SELECT COUNT(*) INTO v_n FROM all_mviews WHERE owner = 'CADENA_NEG';
    chequear('Vistas materializadas: ' || v_n || ' (esperadas 2)', v_n = 2, 'revise el paso 1');

    SELECT COUNT(*) INTO v_n FROM all_triggers WHERE owner = 'CADENA_NEG';
    chequear('Triggers: ' || v_n || ' (minimo 21)', v_n >= 21, 'revise el paso 4');

    SELECT COUNT(*) INTO v_n FROM all_scheduler_jobs WHERE owner = 'CADENA_NEG';
    chequear('Jobs DBMS_SCHEDULER: ' || v_n || ' (minimo 11)', v_n >= 11, 'revise los pasos 6 y 7');

    SELECT COUNT(*) INTO v_n FROM dba_roles
     WHERE role IN ('ROL_GERENTE', 'ROL_JEFE_DEPARTAMENTO', 'ROL_JEFE_PROVEEDURIA', 'ROL_DIGITADOR');
    chequear('Roles de seguridad: ' || v_n || ' (esperados 4)', v_n = 4, 'revise el paso 5');

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '============================================================================');
    IF v_fallas = 0 THEN
        DBMS_OUTPUT.PUT_LINE('  DESPLIEGUE DEL AVANCE #2 FINALIZADO CON EXITO (validacion completa)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('  ATENCION: DESPLIEGUE TERMINADO CON ' || v_fallas || ' PUNTO(S) A REVISAR (ver [FALLA] arriba)');
        DBMS_OUTPUT.PUT_LINE('  Busque el primer ORA- / SP2- en la salida y corrijalo; el instalador se puede volver a ejecutar.');
    END IF;
    DBMS_OUTPUT.PUT_LINE('============================================================================');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('  No se pudo completar la validacion final: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('  (si el usuario no puede leer dba_roles, ejecute el instalador como SYSTEM o SYS)');
END;
/
PROMPT Fecha y hora de finalizacion:
SELECT TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS') AS fecha_fin FROM dual;
