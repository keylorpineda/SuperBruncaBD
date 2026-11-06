-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  04_Triggers_Negocio_y_Auditoria.sql
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c / 23ai / 26ai Free
-- DESCRIPCION:
--   Implementacion de disparadores (triggers) de reglas de negocio automatizadas
--   y disparadores de auditoria profunda en las 7 tablas principales del sistema.
-- ============================================================================

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET DEFINE OFF;
WHENEVER SQLERROR CONTINUE;

-- Conectar dinamicamente al PDB y fijar esquema
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
        DBMS_OUTPUT.PUT_LINE('[SESION] Conectado al PDB: ' || v_pdb);
    END IF;
END;
/

ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;

PROMPT ============================================================================
PROMPT 1. COMPILACION DE DISPARADORES DE NEGOCIO AUTOMATIZADOS
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 TRG_VEN_FACTURA_CRED_BIU
-- Disparador BEFORE INSERT OR UPDATE ON VEN_FACTURA
-- Valida que el cliente no supere su limite de credito autorizado.
-- NOTA TECNICA: TOTAL_FAVE es una columna VIRTUAL (GENERATED ALWAYS AS).
-- En un disparador BEFORE, las columnas virtuales llegan como NULL.
-- Por ello, el total se calcula explicitamente como SUBTOTAL - DESCUENTO + IMPUESTO.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_FACTURA_CRED_BIU
BEFORE INSERT OR UPDATE OF SUBTOTAL_FAVE, DESCUENTO_FAVE, IMPUESTO_FAVE, ES_CREDITO_FAVE, ESTADO_FAVE ON VEN_FACTURA
FOR EACH ROW
DECLARE
    v_saldo_actual  NUMBER(14,2);
    v_monto_max     NUMBER(14,2);
    v_estado_cli    VARCHAR2(1);
    v_codigo_cli    VARCHAR2(30);
    v_total_new     NUMBER(14,2);
    v_total_old     NUMBER(14,2) := 0;
    v_diferencia    NUMBER(14,2) := 0;
BEGIN
    IF :NEW.ES_CREDITO_FAVE = 'S' OR :NEW.ESTADO_FAVE = 'P' THEN
        SELECT NVL(SALDO_ACTUAL_CLI, 0), NVL(MONTO_MAX_CREDITO_CLI, 0), ESTADO_CLI, CODIGO_CLI
          INTO v_saldo_actual, v_monto_max, v_estado_cli, v_codigo_cli
          FROM PER_CLIENTE
         WHERE ID_CLIENTE = :NEW.ID_CLIENTE;

        IF v_estado_cli <> 'A' THEN
            RAISE_APPLICATION_ERROR(-20011, 'El cliente "' || v_codigo_cli || '" no esta activo para emitirle facturas a credito.');
        END IF;

        -- Calculo explicito del total para evitar valor NULL de columna virtual en BEFORE trigger
        v_total_new := NVL(:NEW.SUBTOTAL_FAVE, 0) - NVL(:NEW.DESCUENTO_FAVE, 0) + NVL(:NEW.IMPUESTO_FAVE, 0);

        IF INSERTING THEN
            v_diferencia := v_total_new;
        ELSIF UPDATING THEN
            v_total_old  := NVL(:OLD.SUBTOTAL_FAVE, 0) - NVL(:OLD.DESCUENTO_FAVE, 0) + NVL(:OLD.IMPUESTO_FAVE, 0);
            v_diferencia := v_total_new - v_total_old;
        END IF;

        IF v_diferencia > 0 AND (v_saldo_actual + v_diferencia) > v_monto_max THEN
            RAISE_APPLICATION_ERROR(-20010, 'Limite de credito excedido para el cliente ' || v_codigo_cli || 
                                           '. Maximo: C' || TO_CHAR(v_monto_max, '999,999,990.00') || 
                                           ', Saldo actual: C' || TO_CHAR(v_saldo_actual, '999,999,990.00') || 
                                           ', Monto solicitado: C' || TO_CHAR(v_diferencia, '999,999,990.00'));
        END IF;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20013, 'El cliente indicado no existe en el catalogo de personas.');
END;
/
SHOW ERRORS TRIGGER TRG_VEN_FACTURA_CRED_BIU;

-- ----------------------------------------------------------------------------
-- 1.2 TRG_VEN_FACTURA_CRED_AI
-- Disparador AFTER INSERT ON VEN_FACTURA
-- Aumenta el saldo deudor del cliente y asegura la creacion de la cuenta por cobrar
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_FACTURA_CRED_AI
AFTER INSERT ON VEN_FACTURA
FOR EACH ROW
DECLARE
    v_plazo_dias   NUMBER := 30;
    v_cant_cuco    NUMBER := 0;
    v_monto_total  NUMBER(14,2);
BEGIN
    IF :NEW.ES_CREDITO_FAVE = 'S' OR :NEW.ESTADO_FAVE = 'P' THEN
        v_monto_total := NVL(:NEW.TOTAL_FAVE, NVL(:NEW.SUBTOTAL_FAVE, 0) - NVL(:NEW.DESCUENTO_FAVE, 0) + NVL(:NEW.IMPUESTO_FAVE, 0));

        -- 1. Aumentar el saldo actual del cliente
        UPDATE PER_CLIENTE
           SET SALDO_ACTUAL_CLI = NVL(SALDO_ACTUAL_CLI, 0) + v_monto_total,
               USUARIO_MOD_CLI = USER,
               FECHA_MOD_CLI = SYSTIMESTAMP
         WHERE ID_CLIENTE = :NEW.ID_CLIENTE;

        -- 2. Obtener plazo acordado con el cliente
        BEGIN
            SELECT NVL(DIAS_CREDITO_CLI, 30)
              INTO v_plazo_dias
              FROM PER_CLIENTE
             WHERE ID_CLIENTE = :NEW.ID_CLIENTE;
        EXCEPTION
            WHEN OTHERS THEN v_plazo_dias := 30;
        END;

        -- 3. Verificar si ya existe registro en VEN_CUENTA_COBRAR
        SELECT COUNT(*)
          INTO v_cant_cuco
          FROM VEN_CUENTA_COBRAR
         WHERE ID_FACTURA_VENTA = :NEW.ID_FACTURA_VENTA;

        IF v_cant_cuco = 0 THEN
            INSERT INTO VEN_CUENTA_COBRAR (
                ID_CUENTA_COBRAR,
                ID_FACTURA_VENTA,
                ID_CLIENTE,
                FECHA_EMISION_CUCO,
                FECHA_VENCIM_CUCO,
                MONTO_ORIGINAL_CUCO,
                MONTO_ABONADO_CUCO,
                SALDO_CUCO,
                ESTADO_CUCO,
                USUARIO_CREA_CUCO,
                FECHA_CREA_CUCO
            ) VALUES (
                SEQ_VEN_CUENTA_COBRAR.NEXTVAL,
                :NEW.ID_FACTURA_VENTA,
                :NEW.ID_CLIENTE,
                :NEW.FECHA_FAVE,
                NVL(:NEW.FECHA_VENCIM_FAVE, :NEW.FECHA_FAVE + v_plazo_dias),
                v_monto_total,
                0,
                v_monto_total,
                'P',
                USER,
                SYSTIMESTAMP
            );
        END IF;

        -- 4. Registrar operacion en bitacora
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'VEN_FACTURA',
            p_modulo      => 'VENTAS',
            p_operacion   => 'INSERT',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_VENTA),
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => :NEW.ID_SUCURSAL,
            p_descripcion => '[CREDITO_AUTO] Factura a credito registrada. Saldo cliente aumentado en C' || TO_CHAR(v_monto_total, '999,999,990.00')
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_VEN_FACTURA_CRED_AI;

