# Pruebas en vivo (si el profesor pide "haga esto")

Comandos listos para copiar y pegar, ordenados por lo que el profesor probablemente pida.
**Todos se probaron en la base real (9 nov 2026)** y debajo de cada uno está lo que debe salir.
Se pueden repetir: los números de factura y de cliente llevan la hora, así que no chocan.

**Dónde se pegan:** en la PC principal, `menu.ps1` → **opción 9** (consola SQL del proyecto).
Esa consola ya entra a `PDBCADENA`, al esquema `CADENA_NEG` y con `SERVEROUTPUT ON`.
Pegue cada bloque completo; los que terminan en `/` se ejecutan al pegar esa última línea.
Las pruebas 4, 5 y 6 se hacen **en la misma consola y en ese orden** (comparten la factura).

| Si el profesor pide... | Prueba |
| :--- | :-: |
| "Muestre que todo está compilado" | 1 |
| "Busque una persona en el padrón" | 2 |
| "Registre un cliente nuevo" | 3 |
| "Haga una venta a crédito" / "¿se actualizan las cuentas por cobrar y el inventario?" | 4 |
| "Pague esa factura" / "¿cambia el estado solo?" | 5 |
| "Haga una devolución" | 6 |
| "Haga una compra a un proveedor y páguela" | 7 |
| "Cambie un precio" / "¿dónde queda el historial?" | 8 |
| "Intente pasar el límite de crédito" / "vender sin existencia" | 9 |
| "Muéstreme la bitácora de lo que hicimos" | 10 |
| "¿Eso llegó a la standby?" | 11 |
| "Refresque las vistas materializadas" | 12 |
| "Dos cajeros venden lo mismo a la vez" (concurrencia) | 13 |
| "Entre como un usuario con permisos limitados" | 14 |
| "Mande una notificación" | 15 |

---

## 1. Todo compilado

```sql
SELECT COUNT(*) AS invalidos FROM all_objects WHERE owner = 'CADENA_NEG' AND status <> 'VALID';
SELECT job_name, state FROM user_scheduler_jobs ORDER BY 1;
```

**Debe salir:** `INVALIDOS = 0` y los 11 jobs.

> Si aparece 1 inválido y es `MV_INVENTARIO_CONSOLIDADO`, es normal después de muchos cambios en
> inventario: la vista materializada queda pendiente hasta refrescarse (prueba 12, o el cierre de las 23:00).

## 2. Buscar una persona en el padrón del TSE

```sql
COLUMN nombre FORMAT A40
COLUMN lugar FORMAT A50
SELECT cedula_padr, nombre_padr || ' ' || apellido1_padr || ' ' || apellido2_padr AS nombre,
       provincia_diel || ', ' || canton_diel || ', ' || distrito_diel AS lugar, estado_padr
  FROM V_PADRON_DETALLE WHERE cedula_padr = '101053316';
SELECT COUNT(*) AS personas_en_el_padron FROM CAT_PADRON;
```

**Debe salir:** `101053316  LUCILA PORRAS AGUERO  SAN JOSE, PURISCAL, GRIFO ALTO  A` y `3762245`
personas. Cambie la cédula por la que diga el profesor (la de él mismo, por ejemplo).

## 3. Registrar un cliente nuevo desde el padrón

Toma una cédula real del padrón que todavía no es cliente y crea la persona y el cliente con su nombre oficial.

```sql
DECLARE
    v_cedula  CAT_PADRON.CEDULA_PADR%TYPE;
    v_codigo  VARCHAR2(20) := 'CLI-P' || TO_CHAR(SYSDATE, 'DDHH24MISS');
    v_id      NUMBER;
BEGIN
    SELECT cedula_padr INTO v_cedula FROM CAT_PADRON p
     WHERE estado_padr = 'A' AND NOT EXISTS (SELECT 1 FROM PER_CLIENTE c WHERE c.id_padron = p.id_padron)
       AND ROWNUM = 1;
    -- Solo un cliente preferencial ('S') puede tener credito (regla CK_CLI_CRED_PREF)
    PKG_PER_PADRON.PR_CREAR_CLIENTE_DESDE_PADRON(v_cedula, v_codigo, 'S', 200000, 30, v_id);
    DBMS_OUTPUT.PUT_LINE('Cliente creado: id ' || v_id || ', codigo ' || v_codigo || ', cedula ' || v_cedula);
END;
/
COLUMN cliente FORMAT A40
SELECT c.id_cliente, c.codigo_cli, f.nombre_pefi || ' ' || f.apellido1_pefi || ' ' || f.apellido2_pefi AS cliente,
       c.monto_max_credito_cli AS limite, p.cedula_padr
  FROM PER_CLIENTE c JOIN PER_PERSONA_FISICA f ON f.id_persona_fisica = c.id_persona
  JOIN CAT_PADRON p ON p.id_padron = c.id_padron
 WHERE c.id_cliente = (SELECT MAX(id_cliente) FROM PER_CLIENTE);
```

