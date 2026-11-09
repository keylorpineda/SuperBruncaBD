--------------------------------------------------------------------------------
-- UNIVERSIDAD NACIONAL - SEDE REGIONAL BRUNCA
-- ADMINISTRACION DE BASES DE DATOS - II CICLO 2026
-- PROYECTO: BASE DE DATOS PARA UNA CADENA DE NEGOCIOS
-- ENTREGABLE #2 - ARCHIVO 02: PAQUETES DE AUDITORIA, SEGURIDAD (DBMS_CRYPTO)
--                             Y NOTIFICACIONES POR CORREO (UTL_SMTP)
--
-- REQUISITO PREVIO: Haber ejecutado 01_Estructuras_Avance2.sql
-- ORDEN DE EJECUCION: 01 -> 02 -> 03 -> 04 -> 05 -> 06
--------------------------------------------------------------------------------

SET SERVEROUTPUT ON SIZE UNLIMITED
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE

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
    END IF;
END;
/

-- Configuracion de ACL de red en Oracle para envio directo por UTL_SMTP sin VPN
BEGIN
    DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
        host => '*',
        ace  => xs$ace_type(
            privilege_list => xs$name_list('connect', 'resolve'),
            principal_name => 'CADENA_NEG',
            principal_type => xs_acl.ptype_db
        )
    );
    DBMS_OUTPUT.PUT_LINE('ACL de red para UTL_SMTP configurada para CADENA_NEG.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Aviso ACL UTL_SMTP: ' || SQLERRM);
END;
/

ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;

--------------------------------------------------------------------------------
-- 1. PAQUETE: PKG_AUD_CONTROL
--    Manejo autonomo de bitacoras de operaciones, cambios y errores PL/SQL.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_AUD_CONTROL IS

    -- Registra un error de ejecucion PL/SQL en AUD_ERROR_SISTEMA (transaccion autonoma)
    PROCEDURE PR_REGISTRAR_ERROR (
        p_paquete      IN VARCHAR2,
        p_subprograma  IN VARCHAR2,
        p_codigo_sql   IN NUMBER,
        p_mensaje      IN VARCHAR2,
        p_pila         IN VARCHAR2 DEFAULT NULL
    );

    -- Registra una operacion general o critica en AUD_BITACORA (transaccion autonoma)
    PROCEDURE PR_REGISTRAR_OPERACION (
        p_tabla        IN VARCHAR2,
        p_llave        IN VARCHAR2,
        p_operacion    IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_descripcion  IN VARCHAR2,
        p_id_usuario   IN NUMBER DEFAULT NULL,
        p_id_sucursal  IN NUMBER DEFAULT NULL
    );

    -- Registra el detalle de valor anterior y nuevo en AUD_REGISTRO_CAMBIO
    PROCEDURE PR_REGISTRAR_CAMBIO (
        p_tabla        IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_operacion    IN VARCHAR2,
        p_llave        IN VARCHAR2,
        p_campo        IN VARCHAR2,
        p_valor_ant    IN VARCHAR2,
        p_valor_nue    IN VARCHAR2
    );

END PKG_AUD_CONTROL;
/
SHOW ERRORS PACKAGE PKG_AUD_CONTROL;

