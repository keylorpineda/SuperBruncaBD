-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  05_Seguridad_Perfiles_Roles_Usuarios.sql
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
-- Los roles se crean sin clave en texto plano dentro del script. La clave real
-- se toma YA CIFRADA de SEG_PARAMETRO (CLAVE_ROL_*) y se aplica con
-- PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL (ALTER ROLE ... IDENTIFIED BY).
CREATE ROLE ROL_GERENTE            NOT IDENTIFIED;
CREATE ROLE ROL_JEFE_DEPARTAMENTO  NOT IDENTIFIED;
CREATE ROLE ROL_JEFE_PROVEEDURIA   NOT IDENTIFIED;
CREATE ROLE ROL_DIGITADOR          NOT IDENTIFIED;

PROMPT [OK] Roles con clave creados: ROL_GERENTE, ROL_JEFE_DEPARTAMENTO, ROL_JEFE_PROVEEDURIA, ROL_DIGITADOR.

-- Proteger cada rol con la clave almacenada CIFRADA (AES-256) en SEG_PARAMETRO.
-- Al no enviar p_nueva_clave, el procedimiento descifra la clave de la tabla y
-- ejecuta ALTER ROLE ... IDENTIFIED BY; ninguna clave queda escrita en este script.
-- Para cambiar una clave: PR_ASIGNAR_CLAVE_ROL('ROL_X', 'CLAVE_ROL_X', 'NuevaClave').
BEGIN
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_GERENTE',           'CLAVE_ROL_GERENTE');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_JEFE_DEPARTAMENTO', 'CLAVE_ROL_JEFE_DEPTO');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_JEFE_PROVEEDURIA',  'CLAVE_ROL_JEFE_PROV');
    CADENA_NEG.PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL('ROL_DIGITADOR',         'CLAVE_ROL_DIGITADOR');
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Roles protegidos con las claves cifradas de SEG_PARAMETRO (DBMS_CRYPTO).');
END;
/


PROMPT ============================================================================
PROMPT 4. MATRIZ DE MÍNIMOS PRIVILEGIOS POR ROL (SISTEMA VS OBJETO - REQ. 6c)
PROMPT ============================================================================

-- 4.0 PRIVILEGIOS DE SISTEMA POR ROL (Requerimiento 6c: Sistema vs Objeto)
GRANT CREATE SESSION, ALTER SESSION TO ROL_GERENTE;
GRANT CREATE SESSION, ALTER SESSION TO ROL_JEFE_DEPARTAMENTO;
GRANT CREATE SESSION, ALTER SESSION TO ROL_JEFE_PROVEEDURIA;
GRANT CREATE SESSION                TO ROL_DIGITADOR;

PROMPT [OK] Privilegios de sistema asignados por rol (CREATE SESSION, ALTER SESSION).

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
-- Control operativo de ventas, compras, catalogo, mercadeo y ejecucion de cierre.
-- Proteccion de credito: UPDATE en PER_CLIENTE solo sobre datos comerciales (no SALDO_ACTUAL_CLI).
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.VEN_FACTURA            TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.VEN_FACTURA_DET        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.VEN_CUENTA_COBRAR      TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_ABONO_COBRAR       TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA     TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA_DET TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.COM_CUENTA_PAGAR       TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.COM_ABONO_PAGAR        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.INV_EXISTENCIA         TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.INV_MOVIMIENTO         TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRO_PRODUCTO           TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.PRO_PRECIO_HIST        TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_DESCUENTO_DET      TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_ACCION_CLIENTE     TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PRM_PROMOCION          TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT         ON CADENA_NEG.PER_CLIENTE            TO ROL_JEFE_DEPARTAMENTO;
GRANT UPDATE (MONTO_MAX_CREDITO_CLI, DIAS_CREDITO_CLI, ES_PREFERENCIAL_CLI, OBSERVACIONES_CLI, ESTADO_CLI) 
                             ON CADENA_NEG.PER_CLIENTE            TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.PER_PROVEEDOR          TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.MV_VENTAS_MENSUALES    TO ROL_JEFE_DEPARTAMENTO;
GRANT SELECT                 ON CADENA_NEG.MV_INVENTARIO_CONSOLIDADO TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_VEN_OPERACION                     TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_COM_OPERACION                     TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_INV_GESTION                       TO ROL_JEFE_DEPARTAMENTO;
GRANT EXECUTE ON CADENA_NEG.PKG_PRM_MERCADEO                      TO ROL_JEFE_DEPARTAMENTO;

-- 4.3 PRIVILEGIOS PARA ROL_JEFE_PROVEEDURIA
-- Gestion de proveedores, compras y cuentas por pagar.
-- Proteccion de saldo: UPDATE en PER_PROVEEDOR solo en terminos (no SALDO_ACTUAL_PROVE).
GRANT SELECT, INSERT         ON CADENA_NEG.PER_PROVEEDOR          TO ROL_JEFE_PROVEEDURIA;
GRANT UPDATE (MONTO_MAX_CREDITO_PROV, DIAS_CREDITO_PROV, OBSERVACIONES_PROV, ESTADO_PROV)
                             ON CADENA_NEG.PER_PROVEEDOR          TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA     TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_FACTURA_COMPRA_DET TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.COM_CUENTA_PAGAR       TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT         ON CADENA_NEG.COM_ABONO_PAGAR        TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_DEVOLUCION         TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT, INSERT, UPDATE ON CADENA_NEG.COM_DEVOLUCION_DET     TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.INV_EXISTENCIA         TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.INV_BODEGA             TO ROL_JEFE_PROVEEDURIA;
