-- ============================================================================
-- PROYECTO: Sistema Integral de Cadena de Supermercados
-- ARCHIVO:  04_Triggers_Negocio_y_Auditoria.sql
-- AUTOR:    Keylor Pineda Alvarez
-- CURSO:    Administracion de Bases de Datos
-- FECHA:    Octubre 2026 - Avance 2
-- MOTOR:    Oracle Database 21c / 23ai / 26ai Free
-- DESCRIPCION:
--   Implementacion de disparadores (triggers) de reglas de negocio automatizadas
--   y disparadores de auditoria profunda en las 7 tablas principales del sistema.
--
-- CONTENIDO:
--   1. TRIGGERS DE NEGOCIO:
--      a) TRG_VEN_FACTURA_CREDITO:
--         - BEFORE INSERT OR UPDATE: Valida limite de credito del cliente.
--         - AFTER INSERT: Aumenta saldo actual del cliente y asegura cuenta por cobrar.
--      b) TRG_COM_FACTURA_CREDITO:
--         - BEFORE INSERT OR UPDATE: Valida limite de credito otorgado por proveedor.
--         - AFTER INSERT: Aumenta saldo con proveedor y asegura cuenta por pagar.
--      c) TRG_VEN_ABONO_SALDO:
--         - AFTER INSERT: Disminuye saldo en cuenta por cobrar, saldo del cliente,
--           y si saldo llega a 0 actualiza estado de cuenta y factura a 'C' (Cancelada).
--      d) TRG_COM_ABONO_SALDO:
--         - AFTER INSERT: Disminuye saldo en cuenta por pagar, saldo del proveedor,
--           y si saldo llega a 0 actualiza estado de cuenta y factura compra a 'C'.
--      e) TRG_VEN_FACTURA_DET_INV:
--         - AFTER INSERT: Disminuye inventario de bodega sucursal, registra kardex
--           y otorga acciones promocionales automaticas a marcas patrocinadoras.
--      f) TRG_COM_FACTURA_DET_INV:
--         - AFTER INSERT: Aumenta inventario de bodega, registra kardex y actualiza
--           costo unitario en catalogo de productos si difiere del actual.
--      g) TRG_PRO_HISTORIAL_PRECIO:
--         - AFTER UPDATE OF PRECIO_COSTO_PROD / PRECIO_VENTA_PROD: Registra
--           historico en PRO_PRECIO_HIST de forma automatica e inmutable.
--      h) TRG_VEN_DEVOLUCION_DET_INV:
--         - AFTER INSERT: Reintegra existencias a inventario por devolucion cliente.
--      i) TRG_COM_DEVOLUCION_DET_INV:
--         - AFTER INSERT: Descuenta existencias de inventario por devolucion a proveedor.
--
--   2. TRIGGERS DE AUDITORIA (7 TABLAS PRINCIPALES):
--      1. TRG_AUD_VEN_FACTURA      (Ventas / Facturacion)
--      2. TRG_AUD_COM_FACTURA      (Compras / Proveeduria)
--      3. TRG_AUD_PRO_PRODUCTO     (Catalogo de Productos y Precios)
--      4. TRG_AUD_INV_MOVIMIENTO   (Movimientos de Inventario / Kardex)
--      5. TRG_AUD_PER_CLIENTE      (Clientes y Limites de Credito)
--      6. TRG_AUD_PER_PROVEEDOR    (Proveedores y Condiciones Comerciales)
--      7. TRG_AUD_PRM_PROMOCION    (Campanas Promocionales y Mercadeo)
--
--   3. BLOQUE DE PRUEBA Y VALIDACION DE DISPARADORES.
-- ============================================================================

WHENEVER SQLERROR CONTINUE;

-- Conectar dinamicamente al PDB o esquema de trabajo
DECLARE
    v_open_mode VARCHAR2(20);
    v_pdb_name  VARCHAR2(30);
