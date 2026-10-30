-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  05_Seguridad_Perfiles_Roles_Usuarios.sql
-- AUTOR:    Keylor Pineda Alvarez
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c / 23ai / 26ai Free
-- DESCRIPCION:
--   Implementacion integral del esquema de seguridad:
--   1. Perfiles de contrasena y recursos (PERFIL_CADENA_ADMIN, PERFIL_CADENA_OPER).
--   2. Roles protegidos por contrasena cifrada (ROL_GERENTE, ROL_JEFE_DEPARTAMENTO,
--      ROL_JEFE_PROVEEDURIA, ROL_DIGITADOR).
--   3. Matriz de minimos privilegios (distinguiendo Sistema vs Objeto) sin DBA/CONNECT/RESOURCE.
--   4. Creacion de usuarios, asignacion de tablespaces y cuotas.
--   5. Demostracion de activacion de roles protegidos con contrasena y pruebas
--      exhaustivas de autorizacion [OK] y rechazo controlado [RECHAZADO].
-- ============================================================================

WHENEVER SQLERROR CONTINUE;

-- Conectar dinamicamente al PDB o esquema de trabajo
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
        DBMS_OUTPUT.PUT_LINE('[SESION] Conectado exitosamente al PDB: ' || v_pdb);
    ELSE
        DBMS_OUTPUT.PUT_LINE('[SESION] Ya en PDB: ' || v_contenedor);
    END IF;
END;
/

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. LIMPIEZA PREVIA IDEMPOTENTE DE OBJETOS DE SEGURIDAD
PROMPT ============================================================================

BEGIN
    -- Usuarios
    FOR u IN (SELECT username FROM dba_users WHERE username IN ('USR_GERENTE', 'USR_JEFE_DEPTO', 'USR_JEFE_PROV', 'USR_DIGITADOR')) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
            DBMS_OUTPUT.PUT_LINE('[LIMPIEZA] Usuario eliminado: ' || u.username);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    -- Roles
    FOR r IN (SELECT role FROM dba_roles WHERE role IN ('ROL_GERENTE', 'ROL_JEFE_DEPARTAMENTO', 'ROL_JEFE_PROVEEDURIA', 'ROL_DIGITADOR')) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
            DBMS_OUTPUT.PUT_LINE('[LIMPIEZA] Rol eliminado: ' || r.role);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;

    -- Perfiles
    FOR p IN (SELECT DISTINCT profile FROM dba_profiles WHERE profile IN ('PERFIL_CADENA_ADMIN', 'PERFIL_CADENA_OPER')) LOOP
        BEGIN
            EXECUTE IMMEDIATE 'DROP PROFILE ' || p.profile || ' CASCADE';
            DBMS_OUTPUT.PUT_LINE('[LIMPIEZA] Perfil eliminado: ' || p.profile);
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
    END LOOP;
END;
/


PROMPT ============================================================================
PROMPT 2. CREACION DE PERFILES DE CONTRASEÑA Y POLÍTICAS DE ACCESO
PROMPT ============================================================================

-- Habilitar verificacion de recursos en el sistema
ALTER SYSTEM SET RESOURCE_LIMIT = TRUE;

-- 2.1 Perfil Administrativo / Gerencial
-- Aplicable a gerentes y jefaturas con altos requerimientos de seguridad
CREATE PROFILE PERFIL_CADENA_ADMIN LIMIT
    SESSIONS_PER_USER          3
    FAILED_LOGIN_ATTEMPTS      3
    PASSWORD_LOCK_TIME         1
    PASSWORD_LIFE_TIME         60
    PASSWORD_GRACE_TIME        7
    PASSWORD_REUSE_TIME        365
    PASSWORD_REUSE_MAX         5
    IDLE_TIME                  30;