CREATE OR REPLACE PACKAGE BODY PKG_AUD_CONTROL IS

    PROCEDURE PR_REGISTRAR_ERROR (
        p_paquete      IN VARCHAR2,
        p_subprograma  IN VARCHAR2,
        p_codigo_sql   IN NUMBER,
        p_mensaje      IN VARCHAR2,
        p_pila         IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_pila VARCHAR2(2000);
    BEGIN
        v_pila := NVL(p_pila, SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 2000));

        INSERT INTO AUD_ERROR_SISTEMA (
            ID_ERROR_SISTEMA,
            PAQUETE_ERSI,
            SUBPROGRAMA_ERSI,
            CODIGO_SQL_ERSI,
            MENSAJE_ERROR_ERSI,
            PILA_ERROR_ERSI,
            TERMINAL_ERSI,
            USUARIO_CREA_ERSI,
            FECHA_CREA_ERSI
        ) VALUES (
            SEQ_AUD_ERROR_SISTEMA.NEXTVAL,
            SUBSTR(NVL(p_paquete, 'DESCONOCIDO'), 1, 30),
            SUBSTR(NVL(p_subprograma, 'DESCONOCIDO'), 1, 50),
            NVL(p_codigo_sql, -1),
            SUBSTR(NVL(p_mensaje, 'Error sin mensaje'), 1, 500),
            v_pila,
            SUBSTR(SYS_CONTEXT('USERENV', 'TERMINAL'), 1, 64),
            SUBSTR(SYS_CONTEXT('USERENV', 'SESSION_USER'), 1, 30),
            SYSTIMESTAMP
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END PR_REGISTRAR_ERROR;

    PROCEDURE PR_REGISTRAR_OPERACION (
        p_tabla        IN VARCHAR2,
        p_llave        IN VARCHAR2,
        p_operacion    IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_descripcion  IN VARCHAR2,
        p_id_usuario   IN NUMBER DEFAULT NULL,
        p_id_sucursal  IN NUMBER DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_operacion VARCHAR2(10);
    BEGIN
        v_operacion := CASE
                           WHEN UPPER(p_operacion) IN ('INSERT','UPDATE','DELETE','LOGIN','LOGOUT','ANULAR','CONSULTA')
                           THEN UPPER(p_operacion)
                           WHEN UPPER(p_operacion) IN ('ABONO','CREDITO_AUTO','CARGA','COMPILACION')
                           THEN 'INSERT'
                           WHEN UPPER(p_operacion) IN ('CANCELACION_AUTO','ACTIVACION','DESACTIVACION')
                           THEN 'UPDATE'
                           ELSE 'UPDATE'
                       END;

        INSERT INTO AUD_BITACORA (
            ID_BITACORA,
            ID_USUARIO,
            ID_SUCURSAL,
            TABLA_BITA,
            LLAVE_REGISTRO_BITA,
            OPERACION_BITA,
            MODULO_BITA,
            DESCRIPCION_BITA,
            DIRECCION_IP_BITA,
            FECHA_BITA,
            USUARIO_CREA_BITA,
            FECHA_CREA_BITA
        ) VALUES (
            SEQ_AUD_BITACORA.NEXTVAL,
            p_id_usuario,
            p_id_sucursal,
            SUBSTR(NVL(p_tabla, 'SISTEMA'), 1, 30),
            SUBSTR(p_llave, 1, 50),
            v_operacion,
            SUBSTR(p_modulo, 1, 50),
            SUBSTR(p_descripcion, 1, 500),
            SUBSTR(NVL(SYS_CONTEXT('USERENV', 'IP_ADDRESS'), '127.0.0.1'), 1, 45),
            SYSTIMESTAMP,
            SUBSTR(SYS_CONTEXT('USERENV', 'SESSION_USER'), 1, 30),
            SYSTIMESTAMP
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END PR_REGISTRAR_OPERACION;

    PROCEDURE PR_REGISTRAR_CAMBIO (
        p_tabla        IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_operacion    IN VARCHAR2,
        p_llave        IN VARCHAR2,
        p_campo        IN VARCHAR2,
        p_valor_ant    IN VARCHAR2,
        p_valor_nue    IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO AUD_REGISTRO_CAMBIO (
            ID_REGISTRO_CAMBIO,
            TABLA_RECA,
            MODULO_RECA,
            OPERACION_RECA,
            LLAVE_PRIMARIA_RECA,
            CAMPO_MODIFICADO_RECA,
            VALOR_ANTERIOR_RECA,
            VALOR_NUEVO_RECA,
            TERMINAL_RECA,
            DIRECCION_IP_RECA,
            USUARIO_CREA_RECA,
            FECHA_CREA_RECA
        ) VALUES (
            SEQ_AUD_REGISTRO_CAMBIO.NEXTVAL,
            SUBSTR(p_tabla, 1, 30),
            SUBSTR(p_modulo, 1, 30),
            UPPER(SUBSTR(p_operacion, 1, 10)),
            SUBSTR(p_llave, 1, 50),
            SUBSTR(p_campo, 1, 50),
            SUBSTR(p_valor_ant, 1, 500),
            SUBSTR(p_valor_nue, 1, 500),
            SUBSTR(SYS_CONTEXT('USERENV', 'TERMINAL'), 1, 64),
            SUBSTR(NVL(SYS_CONTEXT('USERENV', 'IP_ADDRESS'), '127.0.0.1'), 1, 45),
            SUBSTR(SYS_CONTEXT('USERENV', 'SESSION_USER'), 1, 30),
            SYSTIMESTAMP
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
    END PR_REGISTRAR_CAMBIO;

END PKG_AUD_CONTROL;
/
SHOW ERRORS PACKAGE BODY PKG_AUD_CONTROL;


--------------------------------------------------------------------------------
-- 2. PAQUETE: PKG_SEG_SEGURIDAD
--    Cifrado DBMS_CRYPTO (AES-256), administracion de SEG_PARAMETRO
--    y asignacion/activacion de contrasenas cifradas en roles de BD.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_SEG_SEGURIDAD IS

    -- Cifra un texto en claro utilizando DBMS_CRYPTO (AES-256 + CBC + PKCS5)
    FUNCTION FN_CIFRAR_VALOR (
        p_texto IN VARCHAR2
    ) RETURN RAW;

    -- Descifra un valor RAW cifrado con DBMS_CRYPTO y devuelve el texto original
    FUNCTION FN_DESCIFRAR_VALOR (
        p_cifrado IN RAW
    ) RETURN VARCHAR2;

    -- Inserta o actualiza un parametro en SEG_PARAMETRO (con soporte de cifrado)
    PROCEDURE PR_GUARDAR_PARAMETRO (
        p_codigo       IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_nombre       IN VARCHAR2,
        p_descripcion  IN VARCHAR2,
        p_es_cifrado   IN VARCHAR2,
        p_valor_texto  IN VARCHAR2 DEFAULT NULL,
        p_valor_num    IN NUMBER   DEFAULT NULL
    );

    -- Obtiene el valor textual de un parametro (si esta cifrado, lo descifra automaticamente)
    FUNCTION FN_OBTENER_PARAM_TEXTO (
        p_codigo IN VARCHAR2
    ) RETURN VARCHAR2;

    -- Obtiene el valor numerico de un parametro
    FUNCTION FN_OBTENER_PARAM_NUM (
        p_codigo IN VARCHAR2
    ) RETURN NUMBER;

    -- Asigna la contrasena a un Rol de BD leyendola (o actualizandola) cifrada en SEG_PARAMETRO
    PROCEDURE PR_ASIGNAR_CLAVE_ROL (
        p_nombre_rol    IN VARCHAR2,
        p_codigo_param  IN VARCHAR2,
        p_nueva_clave   IN VARCHAR2 DEFAULT NULL
    );

    -- Devuelve la sentencia SET ROLE con la clave desencriptada y registra el uso del rol
    FUNCTION FN_OBTENER_CLAVE_ROL (
        p_nombre_rol IN VARCHAR2
    ) RETURN VARCHAR2;

END PKG_SEG_SEGURIDAD;
/
SHOW ERRORS PACKAGE PKG_SEG_SEGURIDAD;

CREATE OR REPLACE PACKAGE BODY PKG_SEG_SEGURIDAD IS

    -- Llave simetrica de 32 bytes (256 bits) para AES-256
    c_llave_aes CONSTANT RAW(32)     := UTL_I18N.STRING_TO_RAW('CADENA_NEG_AES256_KEY_UNA_2026!!', 'AL32UTF8');
    c_algoritmo CONSTANT PLS_INTEGER := DBMS_CRYPTO.ENCRYPT_AES256
                                      + DBMS_CRYPTO.CHAIN_CBC
                                      + DBMS_CRYPTO.PAD_PKCS5;

    FUNCTION FN_CIFRAR_VALOR (
        p_texto IN VARCHAR2
    ) RETURN RAW IS
    BEGIN
        IF p_texto IS NULL THEN
            RETURN NULL;
        END IF;

        RETURN DBMS_CRYPTO.ENCRYPT(
            src => UTL_I18N.STRING_TO_RAW(p_texto, 'AL32UTF8'),
            typ => c_algoritmo,
            key => c_llave_aes
        );
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'FN_CIFRAR_VALOR', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20021, 'Error al cifrar informacion sensible con DBMS_CRYPTO: ' || SQLERRM);
    END FN_CIFRAR_VALOR;

    FUNCTION FN_DESCIFRAR_VALOR (
        p_cifrado IN RAW
    ) RETURN VARCHAR2 IS
        v_raw_descifrado RAW(2000);
    BEGIN
        IF p_cifrado IS NULL THEN
            RETURN NULL;
        END IF;

        v_raw_descifrado := DBMS_CRYPTO.DECRYPT(
            src => p_cifrado,
            typ => c_algoritmo,
            key => c_llave_aes
        );

        RETURN UTL_I18N.RAW_TO_CHAR(v_raw_descifrado, 'AL32UTF8');
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'FN_DESCIFRAR_VALOR', SQLCODE, SQLERRM);
            RAISE_APPLICATION_ERROR(-20022, 'Error al descifrar informacion sensible con DBMS_CRYPTO: ' || SQLERRM);
    END FN_DESCIFRAR_VALOR;

    PROCEDURE PR_GUARDAR_PARAMETRO (
        p_codigo       IN VARCHAR2,
        p_modulo       IN VARCHAR2,
        p_nombre       IN VARCHAR2,
        p_descripcion  IN VARCHAR2,
        p_es_cifrado   IN VARCHAR2,
        p_valor_texto  IN VARCHAR2 DEFAULT NULL,
        p_valor_num    IN NUMBER   DEFAULT NULL
    ) IS
        v_raw     RAW(2000);
        v_texto   VARCHAR2(500);
        v_existe  NUMBER;
    BEGIN
        SAVEPOINT sp_guardar_param;

        IF UPPER(p_es_cifrado) = 'S' THEN
            v_raw   := FN_CIFRAR_VALOR(p_valor_texto);
            v_texto := NULL;
        ELSE
            v_raw   := NULL;
            v_texto := p_valor_texto;
        END IF;

        SELECT COUNT(*) INTO v_existe
          FROM SEG_PARAMETRO
         WHERE CODIGO_PARA = UPPER(TRIM(p_codigo));

        IF v_existe = 0 THEN
            INSERT INTO SEG_PARAMETRO (
                ID_PARAMETRO, CODIGO_PARA, MODULO_PARA, NOMBRE_PARA,
                DESCRIPCION_PARA, ES_CIFRADO_PARA, VALOR_TEXTO_PARA,
                VALOR_NUM_PARA, VALOR_RAW_PARA, ESTADO_PARA
            ) VALUES (
                SEQ_SEG_PARAMETRO.NEXTVAL,
                UPPER(TRIM(p_codigo)),
                UPPER(TRIM(p_modulo)),
                p_nombre,
                p_descripcion,
                UPPER(p_es_cifrado),
                v_texto,
                p_valor_num,
                v_raw,
                'A'
            );
        ELSE
            UPDATE SEG_PARAMETRO
               SET MODULO_PARA      = UPPER(TRIM(p_modulo)),
                   NOMBRE_PARA      = p_nombre,
                   DESCRIPCION_PARA = p_descripcion,
                   ES_CIFRADO_PARA  = UPPER(p_es_cifrado),
                   VALOR_TEXTO_PARA = v_texto,
                   VALOR_NUM_PARA   = p_valor_num,
                   VALOR_RAW_PARA   = v_raw,
                   USUARIO_MOD_PARA = USER,
                   FECHA_MOD_PARA   = SYSTIMESTAMP
             WHERE CODIGO_PARA = UPPER(TRIM(p_codigo));
        END IF;

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_guardar_param;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'PR_GUARDAR_PARAMETRO', SQLCODE, SQLERRM);
            RAISE;
    END PR_GUARDAR_PARAMETRO;

    FUNCTION FN_OBTENER_PARAM_TEXTO (
        p_codigo IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_es_cifrado VARCHAR2(1);
        v_texto      VARCHAR2(500);
        v_raw        RAW(2000);
    BEGIN
        SELECT ES_CIFRADO_PARA, VALOR_TEXTO_PARA, VALOR_RAW_PARA
          INTO v_es_cifrado, v_texto, v_raw
          FROM SEG_PARAMETRO
         WHERE CODIGO_PARA = UPPER(TRIM(p_codigo))
           AND ESTADO_PARA = 'A';

        IF v_es_cifrado = 'S' THEN
            RETURN FN_DESCIFRAR_VALOR(v_raw);
        ELSE
            RETURN v_texto;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'FN_OBTENER_PARAM_TEXTO', -20023,
                'Parametro no encontrado o inactivo: ' || p_codigo);
            RAISE_APPLICATION_ERROR(-20023, 'El parametro ' || p_codigo || ' no existe o esta inactivo.');
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'FN_OBTENER_PARAM_TEXTO', SQLCODE, SQLERRM);
            RAISE;
    END FN_OBTENER_PARAM_TEXTO;

    FUNCTION FN_OBTENER_PARAM_NUM (
        p_codigo IN VARCHAR2
    ) RETURN NUMBER IS
        v_num NUMBER(14,4);
    BEGIN
        SELECT VALOR_NUM_PARA
          INTO v_num
          FROM SEG_PARAMETRO
         WHERE CODIGO_PARA = UPPER(TRIM(p_codigo))
           AND ESTADO_PARA = 'A';

        RETURN v_num;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'FN_OBTENER_PARAM_NUM', -20024,
                'Parametro numerico no encontrado: ' || p_codigo);
            RAISE_APPLICATION_ERROR(-20024, 'El parametro numerico ' || p_codigo || ' no existe o esta inactivo.');
    END FN_OBTENER_PARAM_NUM;

    FUNCTION FN_OBTENER_CLAVE_ROL (
        p_nombre_rol IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_codigo_param VARCHAR2(40);
    BEGIN
        v_codigo_param := CASE UPPER(TRIM(p_nombre_rol))
                              WHEN 'ROL_GERENTE'           THEN 'CLAVE_ROL_GERENTE'
                              WHEN 'ROL_JEFE_DEPARTAMENTO' THEN 'CLAVE_ROL_JEFE_DEPTO'
                              WHEN 'ROL_JEFE_PROVEEDURIA'  THEN 'CLAVE_ROL_JEFE_PROV'
                              WHEN 'ROL_DIGITADOR'         THEN 'CLAVE_ROL_DIGITADOR'
                              ELSE 'CLAVE_' || UPPER(TRIM(p_nombre_rol))
                          END;

        RETURN FN_OBTENER_PARAM_TEXTO(v_codigo_param);
    END FN_OBTENER_CLAVE_ROL;

    PROCEDURE PR_ASIGNAR_CLAVE_ROL (
        p_nombre_rol    IN VARCHAR2,
        p_codigo_param  IN VARCHAR2,
        p_nueva_clave   IN VARCHAR2 DEFAULT NULL
    ) IS
        v_clave      VARCHAR2(200);
        v_rol_limpio VARCHAR2(128);
    BEGIN
        SAVEPOINT sp_asignar_rol;

        IF NOT REGEXP_LIKE(TRIM(p_nombre_rol), '^[A-Za-z_][A-Za-z0-9_#$]{0,127}$') THEN
            RAISE_APPLICATION_ERROR(-20025, 'Nombre de rol invalido: ' || p_nombre_rol);
        END IF;
        v_rol_limpio := UPPER(TRIM(p_nombre_rol));

        IF p_nueva_clave IS NOT NULL THEN
            UPDATE SEG_PARAMETRO
               SET VALOR_RAW_PARA   = FN_CIFRAR_VALOR(p_nueva_clave),
                   ES_CIFRADO_PARA  = 'S',
                   USUARIO_MOD_PARA = USER,
                   FECHA_MOD_PARA   = SYSTIMESTAMP
             WHERE CODIGO_PARA = UPPER(TRIM(p_codigo_param));
            v_clave := p_nueva_clave;
        ELSE
            v_clave := FN_OBTENER_PARAM_TEXTO(p_codigo_param);
        END IF;

        EXECUTE IMMEDIATE 'ALTER ROLE ' || v_rol_limpio || ' IDENTIFIED BY "' || v_clave || '"';

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
            p_tabla       => 'SEG_PARAMETRO',
            p_llave       => v_rol_limpio,
            p_operacion   => 'UPDATE',
            p_modulo      => 'Seguridad',
            p_descripcion => 'Se asigno contrasena cifrada al rol ' || v_rol_limpio || ' desde ' || p_codigo_param
        );

        COMMIT;
        DBMS_OUTPUT.PUT_LINE('[OK] Clave cifrada asignada al rol ' || v_rol_limpio || ' desde SEG_PARAMETRO (' || p_codigo_param || ').');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK TO sp_asignar_rol;
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_SEG_SEGURIDAD', 'PR_ASIGNAR_CLAVE_ROL', SQLCODE, SQLERRM);
            RAISE;
    END PR_ASIGNAR_CLAVE_ROL;

END PKG_SEG_SEGURIDAD;
/
SHOW ERRORS PACKAGE BODY PKG_SEG_SEGURIDAD;

-- Procedimiento con AUTHID CURRENT_USER para activar un rol con clave cifrada en la sesion actual
CREATE OR REPLACE PROCEDURE PRC_ACTIVAR_ROL_SESION (
    p_nombre_rol IN VARCHAR2
) AUTHID CURRENT_USER IS
    v_clave VARCHAR2(200);