BEGIN
    SELECT open_mode INTO v_open_mode FROM v$database;
    IF SYS_CONTEXT('USERENV', 'CON_NAME') = 'CDB$ROOT' THEN
        BEGIN
            SELECT pdb_name INTO v_pdb_name 
              FROM cdb_pdbs 
             WHERE open_mode = 'READ WRITE' 
               AND ROWNUM = 1;
            EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb_name;
            DBMS_OUTPUT.PUT_LINE('[SESION] Conectado exitosamente al PDB: ' || v_pdb_name);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('[AVISO] En CDB$ROOT, no se encontro PDB abierto.');
        END;
    END IF;
    
    -- Establecer esquema actual
    BEGIN
        EXECUTE IMMEDIATE 'ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG';
        DBMS_OUTPUT.PUT_LINE('[SESION] Esquema actual establecido en CADENA_NEG.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('[AVISO] No se pudo cambiar a CADENA_NEG: ' || SQLERRM);
    END;
END;
/

SET SERVEROUTPUT ON SIZE UNLIMITED;
SET LINESIZE 200;
SET PAGESIZE 100;

PROMPT ============================================================================
PROMPT 1. COMPILACION DE DISPARADORES DE NEGOCIO AUTOMATIZADOS
PROMPT ============================================================================

-- ----------------------------------------------------------------------------
-- 1.1 TRG_VEN_FACTURA_CRED_BIU
-- Disparador BEFORE INSERT OR UPDATE ON VEN_FACTURA
-- Valida que el cliente no supere su limite de credito autorizado
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_FACTURA_CRED_BIU
BEFORE INSERT OR UPDATE OF TOTAL_FAVE, ES_CREDITO_FAVE, ESTADO_FAVE ON VEN_FACTURA
FOR EACH ROW
DECLARE
    v_saldo_actual  NUMBER(14,2);
    v_monto_max     NUMBER(14,2);
    v_estado_cli    VARCHAR2(1);
    v_nombre_cli    VARCHAR2(120);
    v_diferencia    NUMBER(14,2) := 0;
BEGIN
    -- Solo aplica si la factura es a credito o se encuentra en estado Pendiente
    IF :NEW.ES_CREDITO_FAVE = 'S' OR :NEW.ESTADO_FAVE = 'P' THEN
        SELECT NVL(SALDO_ACTUAL_CLI, 0), NVL(MONTO_MAX_CREDITO_CLI, 0), ESTADO_CLI, NOMBRE_COMPLETO_CLIE
          INTO v_saldo_actual, v_monto_max, v_estado_cli, v_nombre_cli
          FROM PER_CLIENTE
         WHERE ID_CLIENTE_CLIE = :NEW.ID_CLIENTE_CLIE;

        IF v_estado_cli <> 'A' THEN
            RAISE_APPLICATION_ERROR(-20011, 'El cliente "' || v_nombre_cli || '" no esta activo para emitirle facturas a credito.');
        END IF;

        IF INSERTING THEN
            v_diferencia := :NEW.TOTAL_FAVE;
        ELSIF UPDATING THEN
            v_diferencia := :NEW.TOTAL_FAVE - NVL(:OLD.TOTAL_FAVE, 0);
        END IF;

        IF v_diferencia > 0 AND (v_saldo_actual + v_diferencia) > v_monto_max THEN
            RAISE_APPLICATION_ERROR(-20010, 'Limite de credito excedido para el cliente ' || v_nombre_cli || 
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
    v_plazo_dias NUMBER := 30;
    v_cant_cuco  NUMBER := 0;
BEGIN
    IF :NEW.ES_CREDITO_FAVE = 'S' OR :NEW.ESTADO_FAVE = 'P' THEN
        -- 1. Aumentar el saldo actual del cliente
        UPDATE PER_CLIENTE
           SET SALDO_ACTUAL_CLI = NVL(SALDO_ACTUAL_CLI, 0) + :NEW.TOTAL_FAVE,
               USUARIO_MOD_CLIE = USER,
               FECHA_MOD_CLIE = SYSTIMESTAMP
         WHERE ID_CLIENTE_CLIE = :NEW.ID_CLIENTE_CLIE;

        -- 2. Obtener plazo acordado con el cliente
        BEGIN
            SELECT NVL(PLAZO_CREDITO_DIAS_CLI, 30)
              INTO v_plazo_dias
              FROM PER_CLIENTE
             WHERE ID_CLIENTE_CLIE = :NEW.ID_CLIENTE_CLIE;
        EXCEPTION
            WHEN OTHERS THEN v_plazo_dias := 30;
        END;

        -- 3. Verificar si ya existe registro en VEN_CUENTA_COBRAR (evitar duplicados si lo creo un paquete)
        SELECT COUNT(*)
          INTO v_cant_cuco
          FROM VEN_CUENTA_COBRAR
         WHERE ID_FACTURA_FAVE = :NEW.ID_FACTURA_FAVE;

        IF v_cant_cuco = 0 THEN
            INSERT INTO VEN_CUENTA_COBRAR (
                ID_CUENTA_COBRAR,
                ID_FACTURA_FAVE,
                ID_CLIENTE_CLIE,
                FECHA_EMISION_CUCO,
                FECHA_VENCIMIENTO_CUCO,
                MONTO_ORIGINAL_CUCO,
                SALDO_CUCO,
                ESTADO_CUCO,
                DIAS_CREDITO_CUCO,
                INTERES_MORA_CUCO,
                USUARIO_CREA_CUCO,
                FECHA_CREA_CUCO
            ) VALUES (
                SEQ_VEN_CUENTA_COBRAR.NEXTVAL,
                :NEW.ID_FACTURA_FAVE,
                :NEW.ID_CLIENTE_CLIE,
                :NEW.FECHA_FAVE,
                :NEW.FECHA_FAVE + v_plazo_dias,
                :NEW.TOTAL_FAVE,
                :NEW.TOTAL_FAVE,
                'P',
                v_plazo_dias,
                0,
                USER,
                SYSTIMESTAMP
            );
        END IF;

        -- 4. Registrar operacion en bitacora
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'VENTAS',
            p_tabla       => 'VEN_FACTURA',
            p_operacion   => 'CREDITO_AUTO',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_FAVE),
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Factura a credito registrada. Saldo cliente aumentado en C' || TO_CHAR(:NEW.TOTAL_FAVE, '999,999,990.00')
        );
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_VEN_FACTURA_CRED_AI;

-- ----------------------------------------------------------------------------
-- 1.3 TRG_COM_FACTURA_CRED_BIU
-- Disparador BEFORE INSERT OR UPDATE ON COM_FACTURA_COMPRA
-- Valida que el credito otorgado por el proveedor no sobrepase el limite negociado
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_FACTURA_CRED_BIU
BEFORE INSERT OR UPDATE OF TOTAL_FACO, ES_CREDITO_FACO, ESTADO_FACO ON COM_FACTURA_COMPRA
FOR EACH ROW
DECLARE
    v_saldo_actual  NUMBER(14,2);
    v_limite_max    NUMBER(14,2);
    v_estado_prov   VARCHAR2(1);
    v_nombre_prov   VARCHAR2(120);
    v_diferencia    NUMBER(14,2) := 0;
BEGIN
    IF :NEW.ES_CREDITO_FACO = 'S' OR :NEW.ESTADO_FACO = 'P' THEN
        SELECT NVL(SALDO_ACTUAL_PROVE, 0), NVL(LIMITE_CREDITO_PROVE, 0), ESTADO_PROVE, NOMBRE_COMERCIAL_PROV
          INTO v_saldo_actual, v_limite_max, v_estado_prov, v_nombre_prov
          FROM PER_PROVEEDOR
         WHERE ID_PROVEEDOR_PROV = :NEW.ID_PROVEEDOR_PROV;

        IF v_estado_prov <> 'A' THEN
            RAISE_APPLICATION_ERROR(-20014, 'El proveedor "' || v_nombre_prov || '" se encuentra inactivo para compras a credito.');
        END IF;

        IF INSERTING THEN
            v_diferencia := :NEW.TOTAL_FACO;
        ELSIF UPDATING THEN
            v_diferencia := :NEW.TOTAL_FACO - NVL(:OLD.TOTAL_FACO, 0);
        END IF;

        IF v_limite_max > 0 AND v_diferencia > 0 AND (v_saldo_actual + v_diferencia) > v_limite_max THEN
            RAISE_APPLICATION_ERROR(-20015, 'Limite de credito otorgado por proveedor ' || v_nombre_prov || 
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
    v_plazo_dias NUMBER := 30;
    v_cant_cupa  NUMBER := 0;
BEGIN
    IF :NEW.ES_CREDITO_FACO = 'S' OR :NEW.ESTADO_FACO = 'P' THEN
        -- 1. Aumentar saldo pendiente al proveedor
        UPDATE PER_PROVEEDOR
           SET SALDO_ACTUAL_PROVE = NVL(SALDO_ACTUAL_PROVE, 0) + :NEW.TOTAL_FACO,
               USUARIO_MOD_PROVE = USER,
               FECHA_MOD_PROVE = SYSTIMESTAMP
         WHERE ID_PROVEEDOR_PROV = :NEW.ID_PROVEEDOR_PROV;

        -- 2. Plazo credito del proveedor
        BEGIN
            SELECT NVL(PLAZO_CREDITO_DIAS_PROVE, 30)
              INTO v_plazo_dias
              FROM PER_PROVEEDOR
             WHERE ID_PROVEEDOR_PROV = :NEW.ID_PROVEEDOR_PROV;
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
                ID_PROVEEDOR_PROV,
                FECHA_EMISION_CUPA,
                FECHA_VENCIMIENTO_CUPA,
                MONTO_ORIGINAL_CUPA,
                SALDO_CUPA,
                ESTADO_CUPA,
                DIAS_CREDITO_CUPA,
                USUARIO_CREA_CUPA,
                FECHA_CREA_CUPA
            ) VALUES (
                SEQ_COM_CUENTA_PAGAR.NEXTVAL,
                :NEW.ID_FACTURA_COMPRA,
                :NEW.ID_PROVEEDOR_PROV,
                :NEW.FECHA_FACO,
                :NEW.FECHA_FACO + v_plazo_dias,
                :NEW.TOTAL_FACO,
                :NEW.TOTAL_FACO,
                'P',
                v_plazo_dias,
                USER,
                SYSTIMESTAMP
            );
        END IF;

        -- 4. Registro de bitacora
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'COMPRAS',
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_operacion   => 'CREDITO_AUTO',
            p_llave       => TO_CHAR(:NEW.ID_FACTURA_COMPRA),
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Compra a credito registrada. Saldo con proveedor aumentado en C' || TO_CHAR(:NEW.TOTAL_FACO, '999,999,990.00')
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
    v_id_factura   NUMBER;
    v_id_cliente   NUMBER;
    v_saldo_actual NUMBER(14,2);
    v_nuevo_saldo  NUMBER(14,2);
    v_nuevo_estado VARCHAR2(1);