-- ----------------------------------------------------------------------------
-- 1.3 TRG_COM_FACTURA_CRED_BIU
-- Disparador BEFORE INSERT OR UPDATE ON COM_FACTURA_COMPRA
-- Valida que el credito otorgado por el proveedor no sobrepase el limite negociado.
-- NOTA TECNICA: TOTAL_FACO es una columna VIRTUAL (GENERATED ALWAYS AS).
-- En un disparador BEFORE, las columnas virtuales llegan como NULL.
-- Por ello, el total se calcula explicitamente como SUBTOTAL - DESCUENTO + IMPUESTO.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_FACTURA_CRED_BIU
BEFORE INSERT OR UPDATE OF SUBTOTAL_FACO, DESCUENTO_FACO, IMPUESTO_FACO, ES_CREDITO_FACO, ESTADO_FACO ON COM_FACTURA_COMPRA
FOR EACH ROW
DECLARE
    v_saldo_actual  NUMBER(14,2);
    v_limite_max    NUMBER(14,2);
    v_estado_prov   VARCHAR2(1);
    v_codigo_prov   VARCHAR2(30);
    v_total_new     NUMBER(14,2);
    v_total_old     NUMBER(14,2) := 0;
    v_diferencia    NUMBER(14,2) := 0;
BEGIN
    IF :NEW.ES_CREDITO_FACO = 'S' OR :NEW.ESTADO_FACO = 'P' THEN
        SELECT NVL(SALDO_ACTUAL_PROVE, 0), NVL(LIMITE_CREDITO_PROVE, 0), ESTADO_PROVE, CODIGO_PROVE
          INTO v_saldo_actual, v_limite_max, v_estado_prov, v_codigo_prov
          FROM PER_PROVEEDOR
         WHERE ID_PROVEEDOR = :NEW.ID_PROVEEDOR;

        IF v_estado_prov <> 'A' THEN
            RAISE_APPLICATION_ERROR(-20014, 'El proveedor "' || v_codigo_prov || '" se encuentra inactivo para compras a credito.');
        END IF;

        -- Calculo explicito del total para evitar valor NULL de columna virtual en BEFORE trigger
        v_total_new := NVL(:NEW.SUBTOTAL_FACO, 0) - NVL(:NEW.DESCUENTO_FACO, 0) + NVL(:NEW.IMPUESTO_FACO, 0);

        IF INSERTING THEN
            v_diferencia := v_total_new;
        ELSIF UPDATING THEN
            v_total_old  := NVL(:OLD.SUBTOTAL_FACO, 0) - NVL(:OLD.DESCUENTO_FACO, 0) + NVL(:OLD.IMPUESTO_FACO, 0);
            v_diferencia := v_total_new - v_total_old;
        END IF;

        IF v_limite_max > 0 AND v_diferencia > 0 AND (v_saldo_actual + v_diferencia) > v_limite_max THEN
            RAISE_APPLICATION_ERROR(-20015, 'Limite de credito otorgado por proveedor ' || v_codigo_prov || 
                                           ' excedido. Limite: C' || TO_CHAR(v_limite_max, '999,999,990.00') || 
                                           ', Saldo pendiente: C' || TO_CHAR(v_saldo_actual, '999,999,990.00') || 
                                           ', Monto factura: C' || TO_CHAR(v_diferencia, '999,999,990.00'));
        END IF;
    END IF;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20016, 'El proveedor indicado no existe en el catalogo de proveedores.');
END;
/
SHOW ERRORS TRIGGER TRG_COM_FACTURA_CRED_BIU;

-- ----------------------------------------------------------------------------
-- 1.4 TRG_COM_FACTURA_CRED_AI
-- Disparador AFTER INSERT ON COM_FACTURA_COMPRA
-- Aumenta saldo pendiente con el proveedor y asegura cuenta por pagar
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_FACTURA_CRED_AI
AFTER INSERT ON COM_FACTURA_COMPRA
FOR EACH ROW
DECLARE
    v_plazo_dias   NUMBER := 30;
    v_cant_cupa    NUMBER := 0;
    v_monto_total  NUMBER(14,2);