**Debe salir:** `[OK] Cliente CLI-P... (NOMBRE APELLIDO) enlazado con el Padron Nacional` y una fila
con el nombre tomado del padrón, límite `200000` y la cédula.
Para una cédula concreta, cambie el `SELECT ... INTO v_cedula` por `v_cedula := '1XXXXXXXX';`.

## 4. Venta a crédito (cuenta por cobrar, saldo e inventario automáticos)

```sql
VARIABLE fac NUMBER
DECLARE
    v_saldo_antes NUMBER; v_exis_antes VARCHAR2(200); v_saldo NUMBER; v_exis VARCHAR2(200);
    v_num VARCHAR2(30) := 'FAC-PROF-' || TO_CHAR(SYSDATE, 'DDHH24MISS');
    v_estado VARCHAR2(1); v_cxc NUMBER;
BEGIN
    SELECT saldo_actual_cli INTO v_saldo_antes FROM PER_CLIENTE WHERE id_cliente = 3;
    SELECT LISTAGG('bodega ' || id_bodega || ': ' || cantidad_exis, ', ') WITHIN GROUP (ORDER BY id_bodega) INTO v_exis_antes FROM INV_EXISTENCIA WHERE id_producto = 1;
    PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA(
        p_id_cliente => 3, p_id_sucursal => 1, p_id_usuario => 1, p_num_factura => v_num,
        p_es_credito => 'S', p_subtotal => 20000, p_descuento => 0, p_impuesto => 2600,
        p_id_factura_out => :fac);
    PKG_VEN_OPERACION.PR_AGREGAR_DETALLE_VENTA(
        p_id_factura_venta => :fac, p_id_producto => 1, p_id_servicio => NULL, p_id_lote => NULL,
        p_linea => 1, p_cantidad => 5, p_precio_unitario => 4000);
    SELECT saldo_actual_cli INTO v_saldo FROM PER_CLIENTE WHERE id_cliente = 3;
    SELECT LISTAGG('bodega ' || id_bodega || ': ' || cantidad_exis, ', ') WITHIN GROUP (ORDER BY id_bodega) INTO v_exis FROM INV_EXISTENCIA WHERE id_producto = 1;
    SELECT estado_fave INTO v_estado FROM VEN_FACTURA WHERE id_factura_venta = :fac;
    SELECT saldo_cuco INTO v_cxc FROM VEN_CUENTA_COBRAR WHERE id_factura_venta = :fac;
    DBMS_OUTPUT.PUT_LINE('Factura ' || v_num || ' (id ' || :fac || '), estado ' || v_estado);
    DBMS_OUTPUT.PUT_LINE('Saldo del cliente: ' || v_saldo_antes || ' -> ' || v_saldo);
    DBMS_OUTPUT.PUT_LINE('Existencia del producto 1 (la sucursal 1 vende desde su bodega principal, la 2):');
    DBMS_OUTPUT.PUT_LINE('   antes:   ' || v_exis_antes);
    DBMS_OUTPUT.PUT_LINE('   despues: ' || v_exis);
    DBMS_OUTPUT.PUT_LINE('Cuenta por cobrar creada con saldo ' || v_cxc);
END;
/
```

**Debe salir** (los números varían):

```
[PROMOCION AUTOMATICA] Se otorgaron 2 accion(es) en la promocion "Acumula millas Super Brunca" ...
Factura FAC-PROF-09054442 (id 14), estado P
Saldo del cliente: 41500 -> 64100
Existencia del producto 1 (la sucursal 1 vende desde su bodega principal, la 2):
   antes:   bodega 1: 105, bodega 2: 8
   despues: bodega 1: 105, bodega 2: 3
Cuenta por cobrar creada con saldo 22600
```

Qué explicar: la factura queda **P** (pendiente), el trigger `TRG_VEN_FACTURA_CRED_AI` crea la cuenta
por cobrar y sube el saldo del cliente, y `TRG_VEN_FACTURA_DET_INV_AI` baja 5 unidades en la bodega de
la sucursal y registra el kardex. La promoción da acciones automáticamente.