BEGIN
    v_clave := CADENA_NEG.PKG_SEG_SEGURIDAD.FN_OBTENER_CLAVE_ROL(p_nombre_rol);
    DBMS_SESSION.SET_ROLE(UPPER(TRIM(p_nombre_rol)) || ' IDENTIFIED BY "' || v_clave || '"');

    CADENA_NEG.PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
        p_tabla       => 'SEG_PARAMETRO',
        p_llave       => UPPER(TRIM(p_nombre_rol)),
        p_operacion   => 'LOGIN',
        p_modulo      => 'Seguridad',
        p_descripcion => 'Rol ' || UPPER(TRIM(p_nombre_rol)) || ' activado con clave desencriptada para el usuario ' || SYS_CONTEXT('USERENV', 'SESSION_USER')
    );

    DBMS_OUTPUT.PUT_LINE('[OK] Rol ' || UPPER(TRIM(p_nombre_rol)) || ' activado en la sesion actual mediante clave desencriptada.');
EXCEPTION
    WHEN OTHERS THEN
        CADENA_NEG.PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PRC_ACTIVAR_ROL_SESION', 'SET_ROLE', SQLCODE, SQLERRM);
        RAISE;
END PRC_ACTIVAR_ROL_SESION;
/
SHOW ERRORS PROCEDURE PRC_ACTIVAR_ROL_SESION;


--------------------------------------------------------------------------------
-- 3. PAQUETE: PKG_ADM_NOTIFICACION
--    Envio directo de correos desde Oracle con UTL_SMTP (sin VPN) y procesos
--    de notificacion de limites de credito, clientes morosos y vencidos.
--------------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_ADM_NOTIFICACION IS

    -- Envia un correo directamente desde Oracle usando UTL_SMTP y parametros cifrados
    PROCEDURE PR_ENVIAR_CORREO (
        p_destinatarios IN VARCHAR2,
        p_asunto        IN VARCHAR2,
        p_cuerpo        IN CLOB
    );

    -- Notifica a clientes con >= 85% de su limite en CxC y envia resumen al coordinador
    PROCEDURE PR_NOTIF_CLIENTES_85_CREDITO;

    -- Notifica al gerente en un solo correo consolidado cuando proveedores estan >= 70% de limite CxP
    PROCEDURE PR_NOTIF_PROVEEDORES_70_CREDITO;

    -- Notifica al gerente y coordinador clientes con saldo pendiente y ultimo pago > 1 mes
    PROCEDURE PR_NOTIF_CLIENTES_MOROSOS;

    -- Notifica al coordinador la lista de productos vencidos incluyendo el total general
    PROCEDURE PR_NOTIF_PRODUCTOS_VENCIDOS;

    -- Devuelve el HTML (adaptable al celular) con que se enviaria un correo; sirve
    -- para revisar el formato sin enviarlo: SELECT ... FN_VISTA_PREVIA_HTML(...) FROM dual
    FUNCTION FN_VISTA_PREVIA_HTML (
        p_asunto IN VARCHAR2,
        p_cuerpo IN CLOB
    ) RETURN CLOB;

END PKG_ADM_NOTIFICACION;
/
SHOW ERRORS PACKAGE PKG_ADM_NOTIFICACION;