BEGIN
    -- 1. Obtener datos actuales de la cuenta por cobrar
    SELECT ID_FACTURA_FAVE, ID_CLIENTE_CLIE, SALDO_CUCO
      INTO v_id_factura, v_id_cliente, v_saldo_actual
      FROM VEN_CUENTA_COBRAR
     WHERE ID_CUENTA_COBRAR = :NEW.ID_CUENTA_COBRAR;

    v_nuevo_saldo := GREATEST(0, v_saldo_actual - :NEW.MONTO_ABON);
    
    IF v_nuevo_saldo = 0 THEN
        v_nuevo_estado := 'C'; -- Cancelada
    ELSE
        v_nuevo_estado := 'P'; -- Pendiente / Parcial
    END IF;

    -- 2. Actualizar saldo y estado en la cuenta por cobrar
    UPDATE VEN_CUENTA_COBRAR
       SET SALDO_CUCO = v_nuevo_saldo,
           ESTADO_CUCO = v_nuevo_estado,
           USUARIO_MOD_CUCO = USER,
           FECHA_MOD_CUCO = SYSTIMESTAMP
     WHERE ID_CUENTA_COBRAR = :NEW.ID_CUENTA_COBRAR;

    -- 3. Disminuir saldo actual del cliente
    UPDATE PER_CLIENTE
       SET SALDO_ACTUAL_CLI = GREATEST(0, NVL(SALDO_ACTUAL_CLI, 0) - :NEW.MONTO_ABON),
           USUARIO_MOD_CLIE = USER,
           FECHA_MOD_CLIE = SYSTIMESTAMP
     WHERE ID_CLIENTE_CLIE = v_id_cliente;

    -- 4. Si la cuenta fue cancelada en su totalidad, actualizar estado de factura a 'C'
    IF v_nuevo_estado = 'C' THEN
        UPDATE VEN_FACTURA
           SET ESTADO_FAVE = 'C',
               USUARIO_MOD_FAVE = USER,
               FECHA_MOD_FAVE = SYSTIMESTAMP
         WHERE ID_FACTURA_FAVE = v_id_factura
           AND ESTADO_FAVE <> 'C';

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'VENTAS',
            p_tabla       => 'VEN_FACTURA',
            p_operacion   => 'CANCELACION_AUTO',
            p_llave       => TO_CHAR(v_id_factura),
            p_descripcion => 'Factura cancelada automaticamente tras liquidacion de cuenta por cobrar #' || :NEW.ID_CUENTA_COBRAR
        );
    END IF;

    -- 5. Registrar abono en bitacora
    PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
        p_modulo      => 'VENTAS',
        p_tabla       => 'VEN_ABONO_COBRAR',
        p_operacion   => 'ABONO',
        p_llave       => TO_CHAR(:NEW.ID_ABONO_COBRAR),
        p_descripcion => 'Abono de C' || TO_CHAR(:NEW.MONTO_ABON, '999,999,990.00') || ' aplicado a cuenta #' || :NEW.ID_CUENTA_COBRAR || '. Nuevo saldo: C' || TO_CHAR(v_nuevo_saldo, '999,999,990.00')
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
    v_id_factura_com NUMBER;
    v_id_proveedor   NUMBER;
    v_saldo_actual   NUMBER(14,2);
    v_nuevo_saldo    NUMBER(14,2);
    v_nuevo_estado   VARCHAR2(1);
BEGIN
    -- 1. Obtener datos actuales de la cuenta por pagar
    SELECT ID_FACTURA_COMPRA, ID_PROVEEDOR_PROV, SALDO_CUPA
      INTO v_id_factura_com, v_id_proveedor, v_saldo_actual
      FROM COM_CUENTA_PAGAR
     WHERE ID_CUENTA_PAGAR = :NEW.ID_CUENTA_PAGAR;

    v_nuevo_saldo := GREATEST(0, v_saldo_actual - :NEW.MONTO_ABPA);
    
    IF v_nuevo_saldo = 0 THEN
        v_nuevo_estado := 'C'; -- Cancelada
    ELSE
        v_nuevo_estado := 'P'; -- Pendiente / Parcial
    END IF;

    -- 2. Actualizar saldo y estado en la cuenta por pagar
    UPDATE COM_CUENTA_PAGAR
       SET SALDO_CUPA = v_nuevo_saldo,
           ESTADO_CUPA = v_nuevo_estado,
           USUARIO_MOD_CUPA = USER,
           FECHA_MOD_CUPA = SYSTIMESTAMP
     WHERE ID_CUENTA_PAGAR = :NEW.ID_CUENTA_PAGAR;

    -- 3. Disminuir saldo pendiente con el proveedor
    UPDATE PER_PROVEEDOR
       SET SALDO_ACTUAL_PROVE = GREATEST(0, NVL(SALDO_ACTUAL_PROVE, 0) - :NEW.MONTO_ABPA),
           USUARIO_MOD_PROVE = USER,
           FECHA_MOD_PROVE = SYSTIMESTAMP
     WHERE ID_PROVEEDOR_PROV = v_id_proveedor;

    -- 4. Si la cuenta fue cancelada en su totalidad, actualizar estado de factura compra a 'C'
    IF v_nuevo_estado = 'C' THEN
        UPDATE COM_FACTURA_COMPRA
           SET ESTADO_FACO = 'C',
               USUARIO_MOD_FACO = USER,
               FECHA_MOD_FACO = SYSTIMESTAMP
         WHERE ID_FACTURA_COMPRA = v_id_factura_com
           AND ESTADO_FACO <> 'C';

        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'COMPRAS',
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_operacion   => 'CANCELACION_AUTO',
            p_llave       => TO_CHAR(v_id_factura_com),
            p_descripcion => 'Factura compra cancelada automaticamente tras liquidacion de cuenta por pagar #' || :NEW.ID_CUENTA_PAGAR
        );
    END IF;

    -- 5. Registrar abono en bitacora
    PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
        p_modulo      => 'COMPRAS',
        p_tabla       => 'COM_ABONO_PAGAR',
        p_operacion   => 'ABONO',
        p_llave       => TO_CHAR(:NEW.ID_ABONO_PAGAR),
        p_descripcion => 'Abono a proveedor de C' || TO_CHAR(:NEW.MONTO_ABPA, '999,999,990.00') || ' aplicado a cuenta #' || :NEW.ID_CUENTA_PAGAR || '. Nuevo saldo: C' || TO_CHAR(v_nuevo_saldo, '999,999,990.00')
    );
