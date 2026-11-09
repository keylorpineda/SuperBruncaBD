# Modelo relacional (Avance 2)

`modelo_relacional_avance2.dbml` es el modelo completo del esquema `CADENA_NEG`, generado
desde la base real (Oracle 21c EE) con el diccionario de datos: 61 tablas del modelo (el
diccionario de `CADENA_NEG` muestra 65 porque suma 2 tablas externas del padrón TSE y los 2
contenedores de las vistas materializadas, que no son entidades del modelo), 104 relaciones
(9 de ellas compuestas), comentarios de cada tabla y columna, y las 12 tablas nuevas del
Avance 2 marcadas con `[AVANCE 2]` en su nota.

**Diagrama:** [`Diagrama_Modelo_Relacional_Avance2.pdf`](Diagrama_Modelo_Relacional_Avance2.pdf) es el diagrama exportado de dbdiagram.io (coincide con el DBML: 61 tablas, 728 columnas y 104 relaciones). Se ve mejor en pantalla con zoom que impreso.

**Diccionario de datos:** `Diccionario_de_Datos_Avance2.pdf`, generado desde la base instalada: cada tabla con sus columnas (tipo, nulo, valor por defecto, llave y descripción) y sus restricciones. Marca con *AVANCE 2* las 12 tablas nuevas y las 3 columnas agregadas a tablas del Entregable 1 (`SALDO_ACTUAL_CLI`, `ID_PADRON` y `SALDO_ACTUAL_PROVE`).

**Cómo abrirlo:** entre a https://dbdiagram.io, cree un diagrama nuevo, borre el ejemplo y
pegue el contenido del archivo (o *Import → DBML*). Las tablas quedan agrupadas por módulo
(`TableGroup`: AUD, CAT, COM, INV, PER, PRM, PRO, SEG, VEN).

Avisos normales del editor: "Mismatched optional ref constraints" en llaves foráneas que
permiten nulos (por ejemplo `CAT_PADRON.ID_DISTRITO`, que es opcional a propósito). No son errores.

No incluye las tablas externas `EXT_PADRON_TSE` / `EXT_DISTELEC_TSE` (leen archivos del TSE,
no guardan datos) ni las vistas.

## Desnormalizaciones del Avance 2

El modelo del Entregable 1 está en quinta forma normal (5FN) con **dos desnormalizaciones
declaradas** (sección 6 de la Documentación Técnica del Entregable 1):

1. El tipo de persona copiado en cada subtipo (`TIPO_PERS` / `ES_JURIDICA_PERS`), que permite la
   llave foránea compuesta que garantiza que un proveedor sea siempre persona jurídica.
2. El monto abonado y el saldo de cada cuenta por cobrar y por pagar, que podrían calcularse
   sumando los abonos.

El Avance 2 conserva esas dos y agrega las siguientes, todas **a propósito y controladas**:
cada valor repetido lo mantiene un trigger o un procedimiento del sistema, nunca se escribe a
mano, y siempre se puede recalcular desde su origen.

| # | Dato repetido | De dónde se puede calcular | Por qué se guarda | Quién lo mantiene |
| :-: | :--- | :--- | :--- | :--- |
| 1 | `PER_CLIENTE.SALDO_ACTUAL_CLI` | Suma de `SALDO_CUCO` de las cuentas por cobrar pendientes o con abonos del cliente (estados `P` y `A`) | El enunciado pide validar el límite de crédito en **cada** venta; leer una columna es inmediato, sumar toda la historia no | `TRG_VEN_FACTURA_CRED_AI` (suma) y `TRG_VEN_ABONO_SALDO_AI` (resta) |
| 2 | `PER_PROVEEDOR.SALDO_ACTUAL_PROVE` | Suma de `SALDO_CUPA` de las cuentas por pagar pendientes o con abonos con el proveedor | Igual que el anterior, para el límite de crédito que da el proveedor y la alerta del 70 % | `TRG_COM_FACTURA_CRED_AI` y `TRG_COM_ABONO_SALDO_AI` |
| 3 | `MONTO_ABONADO_CUCO` / `SALDO_CUCO` y `MONTO_ABONADO_CUPA` / `SALDO_CUPA` | Monto original menos la suma de los abonos | Es la desnormalización 2 del Entregable 1, ahora en las tablas `VEN_CUENTA_COBRAR` y `COM_CUENTA_PAGAR` del Avance 2 | `TRG_VEN_ABONO_SALDO_AI` y `TRG_COM_ABONO_SALDO_AI`; restricciones `CHECK` impiden un saldo negativo o mayor al original |
| 4 | Totales de `VEN_CIERRE_DIARIO` y `VEN_CIERRE_DIARIO_DET` (facturas, unidades, montos, devoluciones) | Agregando `VEN_FACTURA`, `VEN_FACTURA_DET` y las devoluciones del día | Es una **foto histórica** del cierre: si después se anula o corrige una factura, el cierre ya entregado no debe cambiar | `PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO` (job de las 23:00) |
| 5 | `CAT_PADRON.ID_DISTRITO` | `COD_ELECTORAL_PADR` → `CAT_DISTRITO_ELECTORAL` (provincia, cantón, distrito) → `CAT_DISTRITO` | Une cada elector con el catálogo geográfico del proyecto una sola vez al cargar, en vez de cruzar por nombres en cada consulta sobre 3,7 millones de filas | `PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO` (carga mensual) |
| 6 | Nombre y apellidos en `PER_PERSONA_FISICA` de un cliente creado desde el padrón | `CAT_PADRON` por medio de `PER_CLIENTE.ID_PADRON` | El padrón es un catálogo externo que se reemplaza cada mes y puede inactivar cédulas; la ficha del cliente debe seguir intacta. Además hay clientes que no están en el padrón (extranjeros, menores) | `PKG_PER_PADRON.PR_CREAR_CLIENTE_DESDE_PADRON` |
| 7 | `MV_VENTAS_MENSUALES` y `MV_INVENTARIO_CONSOLIDADO` | Las tablas de ventas y de existencias | Las pide el enunciado; guardan los agregados para que los reportes gerenciales no recorran las tablas transaccionales | `REFRESH COMPLETE ON DEMAND` dentro del cierre diario (`DBMS_MVIEW.REFRESH`) |

**Lo que no es desnormalización:**

- `TOTAL_FAVE`, `TOTAL_FACO`, `TOTAL_NETO_CIDI` y `TOTAL_NETO_CIDE` son **columnas virtuales**:
  Oracle las calcula al leerlas y no ocupan espacio, así que no pueden contradecirse.
- El precio y el impuesto guardados en cada línea de factura son **copia histórica** (lo que se
  cobró ese día), igual que en el Entregable 1.
- `PRO_PRECIO_HIST` es un historial (un registro por cambio de precio), no una copia del precio vigente.

**Cómo comprobar que los saldos repetidos están correctos** (debe devolver 0 filas; verificado en la base instalada):

```sql
SELECT c.ID_CLIENTE, c.SALDO_ACTUAL_CLI, NVL(SUM(x.SALDO_CUCO), 0) AS SALDO_CALCULADO
  FROM CADENA_NEG.PER_CLIENTE c
  LEFT JOIN CADENA_NEG.VEN_CUENTA_COBRAR x ON x.ID_CLIENTE = c.ID_CLIENTE AND x.ESTADO_CUCO IN ('P', 'A')  -- pendiente o con abonos
 GROUP BY c.ID_CLIENTE, c.SALDO_ACTUAL_CLI
HAVING c.SALDO_ACTUAL_CLI <> NVL(SUM(x.SALDO_CUCO), 0);
```