-- 2.2 Perfil Operativo / Cajas y Almacen
-- Aplicable a digitadores, cajeros y personal de mostrador
CREATE PROFILE PERFIL_CADENA_OPER LIMIT
    SESSIONS_PER_USER          2
    FAILED_LOGIN_ATTEMPTS      3
    PASSWORD_LOCK_TIME         1
    PASSWORD_LIFE_TIME         45
    PASSWORD_GRACE_TIME        5
    PASSWORD_REUSE_TIME        180
    PASSWORD_REUSE_MAX         3
    IDLE_TIME                  15;

PROMPT [OK] Perfiles de seguridad PERFIL_CADENA_ADMIN y PERFIL_CADENA_OPER creados exitosamente.


PROMPT ============================================================================
PROMPT 3. CREACION DE ROLES PROTEGIDOS POR CONTRASEÑA
PROMPT ============================================================================

-- Principio de Seguridad: Cada rol esta blindado con una contrasena individual.
-- No pueden ser activados por defecto; el usuario debe autenticarse ante el rol.
CREATE ROLE ROL_GERENTE            IDENTIFIED BY "ClaveGerente2026*";
CREATE ROLE ROL_JEFE_DEPARTAMENTO  IDENTIFIED BY "ClaveJefeDepto2026*";
CREATE ROLE ROL_JEFE_PROVEEDURIA   IDENTIFIED BY "ClaveJefeProv2026*";
CREATE ROLE ROL_DIGITADOR          IDENTIFIED BY "ClaveDigitador2026*";

PROMPT [OK] Roles con clave creados: ROL_GERENTE, ROL_JEFE_DEPARTAMENTO, ROL_JEFE_PROVEEDURIA, ROL_DIGITADOR.

-- Registrar las contrasenas cifradas con AES-256 en la tabla de parametros del sistema
BEGIN
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_GERENTE',           'CLAVE_ROL_GERENTE',    'ClaveGerente2026*');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_JEFE_DEPARTAMENTO', 'CLAVE_ROL_JEFE_DEPTO', 'ClaveJefeDepto2026*');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_JEFE_PROVEEDURIA',  'CLAVE_ROL_JEFE_PROV',  'ClaveJefeProv2026*');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_DIGITADOR',         'CLAVE_ROL_DIGITADOR',  'ClaveDigitador2026*');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Claves de roles cifradas y almacenadas en SEG_PARAMETRO mediante DBMS_CRYPTO.');
END;
/


PROMPT ============================================================================
PROMPT 4. MATRIZ DE MÍNIMOS PRIVILEGIOS DE OBJETO POR ROL
PROMPT ============================================================================

-- 4.1 PRIVILEGIOS PARA ROL_GERENTE
-- Acceso de consulta gerencial general, vistas materializadas, monitoreo y auditoria
GRANT SELECT ON CADENA_NEG.MV_VENTAS_MENSUALES       TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.MV_INVENTARIO_CONSOLIDADO TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.VEN_FACTURA               TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.VEN_FACTURA_DET           TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.COM_FACTURA_COMPRA        TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.COM_FACTURA_COMPRA_DET    TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.INV_EXISTENCIA            TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.INV_MOVIMIENTO            TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.PER_CLIENTE               TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.PER_PROVEEDOR             TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.PRO_PRODUCTO              TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.PRO_PRECIO_HIST           TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.AUD_BITACORA              TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.AUD_REGISTRO_CAMBIO       TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.AUD_ERROR_SISTEMA         TO ROL_GERENTE;
GRANT SELECT ON CADENA_NEG.AUD_MONITOREO_BD          TO ROL_GERENTE;
GRANT EXECUTE ON CADENA_NEG.PKG_ADM_MONITOREO        TO ROL_GERENTE;
GRANT EXECUTE ON CADENA_NEG.PKG_PRM_MERCADEO         TO ROL_GERENTE;
GRANT EXECUTE ON CADENA_NEG.PKG_INV_GESTION          TO ROL_GERENTE;