## 5. Pagar la factura completa (cambio de estado automático)

```sql
DECLARE
    v_estado VARCHAR2(1); v_cxc NUMBER;
BEGIN
    PKG_VEN_OPERACION.PR_REGISTRAR_ABONO_COBRAR(:fac, 1, 'EFECTIVO', 'REC-PROF-' || TO_CHAR(SYSDATE, 'DDHH24MISS'), 22600);
    SELECT estado_fave INTO v_estado FROM VEN_FACTURA WHERE id_factura_venta = :fac;
    SELECT saldo_cuco INTO v_cxc FROM VEN_CUENTA_COBRAR WHERE id_factura_venta = :fac;
    DBMS_OUTPUT.PUT_LINE('Estado de la factura: ' || v_estado || ' (C = cancelada); saldo de la cuenta: ' || v_cxc);
END;
/
```

**Debe salir:** `Estado de la factura: C (C = cancelada); saldo de la cuenta: 0`.
Para un abono parcial, cambie `22600` por un monto menor: la factura sigue en `P`.

## 6. Devolución de una unidad (vuelve al inventario)

```sql
DECLARE
    v_antes NUMBER; v_despues NUMBER;
BEGIN
    SELECT cantidad_exis INTO v_antes FROM INV_EXISTENCIA WHERE id_producto = 1 AND id_bodega = 2;
    INSERT INTO VEN_DEVOLUCION (ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, MOTIVO_DEVV)
    VALUES (:fac, 2, 1, 'DEV-PROF-' || TO_CHAR(SYSDATE, 'DDHH24MISS'), 'Prueba en la defensa');
    INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
    SELECT SEQ_VEN_DEVOLUCION.CURRVAL, ID_FACTURA_VENTA_DET, 1 FROM VEN_FACTURA_DET WHERE ID_FACTURA_VENTA = :fac;
    COMMIT;
    SELECT cantidad_exis INTO v_despues FROM INV_EXISTENCIA WHERE id_producto = 1 AND id_bodega = 2;
    DBMS_OUTPUT.PUT_LINE('Existencia del producto 1 en la bodega 2: ' || v_antes || ' -> ' || v_despues);
END;
/
```

**Debe salir:** `Existencia del producto 1 en la bodega 2: 3 -> 4` (sube 1).

## 7. Compra a un proveedor a crédito y pago

```sql
VARIABLE fco NUMBER
DECLARE
    v_saldo_antes NUMBER; v_exis_antes NUMBER; v_saldo NUMBER; v_exis NUMBER; v_cxp NUMBER; v_estado VARCHAR2(1);
    v_num VARCHAR2(30) := 'FC-PROF-' || TO_CHAR(SYSDATE, 'DDHH24MISS');
BEGIN
    SELECT saldo_actual_prove INTO v_saldo_antes FROM PER_PROVEEDOR WHERE id_proveedor = 4;
    SELECT cantidad_exis INTO v_exis_antes FROM INV_EXISTENCIA WHERE id_producto = 2 AND id_bodega = 1;
    PKG_COM_OPERACION.PR_CREAR_FACTURA_COMPRA(
        p_id_proveedor => 4, p_id_bodega => 1, p_id_usuario => 1, p_num_factura => v_num,
        p_es_credito => 'S', p_subtotal => 5200, p_descuento => 0, p_impuesto => 676,
        p_id_factura_out => :fco);
    PKG_COM_OPERACION.PR_AGREGAR_DETALLE_COMPRA(
        p_id_factura_compra => :fco, p_id_producto => 2, p_id_lote => NULL, p_linea => 1,
        p_cantidad => 10, p_costo_unitario => 520);
    SELECT saldo_actual_prove INTO v_saldo FROM PER_PROVEEDOR WHERE id_proveedor = 4;
    SELECT cantidad_exis INTO v_exis FROM INV_EXISTENCIA WHERE id_producto = 2 AND id_bodega = 1;
    SELECT saldo_cupa INTO v_cxp FROM COM_CUENTA_PAGAR WHERE id_factura_compra = :fco;
    DBMS_OUTPUT.PUT_LINE('Compra ' || v_num || ' (id ' || :fco || ')');
    DBMS_OUTPUT.PUT_LINE('Saldo con el proveedor 4: ' || v_saldo_antes || ' -> ' || v_saldo);
    DBMS_OUTPUT.PUT_LINE('Existencia del producto 2: ' || v_exis_antes || ' -> ' || v_exis);
    DBMS_OUTPUT.PUT_LINE('Cuenta por pagar creada con saldo ' || v_cxp);
    PKG_COM_OPERACION.PR_REGISTRAR_ABONO_PAGAR(:fco, 1, 'CMP-PROF-' || TO_CHAR(SYSDATE, 'DDHH24MISS'), v_cxp);
    SELECT estado_faco INTO v_estado FROM COM_FACTURA_COMPRA WHERE id_factura_compra = :fco;
    DBMS_OUTPUT.PUT_LINE('Despues de pagarla completa, estado de la compra: ' || v_estado);
END;
/
```