BEGIN
    IF :NEW.ES_CREDITO_FACO = 'S' OR :NEW.ESTADO_FACO = 'P' THEN
        v_monto_total := NVL(:NEW.TOTAL_FACO, NVL(:NEW.SUBTOTAL_FACO, 0) - NVL(:NEW.DESCUENTO_FACO, 0) + NVL(:NEW.IMPUESTO_FACO, 0));

        -- 1. Aumentar saldo pendiente al proveedor
        UPDATE PER_PROVEEDOR
           SET SALDO_ACTUAL_PROVE = NVL(SALDO_ACTUAL_PROVE, 0) + v_monto_total,
               USUARIO_MOD_PROVE = USER,
               FECHA_MOD_PROVE = SYSTIMESTAMP
         WHERE ID_PROVEEDOR = :NEW.ID_PROVEEDOR;

        -- 2. Plazo credito del proveedor
        BEGIN
            SELECT NVL(DIAS_CREDITO_PROVE, 30)
              INTO v_plazo_dias
              FROM PER_PROVEEDOR
             WHERE ID_PROVEEDOR = :NEW.ID_PROVEEDOR;
        EXCEPTION
            WHEN OTHERS THEN v_plazo_dias := 30;
        END;

        -- 3. Crear cuenta por pagar si no existe previamente
        SELECT COUNT(*)
          INTO v_cant_cupa
          FROM COM_CUENTA_PAGAR
         WHERE ID_FACTURA_COMPRA = :NEW.ID_FACTURA_COMPRA;

        IF v_cant_cupa = 0 THEN
            INSERT INTO COM_CUENTA_PAGAR (
                ID_CUENTA_PAGAR,
                ID_FACTURA_COMPRA,
                ID_PROVEEDOR,
                FECHA_EMISION_CUPA,
                FECHA_VENCIM_CUPA,
                MONTO_ORIGINAL_CUPA,
                MONTO_ABONADO_CUPA,
                SALDO_CUPA,
                ESTADO_CUPA,
                USUARIO_CREA_CUPA,
                FECHA_CREA_CUPA
            ) VALUES (
                SEQ_COM_CUENTA_PAGAR.NEXTVAL,
                :NEW.ID_FACTURA_COMPRA,
                :NEW.ID_PROVEEDOR,
                :NEW.FECHA_FACO,
                NVL(:NEW.FECHA_VENCIM_FACO, :NEW.FECHA_FACO + v_plazo_dias),
                v_monto_total,
                0,
                v_monto_total,
                'P',
                USER,
                SYSTIMESTAMP
            );
        END IF;

        -- 4. Registro de bitacora
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_modulo      => 'COMPRAS',
            p_operacion   => 'INSERT',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_COMPRA),
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => NULL,
            p_descripcion => '[CREDITO_AUTO] Compra a credito registrada. Saldo con proveedor aumentado en C' || TO_CHAR(v_monto_total, '999,999,990.00')
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_COM_FACTURA_CRED_AI;

-- ----------------------------------------------------------------------------
-- 1.5 TRG_VEN_ABONO_SALDO_AI
-- Disparador AFTER INSERT ON VEN_ABONO_COBRAR
-- Actualiza saldo de cuenta por cobrar, saldo de cliente y si queda en 0
-- cancela automaticamente la cuenta y la factura (cambio de 'P' a 'C')
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_ABONO_SALDO_AI
AFTER INSERT ON VEN_ABONO_COBRAR
FOR EACH ROW
DECLARE
    v_id_cuenta    NUMBER;
    v_id_cliente   NUMBER;
    v_saldo_actual NUMBER(14,2);
    v_nuevo_saldo  NUMBER(14,2);
    v_nuevo_estado VARCHAR2(1);
BEGIN
    -- 1. Obtener datos actuales de la cuenta por cobrar asociada a la factura
    BEGIN
        SELECT ID_CUENTA_COBRAR, ID_CLIENTE, SALDO_CUCO
          INTO v_id_cuenta, v_id_cliente, v_saldo_actual
          FROM VEN_CUENTA_COBRAR
         WHERE ID_FACTURA_VENTA = :NEW.ID_FACTURA_VENTA;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;

    v_nuevo_saldo := GREATEST(0, v_saldo_actual - :NEW.MONTO_ABCO);
    
    IF v_nuevo_saldo = 0 THEN
        v_nuevo_estado := 'C'; -- Cancelada totalmente
    ELSE
        v_nuevo_estado := 'A'; -- Abonada parcialmente
    END IF;

    -- 2. Actualizar saldo y estado en la cuenta por cobrar
    UPDATE VEN_CUENTA_COBRAR
       SET SALDO_CUCO = v_nuevo_saldo,
           MONTO_ABONADO_CUCO = MONTO_ABONADO_CUCO + :NEW.MONTO_ABCO,
           FECHA_ULT_ABONO_CUCO = :NEW.FECHA_ABCO,
           ESTADO_CUCO = v_nuevo_estado,
           USUARIO_MOD_CUCO = USER,
           FECHA_MOD_CUCO = SYSTIMESTAMP
     WHERE ID_CUENTA_COBRAR = v_id_cuenta;

    -- 3. Disminuir saldo actual del cliente
    UPDATE PER_CLIENTE
       SET SALDO_ACTUAL_CLI = GREATEST(0, NVL(SALDO_ACTUAL_CLI, 0) - :NEW.MONTO_ABCO),
           USUARIO_MOD_CLI = USER,
           FECHA_MOD_CLI = SYSTIMESTAMP
     WHERE ID_CLIENTE = v_id_cliente;

    -- 4. Si la cuenta fue cancelada en su totalidad, actualizar estado de factura a 'C'
    IF v_nuevo_estado = 'C' THEN
        UPDATE VEN_FACTURA
           SET ESTADO_FAVE = 'C',
               USUARIO_MOD_FAVE = USER,
               FECHA_MOD_FAVE = SYSTIMESTAMP
         WHERE ID_FACTURA_VENTA = :NEW.ID_FACTURA_VENTA
           AND ESTADO_FAVE <> 'C';

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'VEN_FACTURA',
            p_modulo      => 'VENTAS',
            p_operacion   => 'UPDATE',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_VENTA),
            p_descripcion => '[CANCELACION_AUTO] Factura cancelada automaticamente tras liquidacion de cuenta por cobrar #' || v_id_cuenta
        );
    END IF;

    -- 5. Registrar abono en bitacora
    PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
        p_tabla       => 'VEN_ABONO_COBRAR',
        p_modulo      => 'VENTAS',
        p_operacion   => 'INSERT',
        p_llave       => TO_CHAR(:NEW.ID_ABONO_COBRAR),
        p_descripcion => '[ABONO] Abono de C' || TO_CHAR(:NEW.MONTO_ABCO, '999,999,990.00') || ' aplicado a cuenta #' || v_id_cuenta || '. Nuevo saldo: C' || TO_CHAR(v_nuevo_saldo, '999,999,990.00')
    );