-- 4.2 PRIVILEGIOS PARA ROL_JEFE_DEPARTAMENTO
-- Control operativo de ventas, compras, catalogo, mercadeo y ejecucion de cierre
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.VEN_FACTURA            TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.VEN_FACTURA_DET        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.VEN_CUENTA_COBRAR      TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_ABONO_COBRAR       TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA     TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA_DET TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_CUENTA_PAGAR       TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.COM_ABONO_PAGAR        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.INV_EXISTENCIA         TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.INV_MOVIMIENTO         TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRO_PRODUCTO           TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.PRO_PRECIO_HIST        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_DESCUENTO_DET      TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_ACCION_CLIENTE     TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_PROMOCION          TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PER_CLIENTE            TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PER_PROVEEDOR          TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.MV_VENTAS_MENSUALES    TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.MV_INVENTARIO_CONSOLIDADO TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_VEN_OPERACION                     TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_COM_OPERACION                     TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_INV_GESTION                       TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_PRM_MERCADEO                      TO ROL_JEFE_DEPARTAMENTO;

-- 4.3 PRIVILEGIOS PARA ROL_JEFE_PROVEEDURIA
-- Gestion integral de proveedores, recepcion de compras, cuentas por pagar y devoluciones
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PER_PROVEEDOR          TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA     TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA_DET TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_CUENTA_PAGAR       TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT         ON CADENA_NEG.COM_ABONO_PAGAR        TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_DEVOLUCION         TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_DEVOLUCION_DET     TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.INV_EXISTENCIA         TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.INV_BODEGA             TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.PRO_PRODUCTO           TO ROL_JEFE_PROVEEDURIA;
GRANT EXECUTE ON CADENA_NEG.PKG_COM_OPERACION                     TO ROL_JEFE_PROVEEDURIA;

-- 4.4 PRIVILEGIOS PARA ROL_DIGITADOR
-- Facturacion rapida en punto de venta y recepcion de pagos. SIN DELETE ni DDL.
GRANT SELECT                 ON CADENA_NEG.PRO_FAMILIA_PRODUCTO   TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.PRO_IMPUESTO           TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.VEN_TIPO_PAGO          TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.PRO_PRODUCTO           TO ROL_DIGITADOR;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PER_CLIENTE            TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_FACTURA            TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_FACTURA_DET        TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_PAGO               TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_ABONO_COBRAR       TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.VEN_CUENTA_COBRAR      TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.INV_EXISTENCIA         TO ROL_DIGITADOR;
GRANT EXECUTE ON CADENA_NEG.PKG_VEN_OPERACION                     TO ROL_DIGITADOR;

-- Conceder ejecucion del procedimiento seguro de activacion a PUBLIC para permitir login
GRANT EXECUTE ON CADENA_NEG.PRC_ACTIVAR_ROL_SESION TO PUBLIC;

PROMPT [OK] Matriz de minimos privilegios aplicada a los 4 roles sin DELETE ni DDL.


PROMPT ============================================================================
PROMPT 5. CREACION DE USUARIOS Y ASIGNACION DE PERFILES Y ROLES
PROMPT ============================================================================

-- Tabla de Tablespaces para asignacion
-- Se asigna TBS_DATOS como tablespace por defecto y TEMP como temporal
-- con cuota de 20 MB para evitar saturacion de disco.

-- 5.1 Usuario Gerente
CREATE USER USR_GERENTE IDENTIFIED BY "Gerente2026#Sec"
    DEFAULT TABLESPACE TBS_DATOS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_CADENA_ADMIN
    QUOTA 20M ON TBS_DATOS;

GRANT CREATE SESSION TO USR_GERENTE;
GRANT ROL_GERENTE TO USR_GERENTE;
ALTER USER USR_GERENTE DEFAULT ROLE NONE; -- Requiere activacion con contrasena

-- 5.2 Usuario Jefe de Departamento
CREATE USER USR_JEFE_DEPTO IDENTIFIED BY "JefeDepto2026#Sec"
    DEFAULT TABLESPACE TBS_DATOS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_CADENA_ADMIN
    QUOTA 20M ON TBS_DATOS;