END;
/
SHOW ERRORS TRIGGER TRG_COM_ABONO_SALDO_AI;

-- ----------------------------------------------------------------------------
-- 1.7 TRG_VEN_FACTURA_DET_INV_AI
-- Disparador AFTER INSERT ON VEN_FACTURA_DET
-- Descuenta existencias del inventario de la bodega correspondiente a la sucursal,
-- registra movimiento de salida por venta en kardex y otorga acciones promocionales.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_FACTURA_DET_INV_AI
AFTER INSERT ON VEN_FACTURA_DET
FOR EACH ROW
DECLARE
    v_id_sucursal NUMBER;
    v_id_bodega   NUMBER;
    v_stock_ant   NUMBER;
    v_stock_nue   NUMBER;
BEGIN
    -- 1. Obtener sucursal de la factura padre
    SELECT ID_SUCURSAL_SUCU
      INTO v_id_sucursal
      FROM VEN_FACTURA
     WHERE ID_FACTURA_FAVE = :NEW.ID_FACTURA_FAVE;

    -- 2. Obtener bodega principal de la sucursal
    BEGIN
        SELECT ID_BODEGA_BODE
          INTO v_id_bodega
          FROM INV_BODEGA
         WHERE ID_SUCURSAL_SUCU = v_id_sucursal
           AND ESTADO_BODE = 'A'
           AND ROWNUM = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            SELECT ID_BODEGA_BODE
              INTO v_id_bodega
              FROM INV_BODEGA
             WHERE ESTADO_BODE = 'A'
               AND ROWNUM = 1;
    END;

    -- 3. Descontar existencias y verificar stock
    BEGIN
        SELECT CANTIDAD_EXISTENCIA_EXIS
          INTO v_stock_ant
          FROM INV_EXISTENCIA
         WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
           AND ID_BODEGA_BODE = v_id_bodega
         FOR UPDATE WAIT 5;

        IF v_stock_ant < :NEW.CANTIDAD_FADE THEN
            -- Si no alcanza el stock en la bodega primaria, se advierte o descuenta
            -- Para evitar abortar facturas masivas se ajusta al saldo disponible
            v_stock_nue := GREATEST(0, v_stock_ant - :NEW.CANTIDAD_FADE);
        ELSE
            v_stock_nue := v_stock_ant - :NEW.CANTIDAD_FADE;
        END IF;

        UPDATE INV_EXISTENCIA
           SET CANTIDAD_EXISTENCIA_EXIS = v_stock_nue,
               FECHA_ULTIMO_MOVIMIENTO_EXIS = SYSDATE,
               USUARIO_MOD_EXIS = USER,
               FECHA_MOD_EXIS = SYSTIMESTAMP
         WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
           AND ID_BODEGA_BODE = v_id_bodega;

        -- 4. Registrar movimiento en kardex INV_MOVIMIENTO
        INSERT INTO INV_MOVIMIENTO (
            ID_MOVIMIENTO_MOVI,
            ID_PRODUCTO_PROD,
            ID_BODEGA_BODE,
            ID_TIPO_MOVIMIENTO_TIMO,
            FECHA_HORA_MOVI,
            CANTIDAD_MOVI,
            DOCUMENTO_REFERENCIA_MOVI,
            OBSERVACIONES_MOVI,
            USUARIO_CREA_MOVI,
            FECHA_CREA_MOVI
        ) VALUES (
            SEQ_INV_MOVIMIENTO.NEXTVAL,
            :NEW.ID_PRODUCTO_PROD,
            v_id_bodega,
            2, -- Salida por Venta
            SYSDATE,
            :NEW.CANTIDAD_FADE,
            'FAC-' || TO_CHAR(:NEW.ID_FACTURA_FAVE),
            'Salida automatica por linea de factura #' || :NEW.ID_FACTURA_FAVE,
            USER,
            SYSTIMESTAMP
        );
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- Si no existe fila de existencia, crearla con saldo cero
            INSERT INTO INV_EXISTENCIA (
                ID_PRODUCTO_PROD, ID_BODEGA_BODE,
                CANTIDAD_EXISTENCIA_EXIS, CANTIDAD_MINIMA_EXIS, CANTIDAD_MAXIMA_EXIS,
                FECHA_ULTIMO_MOVIMIENTO_EXIS, ESTADO_EXIS,
                USUARIO_CREA_EXIS, FECHA_CREA_EXIS
            ) VALUES (
                :NEW.ID_PRODUCTO_PROD, v_id_bodega,
                0, 5, 100,
                SYSDATE, 'A',
                USER, SYSTIMESTAMP
            );
    END;

    -- 5. Otorgamiento automatico de acciones para patrocinadores si califica
    BEGIN
        PKG_PRM_MERCADEO.PR_OTORGAR_ACCIONES_LINEA (
            p_id_factura  => :NEW.ID_FACTURA_FAVE,
            p_id_producto => :NEW.ID_PRODUCTO_PROD,
            p_cantidad    => :NEW.CANTIDAD_FADE,
            p_subtotal    => :NEW.SUBTOTAL_FADE
        );
    EXCEPTION
        WHEN OTHERS THEN
            NULL; -- No interrumpe la facturacion si no hay patrocinador activo
    END;
END;
/
SHOW ERRORS TRIGGER TRG_VEN_FACTURA_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.8 TRG_COM_FACTURA_DET_INV_AI
-- Disparador AFTER INSERT ON COM_FACTURA_COMPRA_DET
-- Aumenta existencias de inventario en la bodega que recibe, registra kardex
-- y actualiza el costo en el catalogo de productos si difiere del actual.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_FACTURA_DET_INV_AI
AFTER INSERT ON COM_FACTURA_COMPRA_DET
FOR EACH ROW
DECLARE
    v_id_bodega     NUMBER;
    v_costo_actual  NUMBER(14,2);
    v_stock_ant     NUMBER;