CREATE OR REPLACE PACKAGE BODY PKG_ADM_NOTIFICACION IS

    -- -------------------------------------------------------------------------
    -- Correo en HTML (privado)
    -- Diseno inspirado en los correos de Apple: tarjeta blanca con esquinas
    -- redondeadas sobre fondo gris claro, tipografia del sistema (San Francisco
    -- en iPhone/Mac, Segoe UI en Windows, Roboto en Android), color e icono
    -- segun el tipo de aviso y modo oscuro en Apple Mail / iOS.
    -- Convierte el cuerpo en texto que arman las notificaciones (titulo en
    -- mayusculas, lineas '====' / '----', columnas alineadas con espacios y
    -- lineas "Etiqueta: valor | Etiqueta: valor") en:
    --   * tablas reales en la computadora y tarjetas apiladas en el celular
    --     (media query de 600 px; sin ella se ve la tabla con desplazamiento);
    --   * listas agrupadas tipo "Ajustes" para los pares etiqueta / valor;
    --   * porcentajes como pastillas de color (verde, ambar, naranja, rojo).
    -- -------------------------------------------------------------------------
    TYPE t_celdas IS TABLE OF VARCHAR2(4000);

    c_fuente CONSTANT VARCHAR2(200) :=
        '-apple-system,BlinkMacSystemFont,''SF Pro Text'',''Segoe UI'',Roboto,''Helvetica Neue'',Arial,sans-serif';

    -- Colores del tema del correo que se esta armando (los fija pr_tema)
    g_acento VARCHAR2(7) := '#007AFF';   -- color vivo (barra superior, graficos)
    g_texto  VARCHAR2(7) := '#0066CC';   -- version oscura legible sobre blanco
    g_suave  VARCHAR2(7) := '#E8F1FD';   -- fondo tenue del icono y del medidor

    FUNCTION fn_escapar_html(p_texto IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN REPLACE(REPLACE(REPLACE(p_texto, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
    END fn_escapar_html;

    -- Celdas de una fila: grupos de palabras separados por 2 o mas espacios (o tabulador)
    FUNCTION fn_celdas(p_linea IN VARCHAR2) RETURN t_celdas IS
        v_linea VARCHAR2(4000) := REPLACE(TRIM(p_linea), CHR(9), '  ');
        v_res   t_celdas       := t_celdas();
    BEGIN
        FOR i IN 1 .. NVL(REGEXP_COUNT(v_linea, '[^ ]+( [^ ]+)*'), 0) LOOP
            v_res.EXTEND;
            v_res(i) := REGEXP_SUBSTR(v_linea, '[^ ]+( [^ ]+)*', 1, i);
        END LOOP;
        RETURN v_res;
    END fn_celdas;

    FUNCTION fn_es_numero(p IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN REGEXP_LIKE(p, '^(#|CRC |C )?[-+]?[0-9][0-9.,]*%?$');
    END fn_es_numero;

    -- Texto casi todo en mayusculas (titulos que arman las notificaciones)
    FUNCTION fn_es_mayusculas(p IN VARCHAR2) RETURN BOOLEAN IS
    BEGIN
        RETURN NVL(REGEXP_COUNT(p, '[a-z]'), 0) <= 2 AND NVL(REGEXP_COUNT(p, '[A-Z]'), 0) >= 3;
    END fn_es_mayusculas;

    -- "REPORTE DE PRODUCTOS VENCIDOS" -> "Reporte de productos vencidos"
    FUNCTION fn_oracion(p IN VARCHAR2) RETURN VARCHAR2 IS
        v VARCHAR2(4000) := TRIM(p);
    BEGIN
        IF fn_es_mayusculas(v) THEN
            v := UPPER(SUBSTR(v, 1, 1)) || LOWER(SUBSTR(v, 2));
            v := REPLACE(REPLACE(REPLACE(REPLACE(v, 'cxc', 'CxC'), 'cxp', 'CxP'), 'crc', 'CRC'), 'cadena_neg', 'CADENA_NEG');
            v := REPLACE(REPLACE(REPLACE(v, ' bd', ' BD'), 'top ', 'Top '), 'super brunca', 'Super Brunca');
        END IF;
        RETURN v;
    END fn_oracion;

    -- Valor de una celda: los porcentajes se muestran como pastilla de color
    FUNCTION fn_valor(p IN VARCHAR2) RETURN VARCHAR2 IS
        v_num NUMBER;
        v_col VARCHAR2(7);
        v_bg  VARCHAR2(7);
    BEGIN
        IF REGEXP_LIKE(TRIM(p), '^[0-9]+([.,][0-9]+)?%$') THEN
            BEGIN
                v_num := TO_NUMBER(REPLACE(REPLACE(TRIM(p), '%', ''), ',', '.'), '999999999D99999',
                                   'NLS_NUMERIC_CHARACTERS=''.,''');
            EXCEPTION WHEN OTHERS THEN v_num := NULL;
            END;
            IF v_num IS NOT NULL THEN
                IF    v_num >= 100 THEN v_col := '#D70015'; v_bg := '#FFE5E3';
                ELSIF v_num >= 85  THEN v_col := '#C93400'; v_bg := '#FFEFDD';
                ELSIF v_num >= 70  THEN v_col := '#946200'; v_bg := '#FFF6D6';
                ELSE                    v_col := '#248A3D'; v_bg := '#E3F7E8';
                END IF;
                RETURN '<span style="display:inline-block;padding:3px 10px;border-radius:999px;font-weight:600;font-size:13px;'
                    || 'white-space:nowrap;color:' || v_col || ';background:' || v_bg || '">' || fn_escapar_html(TRIM(p)) || '</span>';
            END IF;
        END IF;
        RETURN fn_escapar_html(p);
    END fn_valor;

    -- Tema segun el asunto: color, etiqueta superior e icono (entidades HTML: solo ASCII en el codigo)
    PROCEDURE pr_tema(p_asunto IN VARCHAR2, p_etiqueta OUT VARCHAR2, p_icono OUT VARCHAR2) IS
        v_a VARCHAR2(4000) := UPPER(p_asunto);
    BEGIN
        IF INSTR(v_a, 'INCONSISTENCIA BD') > 0 THEN
            g_acento := '#FF3B30'; g_texto := '#D70015'; g_suave := '#FFE9E7';
            p_etiqueta := 'Inconsistencia en la base de datos'; p_icono := '&#x26A0;&#xFE0F;';
        ELSIF INSTR(v_a, 'ALERTA BD') > 0 THEN
            g_acento := '#FF3B30'; g_texto := '#D70015'; g_suave := '#FFE9E7';
            p_etiqueta := 'Errores del sistema'; p_icono := '&#x1F6A8;';
        ELSIF INSTR(v_a, 'ALERTA SESIONES') > 0 THEN
            g_acento := '#FF3B30'; g_texto := '#D70015'; g_suave := '#FFE9E7';
            p_etiqueta := 'Sesiones y bloqueos'; p_icono := '&#x1F512;';
        ELSIF INSTR(v_a, 'STANDBY') > 0 THEN
            g_acento := '#FF3B30'; g_texto := '#D70015'; g_suave := '#FFE9E7';
            p_etiqueta := 'Standby &middot; Data Guard'; p_icono := '&#x1F504;';
        ELSIF INSTR(v_a, 'VENCID') > 0 THEN
            g_acento := '#FF9500'; g_texto := '#C93400'; g_suave := '#FFF1E0';
            p_etiqueta := 'Inventario'; p_icono := '&#x1F4E6;';
        ELSIF INSTR(v_a, 'ALERTA') > 0 THEN
            g_acento := '#FF9500'; g_texto := '#C93400'; g_suave := '#FFF1E0';
            p_etiqueta := 'Alerta de cr&eacute;dito'; p_icono := '&#x1F514;';
        ELSIF INSTR(v_a, 'AVISO') > 0 THEN
            g_acento := '#FF9500'; g_texto := '#C93400'; g_suave := '#FFF1E0';
            p_etiqueta := 'Aviso de cr&eacute;dito'; p_icono := '&#x1F4B3;';
        ELSIF INSTR(v_a, 'PREMIACION') > 0 THEN
            g_acento := '#AF52DE'; g_texto := '#8944AB'; g_suave := '#F5EBFA';
            p_etiqueta := 'Mercadeo &middot; Premiaci&oacute;n'; p_icono := '&#x1F381;';
        ELSIF INSTR(v_a, 'MERCADEO') > 0 THEN
            g_acento := '#30B0C7'; g_texto := '#0071A4'; g_suave := '#E3F5F9';
            p_etiqueta := 'Mercadeo'; p_icono := '&#x1F3F7;&#xFE0F;';
        ELSIF INSTR(v_a, 'CIERRE') > 0 THEN
            g_acento := '#34C759'; g_texto := '#248A3D'; g_suave := '#E6F6EA';
            p_etiqueta := 'Cierre diario'; p_icono := '&#x1F9FE;';
        ELSE
            g_acento := '#007AFF'; g_texto := '#0066CC'; g_suave := '#E8F1FD';
            p_etiqueta := 'Notificaci&oacute;n'; p_icono := '&#x2709;&#xFE0F;';
        END IF;
    END pr_tema;

    FUNCTION fn_texto_a_html(p_asunto IN VARCHAR2, p_cuerpo IN CLOB) RETURN CLOB IS
        TYPE t_lineas IS TABLE OF VARCHAR2(4000);
        v_lineas    t_lineas := t_lineas();
        -- NVL: con un cuerpo vacio DBMS_LOB.INSTR devuelve NULL y el ciclo no terminaria
        v_texto     CLOB := NVL(REPLACE(p_cuerpo, CHR(13), ''), ' ');
        v_ini       PLS_INTEGER := 1;
        v_fin       PLS_INTEGER;
        v_t         VARCHAR2(4000);
        v_sig       VARCHAR2(4000);
        v_html      CLOB;
        v_saltar    PLS_INTEGER := 0;
        -- Estado
        v_en_tabla  BOOLEAN := FALSE;
        v_en_lista  BOOLEAN := FALSE;
        v_primera   BOOLEAN := TRUE;   -- primera fila de la lista (sin linea superior)
        v_inicio    BOOLEAN := TRUE;   -- todavia no se escribio contenido
        v_enc       t_celdas;
        v_filas     t_lineas := t_lineas();
        -- Encabezado
        v_etiqueta  VARCHAR2(200);
        v_icono     VARCHAR2(60);
        v_titulo    VARCHAR2(4000) := NVL(p_asunto, 'Notificacion');
        v_prefijo   VARCHAR2(200);
        v_resumen   VARCHAR2(400);
        v_porc      VARCHAR2(20);
        v_fecha     VARCHAR2(60);
        v_parte     VARCHAR2(4000);
        v_lbl       VARCHAR2(4000);
        v_val       VARCHAR2(4000);

        FUNCTION es_separador(p IN VARCHAR2) RETURN BOOLEAN IS
        BEGIN
            RETURN REGEXP_LIKE(TRIM(p), '^[=-]{8,}$');
        END;

        PROCEDURE agregar(p IN VARCHAR2) IS
        BEGIN
            IF p IS NOT NULL THEN DBMS_LOB.WRITEAPPEND(v_html, LENGTH(p), p); END IF;
        END;

        PROCEDURE cerrar_lista IS
        BEGIN
            IF v_en_lista THEN agregar('</table>'); v_en_lista := FALSE; END IF;
        END;

        PROCEDURE abrir_lista IS
        BEGIN
            cerrar_lista;
            agregar('<table role="presentation" class="sb-in" width="100%" cellpadding="0" cellspacing="0" '
                 || 'style="background:#f5f5f7;border-radius:14px;margin:0 0 14px;border-collapse:separate">');
            v_en_lista := TRUE;
            v_primera  := TRUE;
        END;

        PROCEDURE fila_lista(p_lbl IN VARCHAR2, p_val IN VARCHAR2) IS
            v_borde VARCHAR2(60) := CASE WHEN v_primera THEN '' ELSE 'border-top:1px solid #e5e5ea;' END;
            v_valor VARCHAR2(4000);
        BEGIN
            IF REGEXP_LIKE(p_val, '^(EXEC|SELECT|ALTER|BEGIN) ', 'i') THEN
                v_valor := '<code style="font-family:SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;'
                        || 'background:#e8e8ed;padding:2px 6px;border-radius:6px;font-weight:400">' || fn_escapar_html(p_val) || '</code>';
            ELSE
                v_valor := fn_valor(p_val);
            END IF;
            IF p_lbl IS NULL THEN
                agregar('<tr><td colspan="2" class="sb-tx sb-ln" style="padding:12px 16px;font-size:15px;color:#1d1d1f;' || v_borde || '">'
                     || v_valor || '</td></tr>');
            ELSE
                agregar('<tr><td class="sb-mu sb-ln" style="padding:12px 8px 12px 16px;font-size:14px;color:#6e6e73;vertical-align:top;'
                     || CASE WHEN LENGTH(p_lbl) <= 18 THEN 'white-space:nowrap;' END || v_borde || '">'
                     || fn_escapar_html(p_lbl) || '</td><td class="sb-tx sb-ln" style="padding:12px 16px 12px 8px;font-size:15px;font-weight:600;'
                     || 'color:#1d1d1f;text-align:right;vertical-align:top;' || v_borde || '">' || v_valor || '</td></tr>');
            END IF;
            v_primera := FALSE;
        END;

        -- Escribe la tabla acumulada dos veces: como tabla (computadora) y como tarjetas (celular)
        PROCEDURE cerrar_tabla IS
            v_n      PLS_INTEGER := v_enc.COUNT;
            v_num    t_celdas    := t_celdas();   -- 'S' si la columna es numerica
            v_c      t_celdas;
            v_tit    PLS_INTEGER;
            v_sub    PLS_INTEGER;
            v_estilo VARCHAR2(400);
            v_ult    BOOLEAN;
        BEGIN
            v_en_tabla := FALSE;
            v_num.EXTEND(v_n);
            FOR c IN 1 .. v_n LOOP v_num(c) := 'N'; END LOOP;
            FOR f IN 1 .. v_filas.COUNT LOOP
                v_c := fn_celdas(v_filas(f));
                IF v_c.COUNT = v_n THEN
                    FOR c IN 1 .. v_n LOOP
                        v_num(c) := CASE WHEN fn_es_numero(v_c(c)) THEN 'S' ELSE 'N' END;
                    END LOOP;
                    EXIT;
                END IF;
            END LOOP;

            -- Computadora: tabla con bordes finos y encabezados pequenos
            agregar('<div class="sb-desk" style="margin:0 0 18px"><div class="sb-ln" style="overflow-x:auto;border:1px solid #e5e5ea;border-radius:14px">'
                 || '<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="border-collapse:collapse;font-size:14px"><tr>');
            FOR c IN 1 .. v_n LOOP
                agregar('<th class="sb-in sb-mu sb-ln" style="padding:10px 14px;font-size:11px;font-weight:600;letter-spacing:.05em;text-transform:uppercase;'
                     || 'color:#86868b;background:#fafafc;border-bottom:1px solid #e5e5ea;white-space:nowrap;text-align:'
                     || CASE WHEN v_num(c) = 'S' THEN 'right' ELSE 'left' END || '">' || fn_escapar_html(v_enc(c)) || '</th>');
            END LOOP;
            agregar('</tr>');
            FOR f IN 1 .. v_filas.COUNT LOOP
                v_c   := fn_celdas(v_filas(f));
                v_ult := (f = v_filas.COUNT);
                IF v_c.COUNT <> v_n THEN
                    agregar('<tr><td colspan="' || v_n || '" class="sb-tx" style="padding:12px 14px;font-weight:600;color:#1d1d1f">'
                         || fn_escapar_html(TRIM(v_filas(f))) || '</td></tr>');
                ELSE
                    agregar('<tr>');
                    FOR c IN 1 .. v_n LOOP
                        v_estilo := 'padding:11px 14px;color:#1d1d1f;'
                                 || CASE WHEN NOT v_ult THEN 'border-bottom:1px solid #f0f0f2;' END
                                 || CASE WHEN v_num(c) = 'S' THEN 'text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums;' END
                                 || CASE WHEN c = 1 THEN 'font-weight:600;white-space:nowrap;' END
                                 || CASE WHEN INSTR(v_c(c), ' ') = 0 THEN 'white-space:nowrap;' END;
                        agregar('<td class="sb-tx sb-ln" style="' || v_estilo || '">' || fn_valor(v_c(c)) || '</td>');
                    END LOOP;
                    agregar('</tr>');
                END IF;
            END LOOP;
            agregar('</table></div></div>');

            -- Celular: una tarjeta por fila (se muestra solo con pantallas de hasta 600 px)
            agregar('<div class="sb-mob" style="display:none;max-height:0;overflow:hidden;mso-hide:all">');
            FOR f IN 1 .. v_filas.COUNT LOOP
                v_c := fn_celdas(v_filas(f));
                IF v_c.COUNT <> v_n THEN
                    agregar('<div class="sb-tx" style="font-size:15px;font-weight:600;color:#1d1d1f;padding:2px 4px 12px">'
                         || fn_escapar_html(TRIM(v_filas(f))) || '</div>');
                ELSE
                    -- Titulo de la tarjeta: la columna del nombre (cliente, proveedor, producto...)
                    v_tit := 0; v_sub := 0;
                    FOR c IN 1 .. v_n LOOP
                        IF REGEXP_LIKE(UPPER(v_enc(c)), 'CLIENTE|PROVEEDOR|PRODUCTO|NOMBRE|TABLESPACE|OBJETO|INDICE') THEN
                            v_tit := c; EXIT;
                        END IF;
                    END LOOP;
                    IF v_tit = 0 THEN v_tit := 1; END IF;
                    IF v_tit > 1 THEN v_sub := 1; END IF;
                    agregar('<div class="sb-in" style="background:#f5f5f7;border-radius:14px;padding:14px 16px;margin:0 0 10px">'
                         || '<div class="sb-tx" style="font-size:16px;font-weight:600;color:#1d1d1f">' || fn_escapar_html(v_c(v_tit)) || '</div>');
                    IF v_sub > 0 THEN
                        agregar('<div class="sb-mu" style="font-size:13px;color:#6e6e73;margin-top:2px">' || fn_escapar_html(v_c(v_sub)) || '</div>');
                    END IF;
                    agregar('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:8px">');
                    FOR c IN 1 .. v_n LOOP
                        CONTINUE WHEN c = v_tit OR c = v_sub;
                        agregar('<tr><td class="sb-mu" style="padding:5px 0;font-size:13px;color:#6e6e73">' || fn_escapar_html(fn_oracion(v_enc(c)))
                             || '</td><td class="sb-tx" style="padding:5px 0;font-size:14px;font-weight:600;color:#1d1d1f;text-align:right">'
                             || fn_valor(v_c(c)) || '</td></tr>');
                    END LOOP;
                    agregar('</table></div>');
                END IF;
            END LOOP;
            agregar('</div>');
            v_filas := t_lineas();
        END cerrar_tabla;
    BEGIN
        -- Separar en lineas
        LOOP
            v_fin := DBMS_LOB.INSTR(v_texto, CHR(10), v_ini);
            -- Corte de seguridad: fin del texto o mas de 2000 lineas
            IF NVL(v_fin, 0) = 0 OR v_lineas.COUNT >= 2000 THEN
                v_lineas.EXTEND; v_lineas(v_lineas.COUNT) := DBMS_LOB.SUBSTR(v_texto, 4000, v_ini);
                EXIT;
            END IF;
            v_lineas.EXTEND; v_lineas(v_lineas.COUNT) := DBMS_LOB.SUBSTR(v_texto, LEAST(v_fin - v_ini, 4000), v_ini);
            v_ini := v_fin + 1;
        END LOOP;

        -- Tema, titulo y textos del encabezado
        pr_tema(p_asunto, v_etiqueta, v_icono);
        v_titulo := REGEXP_REPLACE(v_titulo, ' - Super Brunca$', '');
        v_prefijo := REGEXP_SUBSTR(v_titulo, '^(Alerta [^:]{3,40}|INCONSISTENCIA BD|ALERTA BD|ALERTA SESIONES): ', 1, 1, 'i');
        IF v_prefijo IS NOT NULL THEN
            IF UPPER(v_prefijo) LIKE 'ALERTA %' AND UPPER(v_prefijo) NOT LIKE 'ALERTA BD%' AND UPPER(v_prefijo) NOT LIKE 'ALERTA SESIONES%' THEN
                -- "Alerta Coordinador: ..." -> etiqueta "Alerta de credito · Coordinador"
                v_etiqueta := v_etiqueta || ' &middot; ' || fn_escapar_html(TRIM(SUBSTR(v_prefijo, 8, LENGTH(v_prefijo) - 9)));
            END IF;
            v_titulo := SUBSTR(v_titulo, LENGTH(v_prefijo) + 1);
            v_titulo := UPPER(SUBSTR(v_titulo, 1, 1)) || SUBSTR(v_titulo, 2);
        END IF;
        v_porc := REGEXP_SUBSTR(p_asunto, '([0-9]+([.,][0-9]+)?)% utilizado', 1, 1, 'i', 1);

        FOR i IN 1 .. v_lineas.COUNT LOOP
            v_t := TRIM(v_lineas(i));
            IF v_t IS NOT NULL AND NOT es_separador(v_t) THEN
                v_resumen := SUBSTR(fn_oracion(v_t), 1, 140);
                EXIT;
            END IF;
        END LOOP;
        IF v_porc IS NOT NULL THEN
            v_resumen := 'Su cr&eacute;dito est&aacute; al ' || v_porc || '% de su l&iacute;mite autorizado.';
        ELSE
            v_resumen := fn_escapar_html(v_resumen);
        END IF;

        BEGIN
            v_fecha := TO_CHAR(CAST(SYSTIMESTAMP AT TIME ZONE 'America/Costa_Rica' AS DATE),
                               'fmDD "de" month "de" YYYY, fmHH24:MI', 'NLS_DATE_LANGUAGE=SPANISH');
        EXCEPTION WHEN OTHERS THEN
            v_fecha := TO_CHAR(SYSDATE, 'DD/MM/YYYY HH24:MI');
        END;

        DBMS_LOB.CREATETEMPORARY(v_html, TRUE);
        agregar('<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">'
             || '<meta name="viewport" content="width=device-width,initial-scale=1">'
             || '<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">'
             || '<title>' || fn_escapar_html(v_titulo) || '</title><style>'
             || ':root{color-scheme:light dark;supported-color-schemes:light dark}'
             || 'body{margin:0;padding:0;-webkit-text-size-adjust:100%}'
             || '@media only screen and (max-width:600px){'
             || '.sb-desk{display:none!important;max-height:0!important;overflow:hidden!important}'
             || '.sb-mob{display:block!important;max-height:none!important;overflow:visible!important}'
             || '.sb-pad{padding-left:20px!important;padding-right:20px!important}'
             || '.sb-h1{font-size:24px!important}.sb-wrap{padding:12px 8px!important}}'
             || '@media (prefers-color-scheme:dark){'
             || '.sb-bg{background:#000000!important}.sb-card{background:#1c1c1e!important}'
             || '.sb-tx{color:#f5f5f7!important}.sb-mu{color:#a1a1a6!important}'
             || '.sb-in{background:#2c2c2e!important}.sb-ln{border-color:#3a3a3c!important}}'
             || '</style></head>');
        agregar('<body class="sb-bg" style="margin:0;padding:0;background:#f5f5f7;font-family:' || c_fuente || '">'
             -- Texto que se ve en la bandeja de entrada junto al asunto (oculto en el correo)
             || '<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all">' || v_resumen
             || RPAD(' ', 120, ' ') || '&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;</div>'
             || '<table role="presentation" class="sb-bg" width="100%" cellpadding="0" cellspacing="0" style="background:#f5f5f7">'
             || '<tr><td align="center" class="sb-wrap" style="padding:28px 12px">'
             || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:600px">'
             -- Tarjeta
             || '<tr><td class="sb-card" style="background:#ffffff;border-radius:22px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.06)">'
             || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0">'
             -- Franja de color del tipo de aviso
             || '<tr><td style="height:6px;line-height:6px;font-size:0;background:' || g_acento
             || ';background-image:linear-gradient(90deg,' || g_acento || ',' || g_suave || ')">&nbsp;</td></tr>'
             -- Marca y fecha
             || '<tr><td class="sb-pad" style="padding:22px 32px 0"><table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>'
             || '<td class="sb-tx" style="font-size:13px;font-weight:600;color:#1d1d1f;letter-spacing:-.01em">'
             || '<span style="display:inline-block;width:8px;height:8px;border-radius:50%;background:' || g_acento
             || ';margin-right:7px;vertical-align:middle"></span>Super Brunca</td>'
             || '<td align="right" class="sb-mu" style="font-size:12px;color:#86868b">' || v_fecha || '</td></tr></table></td></tr>'
             -- Icono, etiqueta y titulo
             || '<tr><td class="sb-pad" style="padding:26px 32px 4px">'
             || '<div style="width:52px;height:52px;border-radius:14px;background:' || g_suave
             || ';text-align:center;line-height:52px;font-size:26px">' || v_icono || '</div>'
             || '<div style="margin-top:18px;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' || g_texto || '">'
             || v_etiqueta || '</div>'
             || '<h1 class="sb-tx sb-h1" style="margin:6px 0 0;font-size:28px;line-height:1.18;font-weight:700;letter-spacing:-.02em;color:#1d1d1f">'
             || fn_escapar_html(v_titulo) || '</h1></td></tr>'
             || '<tr><td class="sb-pad" style="padding:22px 32px 30px;font-size:16px;line-height:1.55;color:#1d1d1f">');

        -- Medidor grande para el aviso de credito al cliente
        IF v_porc IS NOT NULL THEN
            DECLARE
                v_ancho NUMBER;
            BEGIN
                BEGIN
                    v_ancho := LEAST(100, GREATEST(2, ROUND(TO_NUMBER(REPLACE(v_porc, ',', '.'), '999999D99999',
                                                                      'NLS_NUMERIC_CHARACTERS=''.,'''))));
                EXCEPTION WHEN OTHERS THEN v_ancho := 85;
                END;
                agregar('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px"><tr>'
                     || '<td style="background:' || g_suave || ';border-radius:18px;padding:20px 22px">'
                     || '<div style="font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:' || g_texto
                     || '">Cr&eacute;dito utilizado</div>'
                     || '<div style="font-size:46px;font-weight:700;letter-spacing:-.03em;line-height:1.1;margin:6px 0 14px;color:' || g_texto || '">'
                     || fn_escapar_html(v_porc) || '%</div>'
                     || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:999px"><tr>'
                     || '<td width="' || v_ancho || '%" style="height:8px;line-height:8px;font-size:0;background:' || g_acento
                     || ';border-radius:999px">&nbsp;</td><td style="font-size:0;line-height:0">&nbsp;</td></tr></table></td></tr></table>');
            END;
        END IF;

        FOR i IN 1 .. v_lineas.COUNT LOOP
            CONTINUE WHEN i = v_saltar;   -- linea '-----' bajo el encabezado de una tabla
            v_t   := TRIM(REPLACE(v_lineas(i), CHR(9), '  '));
            v_sig := CASE WHEN i < v_lineas.COUNT THEN TRIM(v_lineas(i + 1)) END;

            IF v_en_tabla THEN
                IF v_t IS NULL OR es_separador(v_t) THEN
                    cerrar_tabla;
                ELSE
                    v_filas.EXTEND; v_filas(v_filas.COUNT) := v_t;
                END IF;
                CONTINUE;
            END IF;

            IF v_t IS NOT NULL AND NOT es_separador(v_t) AND v_sig IS NOT NULL
               AND REGEXP_LIKE(v_sig, '^-{8,}$') AND REGEXP_COUNT(v_t, '[^ ]+( [^ ]+)*') > 1 THEN
                -- Encabezado de tabla: linea con varias columnas seguida de '-----'
                cerrar_lista;
                v_enc      := fn_celdas(v_t);
                v_filas    := t_lineas();
                v_en_tabla := TRUE;
                v_saltar   := i + 1;
                v_inicio   := FALSE;
            ELSIF v_t IS NULL OR es_separador(v_t) THEN
                cerrar_lista;
            ELSIF v_inicio AND fn_es_mayusculas(v_t) THEN
                -- Primera linea en mayusculas: subtitulo debajo del titulo
                agregar('<p class="sb-mu" style="margin:0 0 22px;font-size:16px;line-height:1.5;color:#6e6e73">'
                     || fn_escapar_html(fn_oracion(v_t)) || '</p>');
            ELSIF UPPER(v_t) LIKE 'SECCI%' OR (fn_es_mayusculas(v_t) AND INSTR(v_t, ':') = 0) THEN
                cerrar_lista;
                agregar('<div class="sb-tx" style="font-size:19px;font-weight:700;letter-spacing:-.01em;color:#1d1d1f;margin:26px 0 12px">'
                     || fn_escapar_html(fn_oracion(v_t)) || '</div>');
            ELSIF UPPER(v_t) LIKE 'ESTIMAD%' THEN
                cerrar_lista;
                agregar('<p class="sb-tx" style="margin:0 0 12px;font-size:18px;font-weight:600;color:#1d1d1f">' || fn_escapar_html(v_t) || '</p>');
            ELSIF v_t LIKE '%:' THEN
                cerrar_lista;
                agregar('<div class="sb-mu" style="font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:#86868b;margin:18px 4px 8px">'
                     || fn_escapar_html(fn_oracion(RTRIM(v_t, ':'))) || '</div>');
            ELSIF v_t LIKE '(%)' THEN
                cerrar_lista;
                agregar('<p class="sb-mu" style="margin:0 0 14px;font-size:14px;font-style:italic;color:#86868b">'
                     || fn_escapar_html(SUBSTR(v_t, 2, LENGTH(v_t) - 2)) || '</p>');
            ELSIF REGEXP_LIKE(v_t, '^(- )?[^:|]{1,60}:[[:space:]]*[^[:space:]]') THEN
                -- "Etiqueta: valor | Etiqueta: valor" -> lista agrupada; cada "- " inicia otra lista
                IF v_t LIKE '- %' OR NOT v_en_lista THEN abrir_lista; END IF;
                FOR k IN 1 .. NVL(REGEXP_COUNT(v_t, '[^|]+'), 0) LOOP
                    v_parte := TRIM(REGEXP_REPLACE(REGEXP_SUBSTR(v_t, '[^|]+', 1, k), '^- ', ''));
                    IF REGEXP_LIKE(v_parte, '^[^:]{1,60}:[[:space:]]*[^[:space:]]') THEN
                        v_lbl := TRIM(SUBSTR(v_parte, 1, INSTR(v_parte, ':') - 1));
                        v_val := TRIM(SUBSTR(v_parte, INSTR(v_parte, ':') + 1));
                        fila_lista(fn_oracion(v_lbl), v_val);
                    ELSIF v_parte IS NOT NULL THEN
                        fila_lista(NULL, v_parte);
                    END IF;
                END LOOP;
            ELSIF v_t LIKE '- %' THEN
                -- Vineta
                cerrar_lista;
                agregar('<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 10px"><tr>'
                     || '<td style="vertical-align:top;padding:0 10px 0 4px;color:' || g_acento || ';font-size:16px;line-height:1.55">&#9679;</td>'
                     || '<td class="sb-tx" style="color:#1d1d1f;font-size:15px;line-height:1.55">' || fn_escapar_html(SUBSTR(v_t, 3)) || '</td></tr></table>');
            ELSE
                cerrar_lista;
                agregar('<p class="sb-tx" style="margin:0 0 14px;color:#1d1d1f">' || fn_escapar_html(v_t) || '</p>');
            END IF;
            IF v_t IS NOT NULL AND NOT es_separador(v_t) THEN v_inicio := FALSE; END IF;
        END LOOP;
        IF v_en_tabla THEN cerrar_tabla; END IF;
        cerrar_lista;

        agregar('</td></tr></table></td></tr>'
             -- Pie fuera de la tarjeta
             || '<tr><td align="center" class="sb-mu" style="padding:22px 24px 6px;font-size:12px;line-height:1.6;color:#86868b">'
             || '<b style="color:#6e6e73">Super Brunca</b> &middot; Notificaci&oacute;n autom&aacute;tica<br>'
             || 'Enviada directamente desde Oracle Database (UTL_SMTP). No responda a este correo.</td></tr>'
             || '</table></td></tr></table></body></html>');
        RETURN v_html;
    END fn_texto_a_html;

    -- Escribe un CLOB en Base64 (lineas de 76 caracteres) dentro del DATA de UTL_SMTP
    PROCEDURE pr_escribir_base64(p_conn IN OUT NOCOPY UTL_SMTP.CONNECTION, p_texto IN CLOB) IS
        v_blob   BLOB;
        v_dest   INTEGER := 1;
        v_src    INTEGER := 1;
        v_ctx    INTEGER := DBMS_LOB.DEFAULT_LANG_CTX;
        v_aviso  INTEGER;
        v_pos    INTEGER := 1;
        v_largo  INTEGER;
        v_buffer VARCHAR2(32000);
    BEGIN
        DBMS_LOB.CREATETEMPORARY(v_blob, TRUE);
        DBMS_LOB.CONVERTTOBLOB(v_blob, p_texto, DBMS_LOB.LOBMAXSIZE, v_dest, v_src,
                               NLS_CHARSET_ID('AL32UTF8'), v_ctx, v_aviso);
        v_largo := DBMS_LOB.GETLENGTH(v_blob);
        WHILE v_pos <= v_largo LOOP
            v_buffer := v_buffer || UTL_RAW.CAST_TO_VARCHAR2(
                            UTL_ENCODE.BASE64_ENCODE(DBMS_LOB.SUBSTR(v_blob, 57, v_pos))) || UTL_TCP.CRLF;
            v_pos := v_pos + 57;
            IF LENGTH(v_buffer) > 30000 THEN
                UTL_SMTP.WRITE_DATA(p_conn, v_buffer);
                v_buffer := NULL;
            END IF;
        END LOOP;
        IF v_buffer IS NOT NULL THEN UTL_SMTP.WRITE_DATA(p_conn, v_buffer); END IF;
        DBMS_LOB.FREETEMPORARY(v_blob);
    END pr_escribir_base64;

    -- Asunto codificado (RFC 2047) para que las tildes se vean bien
    FUNCTION fn_asunto_mime(p_asunto IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN '=?UTF-8?B?' || REPLACE(REPLACE(UTL_RAW.CAST_TO_VARCHAR2(UTL_ENCODE.BASE64_ENCODE(
                   UTL_I18N.STRING_TO_RAW(p_asunto, 'AL32UTF8'))), CHR(13), ''), CHR(10), '') || '?=';
    END fn_asunto_mime;

    PROCEDURE PR_ENVIAR_CORREO (
        p_destinatarios IN VARCHAR2,
        p_asunto        IN VARCHAR2,
        p_cuerpo        IN CLOB
    ) IS
        v_host        VARCHAR2(200);
        v_port        NUMBER;
        v_emisor      VARCHAR2(200);
        v_clave       VARCHAR2(200);
        v_wallet_path VARCHAR2(200) := NULL;
        v_wallet_pwd  VARCHAR2(200) := NULL;
        v_conn        UTL_SMTP.CONNECTION;
        v_lista       VARCHAR2(1000);
        v_dest        VARCHAR2(200);
        v_pos         PLS_INTEGER;
        v_exito_smtp  BOOLEAN := FALSE;
        v_para        VARCHAR2(2000);
        v_limite      VARCHAR2(70);
    BEGIN
        v_host   := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('SMTP_HOST');
        v_port   := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('SMTP_PORT');
        v_emisor := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_EMISOR');
        v_clave  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CLAVE_CORREO_EMISOR');

        BEGIN
            v_wallet_path := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('SMTP_WALLET_PATH');
        EXCEPTION WHEN OTHERS THEN v_wallet_path := NULL;
        END;
        BEGIN
            v_wallet_pwd  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('SMTP_WALLET_PWD');
        EXCEPTION WHEN OTHERS THEN v_wallet_pwd := NULL;
        END;

        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('[NOTIFICACION ORACLE UTL_SMTP]');
        DBMS_OUTPUT.PUT_LINE('  Servidor SMTP : ' || v_host || ':' || v_port || ' (Clave desencriptada con DBMS_CRYPTO)');
        DBMS_OUTPUT.PUT_LINE('  De            : ' || v_emisor);
        DBMS_OUTPUT.PUT_LINE('  Para          : ' || p_destinatarios);
        DBMS_OUTPUT.PUT_LINE('  Asunto        : ' || p_asunto);
        DBMS_OUTPUT.PUT_LINE('  Mensaje       :' || CHR(10) || SUBSTR(p_cuerpo, 1, 3000));
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------------------------');

        -- Intento de despacho directo por UTL_SMTP desde el motor Oracle con soporte TLS / SSL
        BEGIN
            IF v_port = 465 THEN
                -- Canal seguro SSL/TLS nativo (SMTPS puerto 465)
                -- El wallet (SMTP_WALLET_PATH) trae los certificados raiz de Gmail;
                -- sin el, Oracle 21c responde ORA-29024 (sql/08_Wallet_SMTP_Gmail.sh)
                v_conn := UTL_SMTP.OPEN_CONNECTION(
                    host => v_host,
                    port => v_port,
                    tx_timeout => 10,
                    wallet_path => v_wallet_path,
                    wallet_password => v_wallet_pwd,
                    secure_connection_before_smtp => TRUE
                );
            ELSE
                v_conn := UTL_SMTP.OPEN_CONNECTION(
                    host => v_host,
                    port => v_port,
                    tx_timeout => 10,
                    wallet_path => v_wallet_path,
                    wallet_password => v_wallet_pwd
                );
            END IF;

            UTL_SMTP.EHLO(v_conn, v_host);

            -- Negociacion de canal seguro STARTTLS si el puerto es 587
            IF v_port = 587 THEN
                BEGIN
                    UTL_SMTP.STARTTLS(c => v_conn, secure_host => v_host);
                    -- RFC 3207: se debe reenviar EHLO inmediatamente tras STARTTLS
                    UTL_SMTP.EHLO(v_conn, v_host);
                EXCEPTION
                    WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE('  [AVISO TLS]: STARTTLS no disponible o error TLS: ' || SUBSTR(SQLERRM, 1, 80));
                END;
            END IF;

            -- Autenticacion segura mediante UTL_SMTP.AUTH (LOGIN / PLAIN) con la clave desencriptada
            IF v_clave IS NOT NULL THEN
                UTL_SMTP.AUTH(
                    c        => v_conn,
                    username => v_emisor,
                    password => v_clave,
                    schemes  => 'LOGIN PLAIN'
                );
            END IF;

            UTL_SMTP.MAIL(v_conn, '<' || v_emisor || '>');

            v_lista := REPLACE(p_destinatarios, ';', ',') || ',';
            LOOP
                v_pos := INSTR(v_lista, ',');
                EXIT WHEN NVL(v_pos, 0) = 0;
                v_dest  := TRIM(SUBSTR(v_lista, 1, v_pos - 1));
                v_lista := SUBSTR(v_lista, v_pos + 1);
                IF v_dest IS NOT NULL THEN
                    UTL_SMTP.RCPT(v_conn, '<' || v_dest || '>');
                    v_para := v_para || CASE WHEN v_para IS NOT NULL THEN ', ' END || '<' || v_dest || '>';
                END IF;
                EXIT WHEN v_lista IS NULL;
            END LOOP;

            -- Mensaje MIME multipart/alternative: version en texto y version HTML adaptable
            -- al celular (fn_texto_a_html). Todo en UTF-8 codificado en Base64.
            v_limite := 'SuperBrunca_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF6');
            UTL_SMTP.OPEN_DATA(v_conn);
            UTL_SMTP.WRITE_DATA(v_conn,
                   'Date: ' || TO_CHAR(SYSTIMESTAMP, 'Dy, DD Mon YYYY HH24:MI:SS TZHTZM', 'NLS_DATE_LANGUAGE=AMERICAN') || UTL_TCP.CRLF
                || 'From: "Super Brunca - Oracle" <' || v_emisor || '>' || UTL_TCP.CRLF
                || 'To: ' || v_para || UTL_TCP.CRLF
                || 'Subject: ' || fn_asunto_mime(p_asunto) || UTL_TCP.CRLF
                || 'MIME-Version: 1.0' || UTL_TCP.CRLF
                || 'Content-Type: multipart/alternative; boundary="' || v_limite || '"' || UTL_TCP.CRLF || UTL_TCP.CRLF
                || '--' || v_limite || UTL_TCP.CRLF
                || 'Content-Type: text/plain; charset=UTF-8' || UTL_TCP.CRLF
                || 'Content-Transfer-Encoding: base64' || UTL_TCP.CRLF || UTL_TCP.CRLF);
            pr_escribir_base64(v_conn, NVL(p_cuerpo, ' '));
            UTL_SMTP.WRITE_DATA(v_conn,
                   UTL_TCP.CRLF || '--' || v_limite || UTL_TCP.CRLF
                || 'Content-Type: text/html; charset=UTF-8' || UTL_TCP.CRLF
                || 'Content-Transfer-Encoding: base64' || UTL_TCP.CRLF || UTL_TCP.CRLF);
            pr_escribir_base64(v_conn, fn_texto_a_html(p_asunto, p_cuerpo));
            UTL_SMTP.WRITE_DATA(v_conn, UTL_TCP.CRLF || '--' || v_limite || '--' || UTL_TCP.CRLF);
            UTL_SMTP.CLOSE_DATA(v_conn);
            UTL_SMTP.QUIT(v_conn);
            v_exito_smtp := TRUE;
            DBMS_OUTPUT.PUT_LINE('  [Estado SMTP]: Notificacion entregada al servidor de correo.');
        EXCEPTION
            WHEN OTHERS THEN
                BEGIN
                    UTL_SMTP.QUIT(v_conn);
                EXCEPTION WHEN OTHERS THEN NULL;
                END;
                -- Se registra el error real en la bitacora de errores tecnicos
                PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_ENVIAR_CORREO', SQLCODE, 
                    'Fallo al despachar correo a ' || p_destinatarios || ': ' || SQLERRM);
                DBMS_OUTPUT.PUT_LINE('  [Estado SMTP]: Fallo de conexion/autenticacion (' || SUBSTR(SQLERRM, 1, 90) || ')');
        END;

        IF v_exito_smtp THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
                p_tabla       => 'SEG_PARAMETRO',
                p_llave       => SUBSTR(p_destinatarios, 1, 50),
                p_operacion   => 'INSERT',
                p_modulo      => 'Notificaciones',
                p_descripcion => '[CORREO_ENVIADO] Asunto: ' || p_asunto || ' | Destinatario: ' || p_destinatarios
            );
        ELSE
            PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION(
                p_tabla       => 'SEG_PARAMETRO',
                p_llave       => SUBSTR(p_destinatarios, 1, 50),
                p_operacion   => 'UPDATE',
                p_modulo      => 'Notificaciones',
                p_descripcion => '[FALLO_SMTP] Error al enviar correo [' || p_asunto || '] a: ' || p_destinatarios
            );
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_ENVIAR_CORREO_GENERAL', SQLCODE, SQLERRM);
            RAISE;
    END PR_ENVIAR_CORREO;

    PROCEDURE PR_NOTIF_CLIENTES_85_CREDITO IS
        v_umbral_porc    NUMBER;
        v_correo_coord   VARCHAR2(200);
        v_cuerpo_coord   CLOB;
        v_cuerpo_cli     CLOB;
        v_contador       PLS_INTEGER := 0;

        CURSOR c_clientes_85 (p_porc NUMBER) IS
            SELECT c.ID_CLIENTE,
                   c.CODIGO_CLI,
                   NVL(pj.RAZON_SOCIAL_PEJU,
                       TRIM(pf.NOMBRE_PADR_O_PEFI)) AS NOMBRE_CLIENTE,
                   c.MONTO_MAX_CREDITO_CLI          AS LIMITE_CREDITO,
                   c.SALDO_ACTUAL_CLI               AS SALDO_PENDIENTE,
                   ROUND((c.SALDO_ACTUAL_CLI / NULLIF(c.MONTO_MAX_CREDITO_CLI, 0)) * 100, 2) AS PORC_USADO,
                   NVL((SELECT MAX(ct.VALOR_CONT)
                          FROM PER_CONTACTO ct
                         WHERE ct.ID_PERSONA = c.ID_PERSONA
                           AND ct.TIPO_CONT  = 'E'
                           AND ct.ESTADO_CONT = 'A'), 'cliente_sin_correo@superbrunca.cr') AS CORREO_CLIENTE
              FROM PER_CLIENTE c
                   LEFT JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = c.ID_PERSONA
                   LEFT JOIN (SELECT ID_PERSONA_FISICA,
                                     NOMBRE_PEFI || ' ' || APELLIDO1_PEFI || ' ' || NVL(APELLIDO2_PEFI, '') AS NOMBRE_PADR_O_PEFI
                                FROM PER_PERSONA_FISICA) pf ON pf.ID_PERSONA_FISICA = c.ID_PERSONA
             WHERE c.ESTADO_CLI = 'A'
               AND c.MONTO_MAX_CREDITO_CLI > 0
               AND (c.SALDO_ACTUAL_CLI / c.MONTO_MAX_CREDITO_CLI) * 100 >= p_porc
             ORDER BY PORC_USADO DESC;
    BEGIN
        v_umbral_porc  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('PORC_ALERTA_CREDITO_CLI');
        v_correo_coord := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR');

        v_cuerpo_coord := 'REPORTE CONSOLIDADO DE CLIENTES CON ' || v_umbral_porc || '% O MAS DE SU LIMITE DE CREDITO (CxC)' || CHR(10) ||
                          RPAD('=', 78, '=') || CHR(10) ||
                          RPAD('CODIGO', 12) || RPAD('CLIENTE', 30) || LPAD('LIMITE', 14) || LPAD('SALDO', 14) || LPAD('% USO', 8) || CHR(10) ||
                          RPAD('-', 78, '-') || CHR(10);

        FOR r IN c_clientes_85(v_umbral_porc) LOOP
            v_contador := v_contador + 1;

            -- 1) Notificacion individual al cliente
            v_cuerpo_cli := 'Estimado(a) ' || r.NOMBRE_CLIENTE || ' (' || r.CODIGO_CLI || '):' || CHR(10) ||
                            'Le informamos que su saldo actual en Cuentas por Cobrar es de CRC ' ||
                            TO_CHAR(r.SALDO_PENDIENTE, 'FM999G999G990D00') ||
                            ', lo que representa el ' || r.PORC_USADO || '% de su limite autorizado (CRC ' ||
                            TO_CHAR(r.LIMITE_CREDITO, 'FM999G999G990D00') || ').' || CHR(10) ||
                            'Por favor gestione un abono para mantener disponible su linea de credito.';

            PR_ENVIAR_CORREO(
                p_destinatarios => r.CORREO_CLIENTE,
                p_asunto        => 'Aviso de limite de credito (' || r.PORC_USADO || '% utilizado) - Super Brunca',
                p_cuerpo        => v_cuerpo_cli
            );

            -- 2) Agregar linea al consolidado del coordinador
            v_cuerpo_coord := v_cuerpo_coord ||
                              RPAD(r.CODIGO_CLI, 12) ||
                              RPAD(SUBSTR(r.NOMBRE_CLIENTE, 1, 28), 30) ||
                              LPAD(TO_CHAR(r.LIMITE_CREDITO, 'FM999G999G990D00'), 14) ||
                              LPAD(TO_CHAR(r.SALDO_PENDIENTE, 'FM999G999G990D00'), 14) ||
                              LPAD(r.PORC_USADO || '%', 8) || CHR(10);
        END LOOP;

        IF v_contador > 0 THEN
            v_cuerpo_coord := v_cuerpo_coord || RPAD('-', 78, '-') || CHR(10) ||
                              'Total de clientes en alerta (>= ' || v_umbral_porc || '%): ' || v_contador;

            PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_coord,
                p_asunto        => 'Alerta Coordinador: ' || v_contador || ' cliente(s) al ' || v_umbral_porc || '% o mas de credito',
                p_cuerpo        => v_cuerpo_coord
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('No existen clientes que superen el ' || v_umbral_porc || '% de su limite de credito.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_NOTIF_CLIENTES_85_CREDITO', SQLCODE, SQLERRM);
            RAISE;
    END PR_NOTIF_CLIENTES_85_CREDITO;

    PROCEDURE PR_NOTIF_PROVEEDORES_70_CREDITO IS
        v_umbral_porc   NUMBER;
        v_correo_ger    VARCHAR2(200);
        v_cuerpo        CLOB;
        v_contador      PLS_INTEGER := 0;
        v_total_deuda   NUMBER(14,2) := 0;

        CURSOR c_proveedores_70 (p_porc NUMBER) IS
            SELECT pr.ID_PROVEEDOR,
                   pr.CODIGO_PROVE,
                   pj.RAZON_SOCIAL_PEJU   AS NOMBRE_PROVEEDOR,
                   pr.LIMITE_CREDITO_PROVE AS LIMITE_CREDITO,
                   pr.SALDO_ACTUAL_PROVE   AS SALDO_PENDIENTE,
                   ROUND((pr.SALDO_ACTUAL_PROVE / NULLIF(pr.LIMITE_CREDITO_PROVE, 0)) * 100, 2) AS PORC_USADO
              FROM PER_PROVEEDOR pr
                   JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = pr.ID_PERSONA_JURIDICA
             WHERE pr.ESTADO_PROVE = 'A'
               AND pr.LIMITE_CREDITO_PROVE > 0
               AND (pr.SALDO_ACTUAL_PROVE / pr.LIMITE_CREDITO_PROVE) * 100 >= p_porc
             ORDER BY PORC_USADO DESC;
    BEGIN
        v_umbral_porc := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('PORC_ALERTA_CREDITO_PROV');
        v_correo_ger  := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_GERENTE');

        v_cuerpo := 'NOTIFICACION UNICA CONSOLIDADA - PROVEEDORES CON >= ' || v_umbral_porc || '% DEL LIMITE EN CUENTAS POR PAGAR' || CHR(10) ||
                    RPAD('=', 80, '=') || CHR(10) ||
                    RPAD('CODIGO', 10) || RPAD('PROVEEDOR', 32) || LPAD('LIMITE', 15) || LPAD('SALDO CXP', 15) || LPAD('% USO', 8) || CHR(10) ||
                    RPAD('-', 80, '-') || CHR(10);

        FOR r IN c_proveedores_70(v_umbral_porc) LOOP
            v_contador    := v_contador + 1;
            v_total_deuda := v_total_deuda + r.SALDO_PENDIENTE;

            v_cuerpo := v_cuerpo ||
                        RPAD(r.CODIGO_PROVE, 10) ||
                        RPAD(SUBSTR(r.NOMBRE_PROVEEDOR, 1, 30), 32) ||
                        LPAD(TO_CHAR(r.LIMITE_CREDITO, 'FM999G999G990D00'), 15) ||
                        LPAD(TO_CHAR(r.SALDO_PENDIENTE, 'FM999G999G990D00'), 15) ||
                        LPAD(r.PORC_USADO || '%', 8) || CHR(10);
        END LOOP;

        IF v_contador > 0 THEN
            v_cuerpo := v_cuerpo || RPAD('-', 80, '-') || CHR(10) ||
                        'Proveedores en alerta: ' || v_contador ||
                        ' | Saldo total adeudado en alerta: CRC ' || TO_CHAR(v_total_deuda, 'FM999G999G990D00');

            PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_ger,
                p_asunto        => 'Alerta Gerencia: Proveedores al ' || v_umbral_porc || '% o mas del limite en Cuentas por Pagar',
                p_cuerpo        => v_cuerpo
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('Ningun proveedor supera actualmente el ' || v_umbral_porc || '% de su limite de credito.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_NOTIF_PROVEEDORES_70_CREDITO', SQLCODE, SQLERRM);
            RAISE;
    END PR_NOTIF_PROVEEDORES_70_CREDITO;

    PROCEDURE PR_NOTIF_CLIENTES_MOROSOS IS
        v_meses         NUMBER;
        v_destinatarios VARCHAR2(400);
        v_cuerpo        CLOB;
        v_contador      PLS_INTEGER := 0;

        CURSOR c_morosos (p_meses NUMBER) IS
            SELECT c.ID_CLIENTE,
                   c.CODIGO_CLI,
                   NVL(pj.RAZON_SOCIAL_PEJU,
                       pf.NOMBRE_PEFI || ' ' || pf.APELLIDO1_PEFI) AS NOMBRE_CLIENTE,
                   c.SALDO_ACTUAL_CLI                              AS SALDO_PENDIENTE,
                   MAX(NVL(cc.FECHA_ULT_ABONO_CUCO, cc.FECHA_EMISION_CUCO)) AS ULTIMO_MOV_PAGO,
                   TRUNC(SYSDATE) - TRUNC(MAX(NVL(cc.FECHA_ULT_ABONO_CUCO, cc.FECHA_EMISION_CUCO))) AS DIAS_SIN_PAGO
              FROM PER_CLIENTE c
                   JOIN VEN_CUENTA_COBRAR cc ON cc.ID_CLIENTE = c.ID_CLIENTE
                   LEFT JOIN PER_PERSONA_JURIDICA pj ON pj.ID_PERSONA_JURIDICA = c.ID_PERSONA
                   LEFT JOIN PER_PERSONA_FISICA pf   ON pf.ID_PERSONA_FISICA   = c.ID_PERSONA
             WHERE c.SALDO_ACTUAL_CLI > 0
               AND cc.SALDO_CUCO > 0
               AND cc.ESTADO_CUCO IN ('P','A')
             GROUP BY c.ID_CLIENTE, c.CODIGO_CLI, pj.RAZON_SOCIAL_PEJU,
                      pf.NOMBRE_PEFI, pf.APELLIDO1_PEFI, c.SALDO_ACTUAL_CLI
            HAVING MAX(NVL(cc.FECHA_ULT_ABONO_CUCO, cc.FECHA_EMISION_CUCO)) <= ADD_MONTHS(TRUNC(SYSDATE), -p_meses)
             ORDER BY DIAS_SIN_PAGO DESC;
    BEGIN
        v_meses         := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_NUM('MESES_MOROSIDAD_CLIENTE');
        v_destinatarios := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_GERENTE') || ',' ||
                           PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR');

        v_cuerpo := 'CLIENTES CON SALDO PENDIENTE Y ULTIMO PAGO CON MAS DE ' || v_meses || ' MES(ES) DE ANTIGUEDAD' || CHR(10) ||
                    RPAD('=', 78, '=') || CHR(10) ||
                    RPAD('CODIGO', 12) || RPAD('CLIENTE', 30) || LPAD('SALDO PEND.', 14) || LPAD('ULT. PAGO', 12) || LPAD('DIAS', 8) || CHR(10) ||
                    RPAD('-', 78, '-') || CHR(10);

        FOR r IN c_morosos(v_meses) LOOP
            v_contador := v_contador + 1;
            v_cuerpo := v_cuerpo ||
                        RPAD(r.CODIGO_CLI, 12) ||
                        RPAD(SUBSTR(r.NOMBRE_CLIENTE, 1, 28), 30) ||
                        LPAD(TO_CHAR(r.SALDO_PENDIENTE, 'FM999G999G990D00'), 14) ||
                        LPAD(TO_CHAR(r.ULTIMO_MOV_PAGO, 'YYYY-MM-DD'), 12) ||
                        LPAD(r.DIAS_SIN_PAGO, 8) || CHR(10);
        END LOOP;

        IF v_contador > 0 THEN
            v_cuerpo := v_cuerpo || RPAD('-', 78, '-') || CHR(10) ||
                        'Total de clientes en morosidad (> ' || v_meses || ' mes): ' || v_contador;

            PR_ENVIAR_CORREO(
                p_destinatarios => v_destinatarios,
                p_asunto        => 'Alerta Gerencia y Coordinador: ' || v_contador || ' cliente(s) con pago atrasado (> ' || v_meses || ' mes)',
                p_cuerpo        => v_cuerpo
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('No existen clientes con saldo pendiente y ultimo pago mayor a ' || v_meses || ' mes(es).');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_NOTIF_CLIENTES_MOROSOS', SQLCODE, SQLERRM);
            RAISE;
    END PR_NOTIF_CLIENTES_MOROSOS;

    PROCEDURE PR_NOTIF_PRODUCTOS_VENCIDOS IS
        v_correo_coord   VARCHAR2(200);
        v_cuerpo         CLOB;
        v_contador       PLS_INTEGER  := 0;
        v_total_unidades NUMBER(14,3) := 0;
        v_total_costo    NUMBER(14,2) := 0;

        CURSOR c_vencidos IS
            SELECT b.NOMBRE_BODE,
                   p.CODIGO_PROD,
                   p.NOMBRE_PROD,
                   l.NUMERO_LOTE,
                   l.FECHA_VENCIM_LOTE,
                   e.CANTIDAD_EXIS,
                   p.PRECIO_COSTO_PROD,
                   ROUND(e.CANTIDAD_EXIS * p.PRECIO_COSTO_PROD, 2) AS SUBTOTAL_COSTO
              FROM INV_EXISTENCIA e
                   JOIN PRO_LOTE l     ON l.ID_LOTE     = e.ID_LOTE
                                      AND l.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN PRO_PRODUCTO p ON p.ID_PRODUCTO = e.ID_PRODUCTO
                   JOIN INV_BODEGA b   ON b.ID_BODEGA   = e.ID_BODEGA
             WHERE l.FECHA_VENCIM_LOTE < TRUNC(SYSDATE)
               AND e.CANTIDAD_EXIS > 0
             ORDER BY l.FECHA_VENCIM_LOTE ASC;
    BEGIN
        v_correo_coord := PKG_SEG_SEGURIDAD.FN_OBTENER_PARAM_TEXTO('CORREO_COORDINADOR');

        v_cuerpo := 'REPORTE DE PRODUCTOS VENCIDOS EN BODEGA (PARA DEFINICION DEL COORDINADOR)' || CHR(10) ||
                    RPAD('=', 86, '=') || CHR(10) ||
                    RPAD('PRODUCTO', 24) || RPAD('LOTE', 12) || RPAD('VENCIO', 12) ||
                    LPAD('CANTIDAD', 10) || LPAD('COSTO UNIT', 12) || LPAD('SUBTOTAL', 14) || CHR(10) ||
                    RPAD('-', 86, '-') || CHR(10);

        FOR r IN c_vencidos LOOP
            v_contador       := v_contador + 1;
            v_total_unidades := v_total_unidades + r.CANTIDAD_EXIS;
            v_total_costo    := v_total_costo    + r.SUBTOTAL_COSTO;

            v_cuerpo := v_cuerpo ||
                        RPAD(SUBSTR(r.NOMBRE_PROD, 1, 22), 24) ||
                        RPAD(r.NUMERO_LOTE, 12) ||
                        RPAD(TO_CHAR(r.FECHA_VENCIM_LOTE, 'YYYY-MM-DD'), 12) ||
                        LPAD(TO_CHAR(r.CANTIDAD_EXIS, 'FM999G990D00'), 10) ||
                        LPAD(TO_CHAR(r.PRECIO_COSTO_PROD, 'FM999G990D00'), 12) ||
                        LPAD(TO_CHAR(r.SUBTOTAL_COSTO, 'FM999G999G990D00'), 14) || CHR(10);
        END LOOP;

        IF v_contador > 0 THEN
            v_cuerpo := v_cuerpo || RPAD('=', 86, '=') || CHR(10) ||
                        'TOTAL DE LOTES VENCIDOS   : ' || v_contador || CHR(10) ||
                        'TOTAL DE UNIDADES VENCIDAS: ' || TO_CHAR(v_total_unidades, 'FM999G990D00') || CHR(10) ||
                        'VALOR TOTAL EN INVENTARIO : CRC ' || TO_CHAR(v_total_costo, 'FM999G999G990D00');

            PR_ENVIAR_CORREO(
                p_destinatarios => v_correo_coord,
                p_asunto        => 'Alerta Coordinador: Lista de Productos Vencidos (Total CRC ' || TO_CHAR(v_total_costo, 'FM999G999G990D00') || ')',
                p_cuerpo        => v_cuerpo
            );
        ELSE
            DBMS_OUTPUT.PUT_LINE('No se encontraron lotes vencidos con existencia positiva.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('PKG_ADM_NOTIFICACION', 'PR_NOTIF_PRODUCTOS_VENCIDOS', SQLCODE, SQLERRM);
            RAISE;
    END PR_NOTIF_PRODUCTOS_VENCIDOS;

    FUNCTION FN_VISTA_PREVIA_HTML (
        p_asunto IN VARCHAR2,
        p_cuerpo IN CLOB
    ) RETURN CLOB IS
    BEGIN
        RETURN fn_texto_a_html(p_asunto, p_cuerpo);
    END FN_VISTA_PREVIA_HTML;

END PKG_ADM_NOTIFICACION;
/
SHOW ERRORS PACKAGE BODY PKG_ADM_NOTIFICACION;

PROMPT === FIN DE 02_Paquetes_Seguridad_Auditoria_Notificaciones.sql ===