GRANT CREATE SESSION TO USR_JEFE_DEPTO;
GRANT ROL_JEFE_DEPARTAMENTO TO USR_JEFE_DEPTO;
ALTER USER USR_JEFE_DEPTO DEFAULT ROLE NONE;

-- 5.3 Usuario Jefe de Proveeduria
CREATE USER USR_JEFE_PROV IDENTIFIED BY "JefeProv2026#Sec"
    DEFAULT TABLESPACE TBS_DATOS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_CADENA_OPER
    QUOTA 20M ON TBS_DATOS;

GRANT CREATE SESSION TO USR_JEFE_PROV;
GRANT ROL_JEFE_PROVEEDURIA TO USR_JEFE_PROV;
ALTER USER USR_JEFE_PROV DEFAULT ROLE NONE;

-- 5.4 Usuario Digitador
CREATE USER USR_DIGITADOR IDENTIFIED BY "Digitador2026#Sec"
    DEFAULT TABLESPACE TBS_DATOS
    TEMPORARY TABLESPACE TEMP
    PROFILE PERFIL_CADENA_OPER
    QUOTA 20M ON TBS_DATOS;

GRANT CREATE SESSION TO USR_DIGITADOR;
GRANT ROL_DIGITADOR TO USR_DIGITADOR;
ALTER USER USR_DIGITADOR DEFAULT ROLE NONE;

PROMPT [OK] Usuarios creados: USR_GERENTE, USR_JEFE_DEPTO, USR_JEFE_PROV, USR_DIGITADOR.
PROMPT [OK] Roles con DEFAULT ROLE NONE configurados para forzar autenticacion de roles.


PROMPT ============================================================================
PROMPT 6. VERIFICACION DE ESTRUCTURA DE SEGURIDAD (DICCIONARIO DE DATOS)
PROMPT ============================================================================

-- 6.1 Usuarios y perfiles asignados
SELECT username, account_status, default_tablespace, profile, created
  FROM dba_users
 WHERE username IN ('USR_GERENTE', 'USR_JEFE_DEPTO', 'USR_JEFE_PROV', 'USR_DIGITADOR')
 ORDER BY username;

-- 6.2 Roles asignados a los usuarios (ninguno debe ser DEFAULT)
SELECT grantee, granted_role, admin_option, default_role
  FROM dba_role_privs
 WHERE grantee IN ('USR_GERENTE', 'USR_JEFE_DEPTO', 'USR_JEFE_PROV', 'USR_DIGITADOR')
 ORDER BY grantee, granted_role;

-- 6.3 Privilegios de sistema (Unicamente CREATE SESSION bajo el principio de minimo privilegio)
SELECT grantee, privilege, admin_option
  FROM dba_sys_privs
 WHERE grantee IN ('USR_GERENTE', 'USR_JEFE_DEPTO', 'USR_JEFE_PROV', 'USR_DIGITADOR')
 ORDER BY grantee;

-- 6.4 Cuotas de tablespace
SELECT username, tablespace_name, ROUND(bytes/1024/1024, 2) AS usado_mb, ROUND(max_bytes/1024/1024, 2) AS max_mb
  FROM dba_ts_quotas
 WHERE username IN ('USR_GERENTE', 'USR_JEFE_DEPTO', 'USR_JEFE_PROV', 'USR_DIGITADOR')
 ORDER BY username;


PROMPT ============================================================================
PROMPT 7. DEMOSTRACION EN VIVO DE ACTIVACION DE ROLES Y PRUEBAS DE PERMISOS
PROMPT ============================================================================