END;
/
SHOW ERRORS TRIGGER TRG_VEN_ABONO_SALDO_AI;

-- ----------------------------------------------------------------------------
-- 1.6 TRG_COM_ABONO_SALDO_AI
-- Disparador AFTER INSERT ON COM_ABONO_PAGAR
-- Actualiza saldo de cuenta por pagar, saldo de proveedor y si queda en 0
-- cancela automaticamente la cuenta y la factura de compra (cambio de 'P' a 'C')
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_ABONO_SALDO_AI
AFTER INSERT ON COM_ABONO_PAGAR
FOR EACH ROW
DECLARE
    v_id_cuenta      NUMBER;
    v_id_proveedor   NUMBER;
    v_saldo_actual   NUMBER(14,2);
    v_nuevo_saldo    NUMBER(14,2);
    v_nuevo_estado   VARCHAR2(1);
BEGIN
    -- 1. Obtener datos actuales de la cuenta por pagar asociada a la compra
    BEGIN
        SELECT ID_CUENTA_PAGAR, ID_PROVEEDOR, SALDO_CUPA
          INTO v_id_cuenta, v_id_proveedor, v_saldo_actual
          FROM COM_CUENTA_PAGAR
         WHERE ID_FACTURA_COMPRA = :NEW.ID_FACTURA_COMPRA;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN;
    END;

    v_nuevo_saldo := GREATEST(0, v_saldo_actual - :NEW.MONTO_ABPA);
    
    IF v_nuevo_saldo = 0 THEN
        v_nuevo_estado := 'C'; -- Cancelada
    ELSE
        v_nuevo_estado := 'A'; -- Abonada parcialmente
    END IF;

    -- 2. Actualizar saldo y estado en la cuenta por pagar
    UPDATE COM_CUENTA_PAGAR
       SET SALDO_CUPA = v_nuevo_saldo,
           MONTO_ABONADO_CUPA = MONTO_ABONADO_CUPA + :NEW.MONTO_ABPA,
           FECHA_ULT_ABONO_CUPA = :NEW.FECHA_ABPA,
           ESTADO_CUPA = v_nuevo_estado,
           USUARIO_MOD_CUPA = USER,
           FECHA_MOD_CUPA = SYSTIMESTAMP
     WHERE ID_CUENTA_PAGAR = v_id_cuenta;

    -- 3. Disminuir saldo pendiente con el proveedor
    UPDATE PER_PROVEEDOR
       SET SALDO_ACTUAL_PROVE = GREATEST(0, NVL(SALDO_ACTUAL_PROVE, 0) - :NEW.MONTO_ABPA),
           USUARIO_MOD_PROVE = USER,
           FECHA_MOD_PROVE = SYSTIMESTAMP
     WHERE ID_PROVEEDOR = v_id_proveedor;

    -- 4. Si la cuenta fue cancelada en su totalidad, actualizar estado de factura compra a 'C'
    IF v_nuevo_estado = 'C' THEN
        UPDATE COM_FACTURA_COMPRA
           SET ESTADO_FACO = 'C',
               USUARIO_MOD_FACO = USER,
               FECHA_MOD_FACO = SYSTIMESTAMP
         WHERE ID_FACTURA_COMPRA = :NEW.ID_FACTURA_COMPRA
           AND ESTADO_FACO <> 'C';

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_modulo      => 'COMPRAS',
            p_operacion   => 'UPDATE',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_COMPRA),
            p_descripcion => '[CANCELACION_AUTO] Factura compra cancelada automaticamente tras liquidacion de cuenta por pagar #' || v_id_cuenta
        );
    END IF;

    -- 5. Registrar abono en bitacora
    PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
        p_tabla       => 'COM_ABONO_PAGAR',
        p_modulo      => 'COMPRAS',
        p_operacion   => 'INSERT',
        p_llave       => TO_CHAR(:NEW.ID_ABONO_PAGAR),
        p_descripcion => '[ABONO] Abono a proveedor de C' || TO_CHAR(:NEW.MONTO_ABPA, '999,999,990.00') || ' aplicado a cuenta #' || v_id_cuenta || '. Nuevo saldo: C' || TO_CHAR(v_nuevo_saldo, '999,999,990.00')
    );
END;
/
SHOW ERRORS TRIGGER TRG_COM_ABONO_SALDO_AI;

-- ----------------------------------------------------------------------------
-- 1.7 TRG_VEN_FACTURA_DET_INV_AI
-- Disparador AFTER INSERT ON VEN_FACTURA_DET
-- Descuenta existencias del inventario formalmente via PKG_INV_GESTION (con bloqueo
-- FOR UPDATE WAIT, trazabilidad por lote y generacion automatica de Kardex).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_FACTURA_DET_INV_AI
AFTER INSERT ON VEN_FACTURA_DET
FOR EACH ROW
DECLARE
    v_id_sucursal NUMBER;
    v_id_usuario  NUMBER;
    v_id_bodega   NUMBER;