BEGIN
    -- 1. Obtener bodega que recibe de la factura de compra
    SELECT ID_BODEGA_BODE
      INTO v_id_bodega
      FROM COM_FACTURA_COMPRA
     WHERE ID_FACTURA_COMPRA = :NEW.ID_FACTURA_COMPRA;

    IF v_id_bodega IS NULL THEN
        SELECT ID_BODEGA_BODE INTO v_id_bodega 
          FROM INV_BODEGA 
         WHERE ESTADO_BODE = 'A' AND ROWNUM = 1;
    END IF;

    -- 2. Aumentar stock de inventario
    BEGIN
        SELECT CANTIDAD_EXISTENCIA_EXIS
          INTO v_stock_ant
          FROM INV_EXISTENCIA
         WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
           AND ID_BODEGA_BODE = v_id_bodega
         FOR UPDATE WAIT 5;

        UPDATE INV_EXISTENCIA
           SET CANTIDAD_EXISTENCIA_EXIS = CANTIDAD_EXISTENCIA_EXIS + :NEW.CANTIDAD_FCDE,
               FECHA_ULTIMO_MOVIMIENTO_EXIS = SYSDATE,
               USUARIO_MOD_EXIS = USER,
               FECHA_MOD_EXIS = SYSTIMESTAMP
         WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
           AND ID_BODEGA_BODE = v_id_bodega;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            INSERT INTO INV_EXISTENCIA (
                ID_PRODUCTO_PROD, ID_BODEGA_BODE,
                CANTIDAD_EXISTENCIA_EXIS, CANTIDAD_MINIMA_EXIS, CANTIDAD_MAXIMA_EXIS,
                FECHA_ULTIMO_MOVIMIENTO_EXIS, ESTADO_EXIS,
                USUARIO_CREA_EXIS, FECHA_CREA_EXIS
            ) VALUES (
                :NEW.ID_PRODUCTO_PROD, v_id_bodega,
                :NEW.CANTIDAD_FCDE, 5, 100,
                SYSDATE, 'A',
                USER, SYSTIMESTAMP
            );
    END;

    -- 3. Registrar movimiento en kardex INV_MOVIMIENTO
    INSERT INTO INV_MOVIMIENTO (
        ID_MOVIMIENTO_MOVI,
        ID_PRODUCTO_PROD,
        ID_BODEGA_BODE,
        ID_TIPO_MOVIMIENTO_TIMO,
        FECHA_HORA_MOVI,
        CANTIDAD_MOVI,
        DOCUMENTO_REFERENCIA_MOVI,
        OBSERVACIONES_MOVI,
        USUARIO_CREA_MOVI,
        FECHA_CREA_MOVI
    ) VALUES (
        SEQ_INV_MOVIMIENTO.NEXTVAL,
        :NEW.ID_PRODUCTO_PROD,
        v_id_bodega,
        1, -- Entrada por Compra
        SYSDATE,
        :NEW.CANTIDAD_FCDE,
        'COM-' || TO_CHAR(:NEW.ID_FACTURA_COMPRA),
        'Entrada automatica por linea de compra #' || :NEW.ID_FACTURA_COMPRA,
        USER,
        SYSTIMESTAMP
    );

    -- 4. Si el costo unitario de compra difiere del registrado, actualizarlo en catalogo
    SELECT PRECIO_COSTO_PROD
      INTO v_costo_actual
      FROM PRO_PRODUCTO
     WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD;

    IF NVL(v_costo_actual, 0) <> :NEW.COSTO_UNITARIO_FCDE THEN
        UPDATE PRO_PRODUCTO
           SET PRECIO_COSTO_PROD = :NEW.COSTO_UNITARIO_FCDE,
               USUARIO_MOD_PROD = USER,
               FECHA_MOD_PROD = SYSTIMESTAMP
         WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD;
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_COM_FACTURA_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.9 TRG_PRO_HISTORIAL_PRECIO_AU
-- Disparador AFTER UPDATE ON PRO_PRODUCTO
-- Registra automaticamente el historico en PRO_PRECIO_HIST cuando varia
-- el precio de costo o de venta de cualquier producto.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_PRO_HISTORIAL_PRECIO_AU
AFTER UPDATE OF PRECIO_COSTO_PROD, PRECIO_VENTA_PROD ON PRO_PRODUCTO
FOR EACH ROW
BEGIN
    -- Historico de cambio de Costo
    IF NVL(:OLD.PRECIO_COSTO_PROD, -1) <> NVL(:NEW.PRECIO_COSTO_PROD, -1) THEN
        INSERT INTO PRO_PRECIO_HIST (
            ID_PRECIO_HIST,
            ID_PRODUCTO_PROD,
            PRECIO_ANTERIOR_PRHI,
            PRECIO_NUEVO_PRHI,
            TIPO_PRECIO_PRHI,
            MOTIVO_CAMBIO_PRHI,
            USUARIO_CREA_PRHI,
            FECHA_CREA_PRHI
        ) VALUES (
            SEQ_PRO_PRECIO_HIST.NEXTVAL,
            :NEW.ID_PRODUCTO_PROD,
            NVL(:OLD.PRECIO_COSTO_PROD, 0),
            :NEW.PRECIO_COSTO_PROD,
            'COSTO',
            'Actualizacion automatica por recepcion de compra o ajuste de costo',
            USER,
            SYSTIMESTAMP
        );
    END IF;

    -- Historico de cambio de Precio de Venta
    IF NVL(:OLD.PRECIO_VENTA_PROD, -1) <> NVL(:NEW.PRECIO_VENTA_PROD, -1) THEN
        INSERT INTO PRO_PRECIO_HIST (
            ID_PRECIO_HIST,
            ID_PRODUCTO_PROD,
            PRECIO_ANTERIOR_PRHI,
            PRECIO_NUEVO_PRHI,
            TIPO_PRECIO_PRHI,
            MOTIVO_CAMBIO_PRHI,
            USUARIO_CREA_PRHI,
            FECHA_CREA_PRHI
        ) VALUES (
            SEQ_PRO_PRECIO_HIST.NEXTVAL,
            :NEW.ID_PRODUCTO_PROD,
            NVL(:OLD.PRECIO_VENTA_PROD, 0),
            :NEW.PRECIO_VENTA_PROD,
            'VENTA',
            'Actualizacion de precio comercial de venta al publico',
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
-- Reintegra existencias a inventario por devolucion del cliente
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_VEN_DEVOLUCION_DET_INV_AI
AFTER INSERT ON VEN_DEVOLUCION_DET
FOR EACH ROW
DECLARE
    v_id_bodega NUMBER;
BEGIN
    SELECT ID_BODEGA_BODE
      INTO v_id_bodega
      FROM VEN_DEVOLUCION_CLI
     WHERE ID_DEVOLUCION_CLI = :NEW.ID_DEVOLUCION_CLI;

    IF v_id_bodega IS NULL THEN
        SELECT ID_BODEGA_BODE INTO v_id_bodega FROM INV_BODEGA WHERE ESTADO_BODE = 'A' AND ROWNUM = 1;
    END IF;

    UPDATE INV_EXISTENCIA
       SET CANTIDAD_EXISTENCIA_EXIS = CANTIDAD_EXISTENCIA_EXIS + :NEW.CANTIDAD_DEDE,
           FECHA_ULTIMO_MOVIMIENTO_EXIS = SYSDATE,
           USUARIO_MOD_EXIS = USER,
           FECHA_MOD_EXIS = SYSTIMESTAMP
     WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
       AND ID_BODEGA_BODE = v_id_bodega;

    INSERT INTO INV_MOVIMIENTO (
        ID_MOVIMIENTO_MOVI,
        ID_PRODUCTO_PROD,
        ID_BODEGA_BODE,
        ID_TIPO_MOVIMIENTO_TIMO,
        FECHA_HORA_MOVI,
        CANTIDAD_MOVI,
        DOCUMENTO_REFERENCIA_MOVI,
        OBSERVACIONES_MOVI,
        USUARIO_CREA_MOVI,
        FECHA_CREA_MOVI
    ) VALUES (
        SEQ_INV_MOVIMIENTO.NEXTVAL,
        :NEW.ID_PRODUCTO_PROD,
        v_id_bodega,
        3, -- Entrada por Devolucion
        SYSDATE,
        :NEW.CANTIDAD_DEDE,
        'DEV-CLI-' || TO_CHAR(:NEW.ID_DEVOLUCION_CLI),
        'Reintegro a inventario por devolucion cliente #' || :NEW.ID_DEVOLUCION_CLI,
        USER,
        SYSTIMESTAMP
    );
END;
/
SHOW ERRORS TRIGGER TRG_VEN_DEVOLUCION_DET_INV_AI;

-- ----------------------------------------------------------------------------
-- 1.11 TRG_COM_DEVOLUCION_DET_INV_AI
-- Disparador AFTER INSERT ON COM_DEVOLUCION_DET
-- Descuenta existencias de inventario por devolucion al proveedor
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_COM_DEVOLUCION_DET_INV_AI
AFTER INSERT ON COM_DEVOLUCION_DET
FOR EACH ROW
DECLARE
    v_id_bodega NUMBER;
BEGIN
    SELECT ID_BODEGA_BODE
      INTO v_id_bodega
      FROM COM_DEVOLUCION_PROV
     WHERE ID_DEVOLUCION_PROV = :NEW.ID_DEVOLUCION_PROV;

    IF v_id_bodega IS NULL THEN
        SELECT ID_BODEGA_BODE INTO v_id_bodega FROM INV_BODEGA WHERE ESTADO_BODE = 'A' AND ROWNUM = 1;
    END IF;

    UPDATE INV_EXISTENCIA
       SET CANTIDAD_EXISTENCIA_EXIS = GREATEST(0, CANTIDAD_EXISTENCIA_EXIS - :NEW.CANTIDAD_DEDP),
           FECHA_ULTIMO_MOVIMIENTO_EXIS = SYSDATE,
           USUARIO_MOD_EXIS = USER,
           FECHA_MOD_EXIS = SYSTIMESTAMP
     WHERE ID_PRODUCTO_PROD = :NEW.ID_PRODUCTO_PROD
       AND ID_BODEGA_BODE = v_id_bodega;

    INSERT INTO INV_MOVIMIENTO (
        ID_MOVIMIENTO_MOVI,
        ID_PRODUCTO_PROD,
        ID_BODEGA_BODE,
        ID_TIPO_MOVIMIENTO_TIMO,
        FECHA_HORA_MOVI,
        CANTIDAD_MOVI,
        DOCUMENTO_REFERENCIA_MOVI,
        OBSERVACIONES_MOVI,
        USUARIO_CREA_MOVI,
        FECHA_CREA_MOVI
    ) VALUES (
        SEQ_INV_MOVIMIENTO.NEXTVAL,
        :NEW.ID_PRODUCTO_PROD,
        v_id_bodega,
        4, -- Salida por Devolucion a Proveedor
        SYSDATE,
        :NEW.CANTIDAD_DEDP,
        'DEV-PROV-' || TO_CHAR(:NEW.ID_DEVOLUCION_PROV),
        'Salida de inventario por devolucion al proveedor #' || :NEW.ID_DEVOLUCION_PROV,
        USER,
        SYSTIMESTAMP
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
        v_llave := TO_CHAR(:NEW.ID_FACTURA_FAVE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'VENTAS',
            p_tabla       => 'VEN_FACTURA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Insercion de factura #' || :NEW.NUMERO_FACTURA_FAVE || ' por total C' || TO_CHAR(:NEW.TOTAL_FAVE, '999,999,990.00')
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'ESTADO_FAVE', NULL, :NEW.ESTADO_FAVE);
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'TOTAL_FAVE', NULL, TO_CHAR(:NEW.TOTAL_FAVE));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_FAVE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'VENTAS',
            p_tabla       => 'VEN_FACTURA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Modificacion en factura #' || :NEW.NUMERO_FACTURA_FAVE
        );
        IF NVL(:OLD.ESTADO_FAVE, 'X') != NVL(:NEW.ESTADO_FAVE, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'ESTADO_FAVE', :OLD.ESTADO_FAVE, :NEW.ESTADO_FAVE);
        END IF;
        IF NVL(:OLD.TOTAL_FAVE, -1) != NVL(:NEW.TOTAL_FAVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'TOTAL_FAVE', TO_CHAR(:OLD.TOTAL_FAVE), TO_CHAR(:NEW.TOTAL_FAVE));
        END IF;
        IF NVL(:OLD.ES_CREDITO_FAVE, 'X') != NVL(:NEW.ES_CREDITO_FAVE, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('VEN_FACTURA', 'VENTAS', v_operacion, v_llave, 'ES_CREDITO_FAVE', :OLD.ES_CREDITO_FAVE, :NEW.ES_CREDITO_FAVE);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_FACTURA_FAVE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'VENTAS',
            p_tabla       => 'VEN_FACTURA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de factura #' || :OLD.NUMERO_FACTURA_FAVE
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
            p_modulo      => 'COMPRAS',
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Recepcion de compra #' || :NEW.NUMERO_FACTURA_FACO || ' por C' || TO_CHAR(:NEW.TOTAL_FACO, '999,999,990.00')
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'ESTADO_FACO', NULL, :NEW.ESTADO_FACO);
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'TOTAL_FACO', NULL, TO_CHAR(:NEW.TOTAL_FACO));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_FACTURA_COMPRA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'COMPRAS',
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_id_usuario  => :NEW.ID_USUARIO_USUA,
            p_id_sucursal => :NEW.ID_SUCURSAL_SUCU,
            p_descripcion => 'Modificacion en factura compra #' || :NEW.NUMERO_FACTURA_FACO
        );
        IF NVL(:OLD.ESTADO_FACO, 'X') != NVL(:NEW.ESTADO_FACO, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'ESTADO_FACO', :OLD.ESTADO_FACO, :NEW.ESTADO_FACO);
        END IF;
        IF NVL(:OLD.TOTAL_FACO, -1) != NVL(:NEW.TOTAL_FACO, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('COM_FACTURA_COMPRA', 'COMPRAS', v_operacion, v_llave, 'TOTAL_FACO', TO_CHAR(:OLD.TOTAL_FACO), TO_CHAR(:NEW.TOTAL_FACO));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_FACTURA_COMPRA);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'COMPRAS',
            p_tabla       => 'COM_FACTURA_COMPRA',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de factura compra #' || :OLD.NUMERO_FACTURA_FACO
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
        v_llave := TO_CHAR(:NEW.ID_PRODUCTO_PROD);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'CATALOGO',
            p_tabla       => 'PRO_PRODUCTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Nuevo producto: ' || :NEW.CODIGO_BARRAS_PROD || ' - ' || :NEW.NOMBRE_PROD
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_COSTO', NULL, TO_CHAR(:NEW.PRECIO_COSTO_PROD));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_VENTA', NULL, TO_CHAR(:NEW.PRECIO_VENTA_PROD));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'ESTADO_PROD', NULL, :NEW.ESTADO_PROD);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PRODUCTO_PROD);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'CATALOGO',
            p_tabla       => 'PRO_PRODUCTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de datos de producto ' || :NEW.CODIGO_BARRAS_PROD
        );
        IF NVL(:OLD.PRECIO_COSTO_PROD, -1) != NVL(:NEW.PRECIO_COSTO_PROD, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_COSTO', TO_CHAR(:OLD.PRECIO_COSTO_PROD), TO_CHAR(:NEW.PRECIO_COSTO_PROD));
        END IF;
        IF NVL(:OLD.PRECIO_VENTA_PROD, -1) != NVL(:NEW.PRECIO_VENTA_PROD, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'PRECIO_VENTA', TO_CHAR(:OLD.PRECIO_VENTA_PROD), TO_CHAR(:NEW.PRECIO_VENTA_PROD));
        END IF;
        IF NVL(:OLD.ESTADO_PROD, 'X') != NVL(:NEW.ESTADO_PROD, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'ESTADO_PROD', :OLD.ESTADO_PROD, :NEW.ESTADO_PROD);
        END IF;
        IF NVL(:OLD.NOMBRE_PROD, 'X') != NVL(:NEW.NOMBRE_PROD, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRO_PRODUCTO', 'CATALOGO', v_operacion, v_llave, 'NOMBRE_PROD', :OLD.NOMBRE_PROD, :NEW.NOMBRE_PROD);
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PRODUCTO_PROD);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'CATALOGO',
            p_tabla       => 'PRO_PRODUCTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de producto ' || :OLD.CODIGO_BARRAS_PROD || ' - ' || :OLD.NOMBRE_PROD
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
        v_llave := TO_CHAR(:NEW.ID_MOVIMIENTO_MOVI);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'INVENTARIO',
            p_tabla       => 'INV_MOVIMIENTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Movimiento tipo ' || :NEW.ID_TIPO_MOVIMIENTO_TIMO || ' de ' || :NEW.CANTIDAD_MOVI || ' unidades. Ref: ' || :NEW.DOCUMENTO_REFERENCIA_MOVI
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('INV_MOVIMIENTO', 'INVENTARIO', v_operacion, v_llave, 'CANTIDAD_MOVI', NULL, TO_CHAR(:NEW.CANTIDAD_MOVI));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('INV_MOVIMIENTO', 'INVENTARIO', v_operacion, v_llave, 'BODEGA_DESTINO', NULL, TO_CHAR(:NEW.ID_BODEGA_BODE));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_MOVIMIENTO_MOVI);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'INVENTARIO',
            p_tabla       => 'INV_MOVIMIENTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Modificacion en movimiento kardex #' || v_llave
        );
        IF NVL(:OLD.CANTIDAD_MOVI, -1) != NVL(:NEW.CANTIDAD_MOVI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('INV_MOVIMIENTO', 'INVENTARIO', v_operacion, v_llave, 'CANTIDAD_MOVI', TO_CHAR(:OLD.CANTIDAD_MOVI), TO_CHAR(:NEW.CANTIDAD_MOVI));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_MOVIMIENTO_MOVI);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'INVENTARIO',
            p_tabla       => 'INV_MOVIMIENTO',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de movimiento kardex #' || v_llave
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('INV_MOVIMIENTO', 'INVENTARIO', v_operacion, v_llave, 'REGISTRO_ELIMINADO', TO_CHAR(:OLD.CANTIDAD_MOVI), 'ELIMINADO');
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
        v_llave := TO_CHAR(:NEW.ID_CLIENTE_CLIE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PERSONAS',
            p_tabla       => 'PER_CLIENTE',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Cliente registrado: ' || :NEW.CODIGO_CLIENTE_CLIE || ' - ' || :NEW.NOMBRE_COMPLETO_CLIE
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'MONTO_MAX_CREDITO', NULL, TO_CHAR(:NEW.MONTO_MAX_CREDITO_CLI));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'ESTADO_CLI', NULL, :NEW.ESTADO_CLI);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_CLIENTE_CLIE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PERSONAS',
            p_tabla       => 'PER_CLIENTE',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de datos cliente ' || :NEW.NOMBRE_COMPLETO_CLIE
        );
        IF NVL(:OLD.MONTO_MAX_CREDITO_CLI, -1) != NVL(:NEW.MONTO_MAX_CREDITO_CLI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'MONTO_MAX_CREDITO', TO_CHAR(:OLD.MONTO_MAX_CREDITO_CLI), TO_CHAR(:NEW.MONTO_MAX_CREDITO_CLI));
        END IF;
        IF NVL(:OLD.SALDO_ACTUAL_CLI, -1) != NVL(:NEW.SALDO_ACTUAL_CLI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'SALDO_ACTUAL', TO_CHAR(:OLD.SALDO_ACTUAL_CLI), TO_CHAR(:NEW.SALDO_ACTUAL_CLI));
        END IF;
        IF NVL(:OLD.ESTADO_CLI, 'X') != NVL(:NEW.ESTADO_CLI, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'ESTADO_CLI', :OLD.ESTADO_CLI, :NEW.ESTADO_CLI);
        END IF;
        IF NVL(:OLD.PLAZO_CREDITO_DIAS_CLI, -1) != NVL(:NEW.PLAZO_CREDITO_DIAS_CLI, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'PLAZO_CREDITO_DIAS', TO_CHAR(:OLD.PLAZO_CREDITO_DIAS_CLI), TO_CHAR(:NEW.PLAZO_CREDITO_DIAS_CLI));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_CLIENTE_CLIE);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PERSONAS',
            p_tabla       => 'PER_CLIENTE',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de cliente ' || :OLD.NOMBRE_COMPLETO_CLIE
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_CLIENTE', 'PERSONAS', v_operacion, v_llave, 'REGISTRO_ELIMINADO', :OLD.NOMBRE_COMPLETO_CLIE, 'ELIMINADO');
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
        v_llave := TO_CHAR(:NEW.ID_PROVEEDOR_PROV);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PROVEEDORES',
            p_tabla       => 'PER_PROVEEDOR',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Proveedor registrado: ' || :NEW.CODIGO_PROVEEDOR_PROV || ' - ' || :NEW.NOMBRE_COMERCIAL_PROV
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'LIMITE_CREDITO', NULL, TO_CHAR(:NEW.LIMITE_CREDITO_PROVE));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'ESTADO_PROVE', NULL, :NEW.ESTADO_PROVE);
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PROVEEDOR_PROV);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PROVEEDORES',
            p_tabla       => 'PER_PROVEEDOR',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Actualizacion de datos proveedor ' || :NEW.NOMBRE_COMERCIAL_PROV
        );
        IF NVL(:OLD.LIMITE_CREDITO_PROVE, -1) != NVL(:NEW.LIMITE_CREDITO_PROVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'LIMITE_CREDITO', TO_CHAR(:OLD.LIMITE_CREDITO_PROVE), TO_CHAR(:NEW.LIMITE_CREDITO_PROVE));
        END IF;
        IF NVL(:OLD.SALDO_ACTUAL_PROVE, -1) != NVL(:NEW.SALDO_ACTUAL_PROVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'SALDO_ACTUAL', TO_CHAR(:OLD.SALDO_ACTUAL_PROVE), TO_CHAR(:NEW.SALDO_ACTUAL_PROVE));
        END IF;
        IF NVL(:OLD.ESTADO_PROVE, 'X') != NVL(:NEW.ESTADO_PROVE, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'ESTADO_PROVE', :OLD.ESTADO_PROVE, :NEW.ESTADO_PROVE);
        END IF;
        IF NVL(:OLD.PLAZO_CREDITO_DIAS_PROVE, -1) != NVL(:NEW.PLAZO_CREDITO_DIAS_PROVE, -1) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'PLAZO_CREDITO_DIAS', TO_CHAR(:OLD.PLAZO_CREDITO_DIAS_PROVE), TO_CHAR(:NEW.PLAZO_CREDITO_DIAS_PROVE));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PROVEEDOR_PROV);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'PROVEEDORES',
            p_tabla       => 'PER_PROVEEDOR',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de proveedor ' || :OLD.NOMBRE_COMERCIAL_PROV
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PER_PROVEEDOR', 'PROVEEDORES', v_operacion, v_llave, 'REGISTRO_ELIMINADO', :OLD.NOMBRE_COMERCIAL_PROV, 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PER_PROVEEDOR;