-- 7.1 Demostracion con el usuario USR_DIGITADOR en su sesion real
-- (Demostracion de minimo privilegio: SELECT/INSERT autorizados tras activar rol, DELETE/DDL rechazados)
CONNECT USR_DIGITADOR/Digitador2026#Sec@FREEPDB1
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_total NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('>>> INICIANDO PRUEBAS DE SEGURIDAD PARA USUARIO: USR_DIGITADOR');
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

    -- Paso A: Intento de consulta SIN haber activado el rol (Rechazado)
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO' INTO v_total;
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] Consulta permitida sin activar rol: ' || v_total);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[OK RECHAZADO PREVIO] Sin activar rol no tiene acceso: ' || SQLERRM);
    END;

    -- Paso B: Activacion segura del rol mediante contrasena cifrada
    BEGIN
        CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] No se pudo activar rol: ' || SQLERRM);
    END;

    -- Paso C: Consulta autorizada sobre catalogo de productos tras activar rol
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO' INTO v_total;
        DBMS_OUTPUT.PUT_LINE('[OK AUTORIZADO] Consulta de catalogo exitosa. Total productos visibles: ' || v_total);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] Consulta autorizada fallo: ' || SQLERRM);
    END;

    -- Paso D: Intento de DELETE sobre productos (DEBE SER RECHAZADO: Minimo Privilegio)
    BEGIN
        EXECUTE IMMEDIATE 'DELETE FROM CADENA_NEG.PRO_PRODUCTO WHERE ROWNUM = 1';
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] Se permitio DELETE indebidamente.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[OK RECHAZADO] DELETE sobre PRO_PRODUCTO denegado correctamente: ' || SQLERRM);
    END;

    -- Paso E: Intento de DROP TABLE (DEBE SER RECHAZADO: Sin permisos DDL)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE CADENA_NEG.VEN_FACTURA';
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] Se permitio DROP TABLE indebidamente.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[OK RECHAZADO] DDL DROP TABLE denegado correctamente: ' || SQLERRM);
    END;
END;
/

-- 7.2 Demostracion con el usuario USR_GERENTE en su sesion real
-- (Acceso a vistas ejecutivas y bloqueo de modificacion de tablas operativas)
CONNECT USR_GERENTE/Gerente2026#Sec@FREEPDB1
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_total NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('>>> INICIANDO PRUEBAS DE SEGURIDAD PARA USUARIO: USR_GERENTE');
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

    -- Paso A: Activacion de rol gerencial mediante contrasena cifrada
    BEGIN
        CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_GERENTE');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] Activacion de rol fallo: ' || SQLERRM);
    END;

    -- Paso B: Consulta autorizada a Vista Materializada de Ventas
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CADENA_NEG.MV_VENTAS_MENSUALES' INTO v_total;
        DBMS_OUTPUT.PUT_LINE('[OK AUTORIZADO] Consulta a MV_VENTAS_MENSUALES exitosa. Filas: ' || v_total);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
    END;

    -- Paso C: Consulta autorizada a Vista Materializada de Inventario Consolidado
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM CADENA_NEG.MV_INVENTARIO_CONSOLIDADO' INTO v_total;
        DBMS_OUTPUT.PUT_LINE('[OK AUTORIZADO] Consulta a MV_INVENTARIO_CONSOLIDADO exitosa. Filas: ' || v_total);
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[ERROR] ' || SQLERRM);
    END;

    -- Paso D: Intento de INSERT directo en factura (Rechazado: El gerente tiene solo lectura y monitoreo)
    BEGIN
        EXECUTE IMMEDIATE 'INSERT INTO CADENA_NEG.VEN_FACTURA (ID_FACTURA_VENTA) VALUES (-999)';
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] Gerente inserto factura directamente.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[OK RECHAZADO] INSERT de venta denegado al Gerente (Solo lectura gerencial): ' || SQLERRM);
    END;
END;
/

-- Restablecer sesion administrativa para continuacion de scripts maestros
CONNECT / AS SYSDBA
ALTER SESSION SET CONTAINER = FREEPDB1;
ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;
SET SERVEROUTPUT ON SIZE UNLIMITED;

PROMPT ============================================================================
PROMPT FIN DE IMPLEMENTACION DE SEGURIDAD, PERFILES, ROLES Y USUARIOS — AVANCE 2
PROMPT ============================================================================