BEGIN
    -- 1. Obtener sucursal y usuario de la factura padre
    SELECT ID_SUCURSAL, ID_USUARIO
      INTO v_id_sucursal, v_id_usuario
      FROM VEN_FACTURA
     WHERE ID_FACTURA_VENTA = :NEW.ID_FACTURA_VENTA;

    -- 2. Obtener bodega principal de la sucursal
    BEGIN
        SELECT ID_BODEGA
          INTO v_id_bodega
          FROM INV_BODEGA
         WHERE ID_SUCURSAL = v_id_sucursal
           AND ESTADO_BODE = 'A'
           AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            SELECT ID_BODEGA
              INTO v_id_bodega
              FROM INV_BODEGA
             WHERE ESTADO_BODE = 'A'
               AND ROWNUM = 1;
    END;

    -- 3. Descontar existencias formalmente mediante PKG_INV_GESTION
    IF :NEW.ID_PRODUCTO IS NOT NULL THEN
        PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA (
            p_id_bodega      => v_id_bodega,
            p_id_producto    => :NEW.ID_PRODUCTO,
            p_id_lote        => :NEW.ID_LOTE,
            p_cantidad       => :NEW.CANTIDAD_FVDE,
            p_es_entrada     => 'N',
            p_tipo_movi      => 'VENTA',
            p_id_usuario     => v_id_usuario,
            p_documento_ref  => 'FAC-VTA-' || :NEW.ID_FACTURA_VENTA,
            p_registrar_kard => 'S'
        );

        -- 4. Otorgamiento automatico de acciones para marcas patrocinadoras
        PKG_PRM_MERCADEO.PR_OTORGAR_ACCIONES_LINEA (
            p_id_factura_venta => :NEW.ID_FACTURA_VENTA,
            p_id_producto      => :NEW.ID_PRODUCTO,
            p_cantidad         => :NEW.CANTIDAD_FVDE
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_VEN_FACTURA_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.8 TRG_COM_FACTURA_DET_INV_AI
-- Disparador AFTER INSERT ON COM_FACTURA_COMPRA_DET
-- Aumenta existencias de inventario formalmente via PKG_INV_GESTION (con kardex,
-- lote y actualizacion de costo si difiere del actual).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_FACTURA_DET_INV_AI
AFTER INSERT ON COM_FACTURA_COMPRA_DET
FOR EACH ROW
DECLARE
    v_id_bodega     NUMBER;
    v_id_usuario    NUMBER;
    v_costo_actual  NUMBER(14,2);
BEGIN
    -- 1. Obtener bodega y usuario de la factura de compra
    SELECT ID_BODEGA, ID_USUARIO
      INTO v_id_bodega, v_id_usuario
      FROM COM_FACTURA_COMPRA
     WHERE ID_FACTURA_COMPRA = :NEW.ID_FACTURA_COMPRA;

    -- 2. Aumentar stock de inventario formalmente via PKG_INV_GESTION
    IF :NEW.ID_PRODUCTO IS NOT NULL THEN
        PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA (
            p_id_bodega      => v_id_bodega,
            p_id_producto    => :NEW.ID_PRODUCTO,
            p_id_lote        => :NEW.ID_LOTE,
            p_cantidad       => :NEW.CANTIDAD_FCDE,
            p_es_entrada     => 'S',
            p_tipo_movi      => 'COMPRA',
            p_id_usuario     => v_id_usuario,
            p_documento_ref  => 'FAC-COM-' || :NEW.ID_FACTURA_COMPRA,
            p_registrar_kard => 'S'
        );

        -- 3. Si el costo unitario difiere, actualizar en catalogo de productos
        SELECT PRECIO_COSTO_PROD
          INTO v_costo_actual
          FROM PRO_PRODUCTO
         WHERE ID_PRODUCTO = :NEW.ID_PRODUCTO;

        IF NVL(v_costo_actual, 0) <> :NEW.COSTO_UNITARIO_FCDE THEN
            UPDATE PRO_PRODUCTO
               SET PRECIO_COSTO_PROD = :NEW.COSTO_UNITARIO_FCDE,
                   USUARIO_MOD_PROD = USER,
                   FECHA_MOD_PROD = SYSTIMESTAMP
             WHERE ID_PRODUCTO = :NEW.ID_PRODUCTO;
        END IF;
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_COM_FACTURA_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.9 TRG_PRO_HISTORIAL_PRECIO_AU
-- Disparador AFTER UPDATE ON PRO_PRODUCTO
-- Registra automaticamente el historico en PRO_PRECIO_HIST cuando varia el costo
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_PRO_HISTORIAL_PRECIO_AU
AFTER UPDATE OF PRECIO_COSTO_PROD ON PRO_PRODUCTO
FOR EACH ROW
BEGIN
    IF NVL(:OLD.PRECIO_COSTO_PROD, -1) <> NVL(:NEW.PRECIO_COSTO_PROD, -1) THEN
        INSERT INTO PRO_PRECIO_HIST (
            ID_PRECIO_HIST,
            ID_PRODUCTO,
            COSTO_ANTERIOR_PRHI,
            FECHA_CAMBIO_PRHI,
            MOTIVO_PRHI,
            USUARIO_CREA_PRHI,
            FECHA_CREA_PRHI
        ) VALUES (
            SEQ_PRO_PRECIO_HIST.NEXTVAL,
            :NEW.ID_PRODUCTO,
            NVL(:OLD.PRECIO_COSTO_PROD, 0),
            SYSDATE,
            'Actualizacion automatica por recepcion de compra o ajuste de costo',
            USER,
            SYSTIMESTAMP
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_PRO_HISTORIAL_PRECIO_AU;

-- ----------------------------------------------------------------------------
-- 1.10 TRG_VEN_DEVOLUCION_DET_INV_AI
-- Disparador AFTER INSERT ON VEN_DEVOLUCION_DET
-- Reintegra existencias a inventario formalmente via PKG_INV_GESTION
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_DEVOLUCION_DET_INV_AI
AFTER INSERT ON VEN_DEVOLUCION_DET
FOR EACH ROW
DECLARE
    v_id_bodega  NUMBER;
    v_id_prod    NUMBER;
    v_id_lote    NUMBER;
    v_id_usu     NUMBER;
BEGIN
    SELECT d.ID_BODEGA, d.ID_USUARIO, fd.ID_PRODUCTO, fd.ID_LOTE
      INTO v_id_bodega, v_id_usu, v_id_prod, v_id_lote
      FROM VEN_DEVOLUCION d
           JOIN VEN_FACTURA_DET fd ON fd.ID_FACTURA_VENTA_DET = :NEW.ID_FACTURA_VENTA_DET
     WHERE d.ID_DEVOLUCION_VENTA = :NEW.ID_DEVOLUCION_VENTA;

    PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA (
        p_id_bodega      => v_id_bodega,
        p_id_producto    => v_id_prod,
        p_id_lote        => v_id_lote,
        p_cantidad       => :NEW.CANTIDAD_DVVD,
        p_es_entrada     => 'S',
        p_tipo_movi      => 'DEV_VENTA',
        p_id_usuario     => v_id_usu,
        p_documento_ref  => 'DEV-VTA-' || :NEW.ID_DEVOLUCION_VENTA,
        p_registrar_kard => 'S'
    );
END;
/
SHOW ERRORS TRIGGER TRG_VEN_DEVOLUCION_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.11 TRG_COM_DEVOLUCION_DET_INV_AI
-- Disparador AFTER INSERT ON COM_DEVOLUCION_DET
-- Descuenta existencias de inventario formalmente via PKG_INV_GESTION
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_DEVOLUCION_DET_INV_AI
AFTER INSERT ON COM_DEVOLUCION_DET
FOR EACH ROW
DECLARE
    v_id_bodega  NUMBER;
    v_id_prod    NUMBER;
    v_id_lote    NUMBER;
    v_id_usu     NUMBER;
BEGIN
    SELECT d.ID_BODEGA, d.ID_USUARIO, cd.ID_PRODUCTO, cd.ID_LOTE
      INTO v_id_bodega, v_id_usu, v_id_prod, v_id_lote
      FROM COM_DEVOLUCION d
           JOIN COM_FACTURA_COMPRA_DET cd ON cd.ID_FACTURA_COMPRA_DET = :NEW.ID_FACTURA_COMPRA_DET
     WHERE d.ID_DEVOLUCION_COMPRA = :NEW.ID_DEVOLUCION_COMPRA;

    PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA (
        p_id_bodega      => v_id_bodega,
        p_id_producto    => v_id_prod,
        p_id_lote        => v_id_lote,
        p_cantidad       => :NEW.CANTIDAD_DVCD,
        p_es_entrada     => 'N',
        p_tipo_movi      => 'DEV_COMPRA',
        p_id_usuario     => v_id_usu,
        p_documento_ref  => 'DEV-COM-' || :NEW.ID_DEVOLUCION_COMPRA,
        p_registrar_kard => 'S'
    );
END;
/
SHOW ERRORS TRIGGER TRG_COM_DEVOLUCION_DET_INV_AI;


PROMPT ============================================================================
PROMPT 2. COMPILACION DE DISPARADORES DE AUDITORIA EN LAS 7 TABLAS PRINCIPALES
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 TRG_AUD_VEN_FACTURA
-- Tabla 1: VEN_FACTURA (Auditoria de ventas, estados y totales)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_VEN_FACTURA
AFTER INSERT OR UPDATE OR DELETE ON VEN_FACTURA
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_VENTA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'VEN_FACTURA',
            p_modulo      => 'VENTAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => :NEW.ID_SUCURSAL,
            p_descripcion => 'Insercion de factura #' || :NEW.NUM_FACTURA_FAVE || ' por total C' || TO_CHAR(:NEW.TOTAL_FAVE, '999,999,990.00')
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'ESTADO_FAVE', NULL, :NEW.ESTADO_FAVE);
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'TOTAL_FAVE', NULL, TO_CHAR(:NEW.TOTAL_FAVE));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_VENTA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'VEN_FACTURA',
            p_modulo      => 'VENTAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => :NEW.ID_SUCURSAL,
            p_descripcion => 'Modificacion en factura #' || :NEW.NUM_FACTURA_FAVE
        );
        IF NVL(:OLD.ESTADO_FAVE, 'X') != NVL(:NEW.ESTADO_FAVE, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'ESTADO_FAVE', :OLD.ESTADO_FAVE, :NEW.ESTADO_FAVE);
        END IF;
        IF NVL(:OLD.TOTAL_FAVE, -1) != NVL(:NEW.TOTAL_FAVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'TOTAL_FAVE', TO_CHAR(:OLD.TOTAL_FAVE), TO_CHAR(:NEW.TOTAL_FAVE));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_FACTURA_VENTA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'VEN_FACTURA',
            p_modulo      => 'VENTAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de factura #' || :OLD.NUM_FACTURA_FAVE
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'REGISTRO_ELIMINADO', TO_CHAR(:OLD.TOTAL_FAVE), 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_VEN_FACTURA;