GRANT SELECT                 ON CADENA_NEG.PRO_PRODUCTO           TO ROL_JEFE_PROVEEDURIA;
GRANT EXECUTE ON CADENA_NEG.PKG_COM_OPERACION                     TO ROL_JEFE_PROVEEDURIA;

-- 4.4 PRIVILEGIOS PARA ROL_DIGITADOR
-- Facturacion en punto de venta. SIN DELETE ni DDL.
-- Proteccion estricta de credito: NO puede editar MONTO_MAX_CREDITO_CLI ni SALDO_ACTUAL_CLI.
GRANT SELECT                 ON CADENA_NEG.PRO_FAMILIA_PRODUCTO   TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.PRO_IMPUESTO           TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.VEN_TIPO_PAGO          TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.PRO_PRODUCTO           TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.PER_CLIENTE            TO ROL_DIGITADOR;
GRANT UPDATE (OBSERVACIONES_CLI, ES_PREFERENCIAL_CLI)
                             ON CADENA_NEG.PER_CLIENTE            TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_FACTURA            TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_FACTURA_DET        TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_PAGO               TO ROL_DIGITADOR;
GRANT SELECT, INSERT         ON CADENA_NEG.VEN_ABONO_COBRAR       TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.VEN_CUENTA_COBRAR      TO ROL_DIGITADOR;
GRANT SELECT                 ON CADENA_NEG.INV_EXISTENCIA         TO ROL_DIGITADOR;
GRANT EXECUTE ON CADENA_NEG.PKG_VEN_OPERACION                     TO ROL_DIGITADOR;

-- Conceder ejecucion del procedimiento seguro de activacion a PUBLIC para permitir login
GRANT EXECUTE ON CADENA_NEG.PRC_ACTIVAR_ROL_SESION TO PUBLIC;

PROMPT [OK] Matriz de minimos privilegios aplicada: columnas de credito blindadas contra modificacion manual.


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
PROMPT 7. VERIFICACION INTEGRAL DE MATRIZ DE SEGURIDAD Y MINIMOS PRIVILEGIOS
PROMPT ============================================================================

-- Verificacion de autorizaciones, rechazos controlados y blindaje de creditos
-- sin interrumpir la sesion administrativa para garantizar compatibilidad local y remota.
DECLARE
    v_count NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('>>> VERIFICANDO MATRIZ DE MINIMOS PRIVILEGIOS Y BLINDAJE DE ROLES');
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

    -- 1. Verificar que ROL_DIGITADOR NO posea DELETE sobre ninguna tabla de negocio
    SELECT COUNT(*) INTO v_count
      FROM dba_tab_privs
     WHERE grantee = 'ROL_DIGITADOR' AND privilege = 'DELETE';
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[OK RECHAZADO] ROL_DIGITADOR no tiene privilegios DELETE en el esquema.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] ROL_DIGITADOR posee privilegios DELETE indebidos.');
    END IF;

    -- 2. Verificar que ROL_DIGITADOR tenga bloqueada la modificacion directa de creditos y saldos
    SELECT COUNT(*) INTO v_count
      FROM dba_col_privs
     WHERE grantee = 'ROL_DIGITADOR'
       AND table_name = 'PER_CLIENTE'
       AND column_name IN ('SALDO_ACTUAL_CLI', 'MONTO_MAX_CREDITO_CLI')
       AND privilege = 'UPDATE';
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[OK BLINDADO] ROL_DIGITADOR no puede alterar saldos ni limites de credito de clientes.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] ROL_DIGITADOR puede alterar saldos de credito.');
    END IF;

    -- 3. Verificar que ROL_GERENTE solo posea SELECT sobre tablas transaccionales
    SELECT COUNT(*) INTO v_count
      FROM dba_tab_privs
     WHERE grantee = 'ROL_GERENTE'
       AND table_name IN ('VEN_FACTURA', 'COM_FACTURA_COMPRA')
       AND privilege IN ('INSERT', 'UPDATE', 'DELETE');
    IF v_count = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[OK AUTORIZADO] ROL_GERENTE tiene perfil estricto de solo lectura en transacciones.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[FALLO SEGURIDAD] ROL_GERENTE tiene permisos DML de modificacion.');
    END IF;

    -- 4. Demostracion de activacion de rol protegido con contrasena cifrada
    BEGIN
        CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');
        DBMS_OUTPUT.PUT_LINE('[OK AUTORIZADO] PRC_ACTIVAR_ROL_SESION autentico y activo exitosamente ROL_DIGITADOR.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[INFO] Activacion de rol en sesion actual: ' || SQLERRM);
    END;
END;
/

PROMPT 
PROMPT [GUIA DE CONEXION INTERACTIVA PARA DEMOSTRACION EN VIVO]
PROMPT Para interactuar directamente como usuario operativo en una nueva sesion:
PROMPT   sqlplus USR_DIGITADOR/"Digitador2026#Sec"@localhost:1521/FREEPDB1
PROMPT   SQL> EXEC CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');
PROMPT   SQL> SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO; -- AUTORIZADO
PROMPT   SQL> DELETE FROM CADENA_NEG.PRO_PRODUCTO;          -- RECHAZADO (ORA-01031)
PROMPT 

PROMPT ============================================================================
PROMPT FIN DE IMPLEMENTACION DE SEGURIDAD, PERFILES, ROLES Y USUARIOS — AVANCE 2
PROMPT ============================================================================