**Debe salir:** saldo con el proveedor `0 -> 5876`, existencia del producto 2 sube 10, cuenta por pagar
de `5876` y, tras el pago, estado `C`.

## 8. Cambio de precio: historial y bitácora

```sql
UPDATE PRO_PRODUCTO SET PRECIO_COSTO_PROD = PRECIO_COSTO_PROD + 100 WHERE ID_PRODUCTO = 1;
COMMIT;
SELECT id_precio_hist, costo_anterior_prhi, fecha_cambio_prhi FROM PRO_PRECIO_HIST
 WHERE ID_PRODUCTO = 1 ORDER BY 1 DESC FETCH FIRST 2 ROWS ONLY;
```

**Debe salir:** una fila nueva en `PRO_PRECIO_HIST` con el costo anterior (lo guarda el trigger
`TRG_PRO_HISTORIAL_PRECIO_AU`). La prueba 10 muestra el mismo cambio en la bitácora.

## 9. Reglas que rechazan operaciones (y no dejan nada a medias)

```sql
DECLARE
    v_id NUMBER; v_n NUMBER;
BEGIN
    BEGIN
        PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA(4, 1, 1, 'FAC-PROF-EXCESO', 'S', 50000000, 0, 6500000, v_id);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Venta rechazada: ' || SQLERRM);
    END;
    SELECT COUNT(*) INTO v_n FROM VEN_FACTURA WHERE num_factura_fave = 'FAC-PROF-EXCESO';
    DBMS_OUTPUT.PUT_LINE('Facturas guardadas con ese numero: ' || v_n);
    BEGIN
        PKG_COM_OPERACION.PR_CREAR_FACTURA_COMPRA(4, 1, 1, 'FC-PROF-EXCESO', 'S', 5000000, 0, 650000, v_id);
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Compra rechazada: ' || SQLERRM);
    END;
    BEGIN
        PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA(p_id_bodega => 1, p_id_producto => 1, p_id_lote => NULL,
            p_cantidad => 999999, p_es_entrada => 'N', p_tipo_movi => 'VENTA', p_documento_ref => 'PRUEBA-SIN-STOCK');
    EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Salida rechazada: ' || SQLERRM);
    END;
END;
/
```

**Debe salir:**

```
Venta rechazada: ORA-20010: Limite de credito excedido para el cliente CLI-000003. Maximo: C 300,000.00 ...
Facturas guardadas con ese numero: 0
Compra rechazada: ORA-20018: Limite de credito otorgado por proveedor PRV-0004 excedido ...
Salida rechazada: ORA-20015: Existencia insuficiente en la bodega 1 para el producto 1 (Disponible: 105, Solicitado: 999999).
```

Cada código tiene un solo significado (catálogo en la sección 5.2 del Manual Técnico).

## 10. La bitácora de lo que se acaba de hacer

```sql
COLUMN tabla_reca FORMAT A20
COLUMN campo_modificado_reca FORMAT A22
COLUMN valor_anterior_reca FORMAT A14
COLUMN valor_nuevo_reca FORMAT A14
COLUMN usuario_crea_reca FORMAT A10
SELECT tabla_reca, operacion_reca, campo_modificado_reca, valor_anterior_reca, valor_nuevo_reca, usuario_crea_reca
  FROM AUD_REGISTRO_CAMBIO ORDER BY id_registro_cambio DESC FETCH FIRST 8 ROWS ONLY;
COLUMN mensaje FORMAT A80
SELECT subprograma_ersi, codigo_sql_ersi, SUBSTR(mensaje_error_ersi, 1, 80) AS mensaje
  FROM AUD_ERROR_SISTEMA ORDER BY id_error_sistema DESC FETCH FIRST 4 ROWS ONLY;
```

**Debe salir:** los cambios de las pruebas anteriores (precio `2000 -> 2100`, estados `P -> C`,
saldos) con usuario, y en la bitácora de errores los tres rechazos de la prueba 9 (`-20015`, `-20018`,
`-20010`): se guardan aunque la operación se deshizo, gracias a `PRAGMA AUTONOMOUS_TRANSACTION`.