-- ----------------------------------------------------------------------------
-- 2.2 TRG_AUD_COM_FACTURA
-- Tabla 2: COM_FACTURA_COMPRA (Auditoria de compras a proveedores)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_COM_FACTURA
AFTER INSERT OR UPDATE OR DELETE ON COM_FACTURA_COMPRA
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_COMPRA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_modulo      => 'COMPRAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => NULL,
            p_descripcion => 'Recepcion de compra #' || :NEW.NUM_FACTURA_FACO || ' por C' || TO_CHAR(:NEW.TOTAL_FACO, '999,999,990.00')
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'ESTADO_FACO', NULL, :NEW.ESTADO_FACO);
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'TOTAL_FACO', NULL, TO_CHAR(:NEW.TOTAL_FACO));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_COMPRA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_modulo      => 'COMPRAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_id_sucursal => NULL,
            p_descripcion => 'Modificacion en factura compra #' || :NEW.NUM_FACTURA_FACO
        );
        IF NVL(:OLD.ESTADO_FACO, 'X') != NVL(:NEW.ESTADO_FACO, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'ESTADO_FACO', :OLD.ESTADO_FACO, :NEW.ESTADO_FACO);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_FACTURA_COMPRA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_modulo      => 'COMPRAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de factura compra #' || :OLD.NUM_FACTURA_FACO
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'REGISTRO_ELIMINADO', TO_CHAR(:OLD.TOTAL_FACO), 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_COM_FACTURA;