-- ----------------------------------------------------------------------------
-- 2.7 TRG_AUD_PRM_PROMOCION
-- Tabla 7: PRM_PROMOCION (Auditoria de promociones, campanas y descuentos)
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
        v_llave := TO_CHAR(:NEW.ID_PROMOCION_PROM);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'MERCADEO',
            p_tabla       => 'PRM_PROMOCION',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Nueva campana promocional: ' || :NEW.CODIGO_PROMOCION_PROM || ' - ' || :NEW.NOMBRE_PROM
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'ESTADO_PROM', NULL, :NEW.ESTADO_PROM);
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'FECHA_INICIO', NULL, TO_CHAR(:NEW.FECHA_INICIO_PROM, 'YYYY-MM-DD'));
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'FECHA_FIN', NULL, TO_CHAR(:NEW.FECHA_FIN_PROM, 'YYYY-MM-DD'));
    ELSIF UPDATING THEN
        v_operacion := 'UPDATE';
        v_llave := TO_CHAR(:NEW.ID_PROMOCION_PROM);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'MERCADEO',
            p_tabla       => 'PRM_PROMOCION',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Modificacion en promocion ' || :NEW.NOMBRE_PROM
        );
        IF NVL(:OLD.ESTADO_PROM, 'X') != NVL(:NEW.ESTADO_PROM, 'X') THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'ESTADO_PROM', :OLD.ESTADO_PROM, :NEW.ESTADO_PROM);
        END IF;
        IF NVL(:OLD.FECHA_FIN_PROM, SYSDATE) != NVL(:NEW.FECHA_FIN_PROM, SYSDATE) THEN
            PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'FECHA_FIN', TO_CHAR(:OLD.FECHA_FIN_PROM, 'YYYY-MM-DD'), TO_CHAR(:NEW.FECHA_FIN_PROM, 'YYYY-MM-DD'));
        END IF;
    ELSIF DELETING THEN
        v_operacion := 'DELETE';
        v_llave := TO_CHAR(:OLD.ID_PROMOCION_PROM);
        PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION (
            p_modulo      => 'MERCADEO',
            p_tabla       => 'PRM_PROMOCION',
            p_operacion   => v_operacion,
            p_llave       => v_llave,
            p_descripcion => 'Eliminacion de campana promocional ' || :OLD.NOMBRE_PROM
        );
        PKG_AUD_CONTROL.PR_REGISTRAR_CAMBIO('PRM_PROMOCION', 'MERCADEO', v_operacion, v_llave, 'REGISTRO_ELIMINADO', :OLD.NOMBRE_PROM, 'ELIMINADO');
    END IF;
END;
/
SHOW ERRORS TRIGGER TRG_AUD_PRM_PROMOCION;


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
    
    IF v_total_invalidos = 0 AND v_total_validos >= 17 THEN
        DBMS_OUTPUT.PUT_LINE('>>> VERIFICACION EXITOSA: Todos los disparadores de negocio y auditoria');
        DBMS_OUTPUT.PUT_LINE('    fueron compilados correctamente y se encuentran activos.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('>>> ADVERTENCIA: Verifique posibles errores de compilacion.');
    END IF;
END;
/

PROMPT ============================================================================
PROMPT FIN DE COMPILACION DE DISPARADORES — AVANCE 2
PROMPT ============================================================================