## 11. ¿Llegó a la standby?

En la **PC 2**, `menu.ps1` → **opción 9** (la standby está en solo lectura, así que solo se consulta):

```sql
SELECT num_factura_fave, estado_fave FROM VEN_FACTURA WHERE num_factura_fave LIKE 'FAC-PROF-%' ORDER BY 1;
SELECT codigo_cli FROM PER_CLIENTE WHERE codigo_cli LIKE 'CLI-P%';
```

**Debe salir:** las mismas facturas y clientes creados en la PC 1, a los pocos segundos. Para
comprobar la conexión con un veredicto claro: **opción 14** del menú en cualquiera de las dos PC.

## 12. Vistas materializadas

```sql
EXEC DBMS_MVIEW.REFRESH('MV_VENTAS_MENSUALES', 'C');
EXEC DBMS_MVIEW.REFRESH('MV_INVENTARIO_CONSOLIDADO', 'C');
SELECT periodo_mensual, codigo_suc, total_facturas, total_ventas_mensual FROM MV_VENTAS_MENSUALES ORDER BY 1 DESC, 2;
SELECT * FROM MV_INVENTARIO_CONSOLIDADO;
```

**Debe salir:** el mes actual ya incluye las ventas de las pruebas. Se refrescan solas en el cierre
diario de las 23:00 (`REFRESH COMPLETE ON DEMAND`).

## 13. Concurrencia: dos cajeros a la vez

Abra **dos** consolas (opción 9 en dos ventanas de la PC 1).

**Consola A** (simula un cajero a mitad de una venta; deja la fila bloqueada):

```sql
SELECT cantidad_exis FROM INV_EXISTENCIA WHERE id_producto = 1 AND id_bodega = 2 FOR UPDATE;
```

**Consola B** (otro cajero intenta vender lo mismo):

```sql
BEGIN
  PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA(p_id_bodega => 2, p_id_producto => 1, p_id_lote => NULL,
      p_cantidad => 1, p_es_entrada => 'N', p_tipo_movi => 'VENTA', p_documento_ref => 'PRUEBA-CONCURRENCIA');
  DBMS_OUTPUT.PUT_LINE('No quedo bloqueado');
EXCEPTION WHEN OTHERS THEN DBMS_OUTPUT.PUT_LINE('Segunda sesion: ' || SQLERRM);
END;
/
```

**Debe salir en B, a los 5 segundos:** `ORA-20016: El registro de inventario esta siendo modificado por otro
cajero. Intente nuevamente.` (usa `SELECT ... FOR UPDATE WAIT 5`: espera hasta 5 segundos y, si la fila
sigue bloqueada, avisa en lugar de quedarse colgado). Los abonos usan `FOR UPDATE NOWAIT`, que responde de inmediato.
Luego en **A**: `ROLLBACK;`. Si repite el bloque en B, ahora sí pasa.

## 14. Usuario con permisos limitados (roles con clave)

En una terminal de la PC 1 (la clave del usuario está en `sql/05_Seguridad_Perfiles_Roles_Usuarios.sql`):

```powershell
docker exec -it -u oracle ora_principal sqlplus USR_DIGITADOR@localhost:1521/PDBCADENA
```

```sql
SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO;                 -- ORA-00942: sin el rol no ve nada
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');      -- descifra la clave del rol y lo activa
SELECT role FROM session_roles;                               -- ROL_DIGITADOR
SELECT COUNT(*) AS productos FROM CADENA_NEG.PRO_PRODUCTO;    -- ahora si: 8
DELETE FROM CADENA_NEG.PRO_PRODUCTO WHERE ID_PRODUCTO = -1;   -- ORA-01031: privilegios insuficientes
UPDATE CADENA_NEG.PER_PROVEEDOR SET ESTADO_PROVE = ESTADO_PROVE WHERE 1 = 0;  -- ORA-00942: no le toca
EXIT
```

## 15. Mandar una notificación

`menu.ps1` → **opción 13** y elegir el aviso (muestra el asunto y si se entregó). Para cambiar a quién
llegan (por ejemplo, el correo que dé el profesor): **opción 11**.

---

**Si algo falla:** el código `ORA-200xx` dice qué regla se incumplió (Manual Técnico, sección 5.2).
Si una venta da `ORA-20015` (sin existencia), haga primero la compra de la prueba 7 con el producto de esa venta.