-- ----------------------------------------------------------------------------
-- 2.3 TRG_AUD_PRO_PRODUCTO
-- Tabla 3: PRO_PRODUCTO (Auditoria de catalogo de productos y precios)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PRO_PRODUCTO
AFTER INSERT OR UPDATE OR DELETE ON PRO_PRODUCTO
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_PRODUCTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRO_PRODUCTO',
            p_modulo      => 'CATALOGO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Nuevo producto: ' || :NEW.CODIGO_PROD || ' - ' || :NEW.NOMBRE_PROD
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_COSTO', NULL, TO_CHAR(:NEW.PRECIO_COSTO_PROD));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'ESTADO_PROD', NULL, :NEW.ESTADO_PROD);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PRODUCTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRO_PRODUCTO',
            p_modulo      => 'CATALOGO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de producto ' || :NEW.CODIGO_PROD
        );
        IF NVL(:OLD.PRECIO_COSTO_PROD, -1) != NVL(:NEW.PRECIO_COSTO_PROD, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_COSTO', TO_CHAR(:OLD.PRECIO_COSTO_PROD), TO_CHAR(:NEW.PRECIO_COSTO_PROD));
        END IF;
        IF NVL(:OLD.ESTADO_PROD, 'X') != NVL(:NEW.ESTADO_PROD, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'ESTADO_PROD', :OLD.ESTADO_PROD, :NEW.ESTADO_PROD);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PRODUCTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRO_PRODUCTO',
            p_modulo      => 'CATALOGO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de producto ' || :OLD.CODIGO_PROD || ' - ' || :OLD.NOMBRE_PROD
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'REGISTRO_ELIMINADO', :OLD.NOMBRE_PROD, 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PRO_PRODUCTO;

-- ----------------------------------------------------------------------------
-- 2.4 TRG_AUD_INV_MOVIMIENTO
-- Tabla 4: INV_MOVIMIENTO (Auditoria de transacciones de inventario / kardex)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_INV_MOVIMIENTO
AFTER INSERT OR UPDATE OR DELETE ON INV_MOVIMIENTO
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_MOVIMIENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'INV_MOVIMIENTO',
            p_modulo      => 'INVENTARIO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_descripcion => 'Movimiento de inventario tipo ' || :NEW.TIPO_MOVI || ' ref: ' || :NEW.DOCUMENTO_REF_MOVI
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('INV_MOVIMIENTO', 'INVENTARIO', v_operacion, v_llave, 'TIPO_MOVI', NULL, :NEW.TIPO_MOVI);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_MOVIMIENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'INV_MOVIMIENTO',
            p_modulo      => 'INVENTARIO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO,
            p_descripcion => 'Modificacion en movimiento kardex #' || v_llave
        );
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_MOVIMIENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'INV_MOVIMIENTO',
            p_modulo      => 'INVENTARIO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de movimiento kardex #' || v_llave
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_INV_MOVIMIENTO;

-- ----------------------------------------------------------------------------
-- 2.5 TRG_AUD_PER_CLIENTE
-- Tabla 5: PER_CLIENTE (Auditoria de clientes, saldos y limites de credito)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PER_CLIENTE
AFTER INSERT OR UPDATE OR DELETE ON PER_CLIENTE
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_CLIENTE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_CLIENTE',
            p_modulo      => 'PERSONAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Cliente registrado: ' || :NEW.CODIGO_CLI
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'MONTO_MAX_CREDITO', NULL, TO_CHAR(:NEW.MONTO_MAX_CREDITO_CLI));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'ESTADO_CLI', NULL, :NEW.ESTADO_CLI);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_CLIENTE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_CLIENTE',
            p_modulo      => 'PERSONAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de datos cliente ' || :NEW.CODIGO_CLI
        );
        IF NVL(:OLD.MONTO_MAX_CREDITO_CLI, -1) != NVL(:NEW.MONTO_MAX_CREDITO_CLI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'MONTO_MAX_CREDITO', TO_CHAR(:OLD.MONTO_MAX_CREDITO_CLI), TO_CHAR(:NEW.MONTO_MAX_CREDITO_CLI));
        END IF;
        IF NVL(:OLD.SALDO_ACTUAL_CLI, -1) != NVL(:NEW.SALDO_ACTUAL_CLI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'SALDO_ACTUAL', TO_CHAR(:OLD.SALDO_ACTUAL_CLI), TO_CHAR(:NEW.SALDO_ACTUAL_CLI));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_CLIENTE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_CLIENTE',
            p_modulo      => 'PERSONAS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de cliente ' || :OLD.CODIGO_CLI
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PER_CLIENTE;

-- ----------------------------------------------------------------------------
-- 2.6 TRG_AUD_PER_PROVEEDOR
-- Tabla 6: PER_PROVEEDOR (Auditoria de proveedores, condiciones y saldos)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PER_PROVEEDOR
AFTER INSERT OR UPDATE OR DELETE ON PER_PROVEEDOR
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_PROVEEDOR);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_PROVEEDOR',
            p_modulo      => 'PROVEEDORES',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Proveedor registrado: ' || :NEW.CODIGO_PROVE
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'LIMITE_CREDITO', NULL, TO_CHAR(:NEW.LIMITE_CREDITO_PROVE));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PROVEEDOR);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_PROVEEDOR',
            p_modulo      => 'PROVEEDORES',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de datos proveedor ' || :NEW.CODIGO_PROVE
        );
        IF NVL(:OLD.LIMITE_CREDITO_PROVE, -1) != NVL(:NEW.LIMITE_CREDITO_PROVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'LIMITE_CREDITO', TO_CHAR(:OLD.LIMITE_CREDITO_PROVE), TO_CHAR(:NEW.LIMITE_CREDITO_PROVE));
        END IF;
        IF NVL(:OLD.SALDO_ACTUAL_PROVE, -1) != NVL(:NEW.SALDO_ACTUAL_PROVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'SALDO_ACTUAL', TO_CHAR(:OLD.SALDO_ACTUAL_PROVE), TO_CHAR(:NEW.SALDO_ACTUAL_PROVE));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PROVEEDOR);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PER_PROVEEDOR',
            p_modulo      => 'PROVEEDORES',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de proveedor ' || :OLD.CODIGO_PROVE
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PER_PROVEEDOR;

-- ----------------------------------------------------------------------------
-- 2.7 TRG_AUD_PRM_PROMOCION
-- Tabla 7: PRM_PROMOCION (Auditoria de promociones y campanas de mercadeo)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PRM_PROMOCION
AFTER INSERT OR UPDATE OR DELETE ON PRM_PROMOCION
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_PROMOCION);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_PROMOCION',
            p_modulo      => 'MERCADEO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Nueva promocion: ' || :NEW.CODIGO_PROM || ' - ' || :NEW.NOMBRE_PROM
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'ESTADO_PROM', NULL, :NEW.ESTADO_PROM);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PROMOCION);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_PROMOCION',
            p_modulo      => 'MERCADEO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Modificacion en promocion ' || :NEW.NOMBRE_PROM
        );
        IF NVL(:OLD.ESTADO_PROM, 'X') != NVL(:NEW.ESTADO_PROM, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'ESTADO_PROM', :OLD.ESTADO_PROM, :NEW.ESTADO_PROM);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PROMOCION);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_PROMOCION',
            p_modulo      => 'MERCADEO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de campana promocional ' || :OLD.NOMBRE_PROM
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PRM_PROMOCION;

-- ----------------------------------------------------------------------------
-- 2.8 TRG_AUD_PRM_DESCUENTO
-- Tabla 8: PRM_DESCUENTO (Auditoria de politicas y programas de descuento)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PRM_DESCUENTO
AFTER INSERT OR UPDATE OR DELETE ON PRM_DESCUENTO
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_DESCUENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Nuevo descuento creado: ' || :NEW.CODIGO_DESC || ' - ' || :NEW.NOMBRE_DESC || ' (' || :NEW.PORCENTAJE_DESC || '%)'
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO', 'DESCUENTOS', v_operacion, v_llave, 'PORCENTAJE_DESC', NULL, TO_CHAR(:NEW.PORCENTAJE_DESC));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO', 'DESCUENTOS', v_operacion, v_llave, 'ESTADO_DESC', NULL, :NEW.ESTADO_DESC);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_DESCUENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Modificacion de descuento ' || :NEW.CODIGO_DESC || ' - ' || :NEW.NOMBRE_DESC
        );
        IF NVL(:OLD.PORCENTAJE_DESC, -1) != NVL(:NEW.PORCENTAJE_DESC, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO', 'DESCUENTOS', v_operacion, v_llave, 'PORCENTAJE_DESC', TO_CHAR(:OLD.PORCENTAJE_DESC), TO_CHAR(:NEW.PORCENTAJE_DESC));
        END IF;
        IF NVL(:OLD.ESTADO_DESC, 'X') != NVL(:NEW.ESTADO_DESC, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO', 'DESCUENTOS', v_operacion, v_llave, 'ESTADO_DESC', :OLD.ESTADO_DESC, :NEW.ESTADO_DESC);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_DESCUENTO);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de descuento ' || :OLD.CODIGO_DESC
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO', 'DESCUENTOS', v_operacion, v_llave, 'REGISTRO_ELIMINADO', :OLD.NOMBRE_DESC, 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PRM_DESCUENTO;

-- ----------------------------------------------------------------------------
-- 2.9 TRG_AUD_PRM_DESCUENTO_DET
-- Tabla 9: PRM_DESCUENTO_DET (Auditoria de detalle de productos/lotes en descuento)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_AUD_PRM_DESCUENTO_DET
AFTER INSERT OR UPDATE OR DELETE ON PRM_DESCUENTO_DET
FOR EACH ROW
DECLARE
    v_operacion VARCHAR2(10);
    v_llave     VARCHAR2(50);
BEGIN
    IF INSERTING THEN
        v_operacion := 'INSERT';
        v_llave := TO_CHAR(:NEW.ID_DESCUENTO_DET);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO_DET',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Producto ID ' || :NEW.ID_PRODUCTO || ' (Lote ' || NVL(TO_CHAR(:NEW.ID_LOTE), 'N/A') || ') incluido en descuento #' || :NEW.ID_DESCUENTO
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_DESCUENTO_DET', 'DESCUENTOS', v_operacion, v_llave, 'ID_PRODUCTO', NULL, TO_CHAR(:NEW.ID_PRODUCTO));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_DESCUENTO_DET);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO_DET',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Modificacion en detalle de descuento #' || :NEW.ID_DESCUENTO
        );
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_DESCUENTO_DET);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_tabla       => 'PRM_DESCUENTO_DET',
            p_modulo      => 'DESCUENTOS',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Producto ID ' || :OLD.ID_PRODUCTO || ' retirado de descuento #' || :OLD.ID_DESCUENTO
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PRM_DESCUENTO_DET;

-- ----------------------------------------------------------------------------
-- 2.10 TRG_SEG_PARAM_PREMIACION_AU
-- Sincronizacion dinamica del Scheduler ante actualizaciones del parametro
-- MESES_FRECUENCIA_PREMIACION en SEG_PARAMETRO (Requerimiento de Parametrizacion Dinamica).
-- Utiliza transaccion autonoma para aislar el COMMIT interno de DBMS_SCHEDULER.SET_ATTRIBUTE.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_SEG_PARAM_PREMIACION_AU
AFTER UPDATE OF VALOR_NUM_PARA ON SEG_PARAMETRO
FOR EACH ROW
WHEN (NEW.CODIGO_PARA = 'MESES_FRECUENCIA_PREMIACION' AND NEW.VALOR_NUM_PARA IS NOT NULL AND NEW.VALOR_NUM_PARA > 0)
DECLARE
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    BEGIN
        DBMS_SCHEDULER.SET_ATTRIBUTE (
            name      => 'CADENA_NEG.JOB_PREMIACION_SEMESTRAL',
            attribute => 'repeat_interval',
            value     => 'FREQ=MONTHLY; INTERVAL=' || :NEW.VALOR_NUM_PARA || '; BYMONTHDAY=-1; BYHOUR=23; BYMINUTE=30; BYSECOND=0'
        );
    EXCEPTION
        WHEN OTHERS THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_ERROR('TRG_SEG_PARAM_PREMIACION_AU', 'SET_ATTRIBUTE', SQLCODE, SQLERRM);
    END;
END;
/
SHOW ERRORS TRIGGER TRG_SEG_PARAM_PREMIACION_AU;



PROMPT ============================================================================
PROMPT 3. VALIDACION Y COMPROBACION DE DISPARADORES INSTALADOS
PROMPT ============================================================================

DECLARE
    v_total_validos   NUMBER := 0;
    v_total_invalidos NUMBER := 0;
BEGIN
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE(RPAD('NOMBRE DISPARADOR', 35) || RPAD('TABLA ASOCIADA', 25) || 'ESTADO');
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');

    FOR r IN (
        SELECT trigger_name, table_name, status
          FROM all_triggers
         WHERE owner = 'CADENA_NEG'
           AND trigger_name LIKE 'TRG_%'
         ORDER BY trigger_name
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(RPAD(r.trigger_name, 35) || RPAD(r.table_name, 25) || r.status);
        IF r.status = 'ENABLED' THEN
            v_total_validos := v_total_validos + 1;
        ELSE
            v_total_invalidos := v_total_invalidos + 1;
        END IF;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('TOTAL DISPARADORES HABILITADOS: ' || v_total_validos);
    DBMS_OUTPUT.PUT_LINE('TOTAL DISPARADORES INVALIDOS:   ' || v_total_invalidos);
    DBMS_OUTPUT.PUT_LINE('========================================================================');
END;
/

PROMPT === FIN DE 04_Triggers_Negocio_y_Auditoria.sql ===
