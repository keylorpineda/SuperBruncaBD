# Resumen del proyecto para la defensa

Este documento explica **cómo se implementó cada requerimiento del enunciado del Entregable #2**,
dónde está en el código, cómo se demuestra en vivo y **qué preguntas puede hacer el profesor**
con una respuesta corta para cada una.

- Para el guion de la demostración paso a paso: [GUIA_DEFENSA.md](GUIA_DEFENSA.md).
- Para instalar y montar las dos PC: [GUIA_PASO_A_PASO.md](GUIA_PASO_A_PASO.md) y
  [GUIA_COMPANERO_PC_STANDBY.md](GUIA_COMPANERO_PC_STANDBY.md).
- Todo lo de aquí se probó en **Oracle 21c Enterprise Edition** (Docker, dos contenedores).

---

## 1. El proyecto en un minuto

**Qué es:** la base de datos de una cadena de supermercados ("Super Brunca") en Oracle 21c EE.
No hay aplicación: todo vive en la base (tablas, paquetes PL/SQL, triggers, jobs).

**Arquitectura:**

```
 PC 1 - PRINCIPAL (CADENA)                         PC 2 - STANDBY (CADENA_STBY)
 Esquema CADENA_NEG en el PDB PDBCADENA            Copia fisica exacta, solo lectura
 Paquetes + triggers + 11 jobs   ==== Data Guard ===>  aplica el redo en tiempo real
 RMAN diario, purga, monitoreo   ---- respaldo ---->   recibe el respaldo diario
                                 (puerto 1521)
```

**Cifras (verificadas en 21c EE):** 65 tablas en el diccionario (61 del modelo + 2 tablas
externas del padrón + 2 contenedores de vistas materializadas), 225 índices, 10 paquetes,
20 triggers del Avance 2, 11 jobs, 7 vistas, 2 vistas materializadas, **0 objetos inválidos**,
12 pruebas automáticas con 100 % de éxito.

**Módulos (prefijo de tabla):** `CAT` catálogos y padrón · `PER` personas, clientes y proveedores ·
`SEG` seguridad y parámetros · `PRO` productos y precios · `INV` inventario · `COM` compras ·
`VEN` ventas · `PRM` promociones y descuentos · `AUD` auditoría.

**Paquetes:**

| Paquete | Para qué |
| :--- | :--- |
| `PKG_AUD_CONTROL` | Bitácoras y registro de errores (transacción autónoma) |
| `PKG_SEG_SEGURIDAD` | Cifrado AES-256, parámetros, claves de roles |
| `PKG_ADM_NOTIFICACION` | Envío de correo por `UTL_SMTP` y las notificaciones |
| `PKG_VEN_OPERACION` | Facturas de venta, abonos, cierre diario |
| `PKG_COM_OPERACION` | Facturas de compra y abonos a proveedores |
| `PKG_INV_GESTION` | Movimientos de inventario y reporte semanal de mercadeo |
| `PKG_PRM_MERCADEO` | Promociones (acciones), descuentos semanales, premiación |
| `PKG_PER_PADRON` | Carga del padrón del TSE y alta de clientes desde el padrón |
| `PKG_ADM_MONITOREO` | Tablespaces, objetos inválidos, índices, sesiones, crecimiento |
| `PKG_ADM_STANDBY` | Jobs del standby/RMAN, credencial del SO, monitoreo de Data Guard |

**Orden de instalación:** `sql/script_bd_v2.sql` (base del Entregable 1) → `sql/00_Master_Instalacion_Avance2.sql`
(ejecuta 01 a 06 y `07_Standby_y_RMAN/07_...sql`). Al final imprime la validación y "FINALIZADO CON EXITO".

---

## 2. Funcionalidades del negocio

### 2.1 Factura de venta pendiente → aumenta el saldo del cliente y crea la cuenta por cobrar
- **Cómo:** trigger `TRG_VEN_FACTURA_CRED_AI` (AFTER INSERT en `VEN_FACTURA`). Si la factura es a
  crédito y queda pendiente (`ESTADO_FAVE = 'P'`), inserta la fila en `VEN_CUENTA_COBRAR` y suma el
  total a `PER_CLIENTE.SALDO_ACTUAL_CLI`.
- **Dónde:** `sql/04_Triggers_Negocio_y_Auditoria.sql`; tabla nueva `VEN_CUENTA_COBRAR` (`01_Estructuras`).
- **Demostrar:** `PKG_VEN_OPERACION.PR_FACTURAR_VENTA_ATOMICA` (prueba 5 del instalador) y luego
  `SELECT * FROM VEN_CUENTA_COBRAR ORDER BY 1 DESC;` y el saldo del cliente.
- **Preguntas:**
  - *¿Por qué un trigger y no hacerlo en el procedimiento?* Porque así se cumple aunque la factura se
    inserte desde cualquier lado (otra aplicación, SQL directo); la regla vive en la base.
  - *¿Qué pasa si el insert de la factura falla después?* El trigger es parte de la misma
    transacción: si se hace `ROLLBACK`, también se deshacen la cuenta por cobrar y el saldo.

### 2.2 Factura de proveedor pendiente → aumenta lo que se le debe (cuentas por pagar)
- **Cómo:** igual que 2.1 con `TRG_COM_FACTURA_CRED_AI` sobre `COM_FACTURA_COMPRA`, tabla
  `COM_CUENTA_PAGAR` y `PER_PROVEEDOR.SALDO_ACTUAL_PROVE`.
- **Demostrar:** prueba 4 del instalador / `PKG_COM_OPERACION.PR_FACTURAR_COMPRA_ATOMICA`.

### 2.3 Factura cancelada totalmente → estado pasa de pendiente a cancelada
- **Cómo:** triggers `TRG_VEN_ABONO_SALDO_AI` (en `VEN_ABONO_COBRAR`) y `TRG_COM_ABONO_SALDO_AI`
  (en `COM_ABONO_PAGAR`). Cada abono descuenta el saldo de la cuenta y del cliente/proveedor;
  cuando el saldo llega a 0, cambia la cuenta a `C` y la factura a `ESTADO_FAVE = 'C'`.
- **Demostrar:** prueba 6 (`PR_REGISTRAR_ABONO_COBRAR` con el total): el estado pasa de `P` a `C`.
- **Pregunta:** *¿Y si abonan más de lo que deben?* El procedimiento lo rechaza (`ORA-20041`
  en compras) antes de insertar.

### 2.4 Padrón nacional cargado y enlazado a clientes
- **Cómo:**
  - Tablas `CAT_PADRON` (persona) y `CAT_DISTRITO_ELECTORAL`; `PER_CLIENTE.ID_PADRON` enlaza al cliente.
  - El archivo oficial del TSE (`padron_completo.zip`, 3.762.240 personas) se lee con **tablas
    externas** (`EXT_PADRON_TSE`, `EXT_DISTELEC_TSE`, juego de caracteres Latin-1).
  - `PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO` hace un `MERGE` por provincia con `COMMIT` por lote.
  - `PR_CREAR_CLIENTE_DESDE_PADRON` crea el cliente a partir de la cédula.
  - Carga automática mensual: `JOB_PADRON_MENSUAL` (descarga con `Descargar_Padron_TSE.sh` + carga).
- **Resultado verificado:** 3.762.240 personas, 0 rechazos, ~52 min con Data Guard activo.
- **Preguntas:**
  - *¿Por qué tablas externas y no `UTL_FILE` línea por línea?* Por rendimiento: Oracle lee el
    archivo como una tabla y el `MERGE` procesa millones de filas en bloque. (Para archivos chicos
    también existe `PR_CARGAR_PADRON_TSE`, que usa `UTL_FILE`.)
  - *¿Dónde está el archivo?* En la carpeta del directorio Oracle `DIR_PADRON`, no en el repositorio (pesa 450 MB).
  - *¿Por qué el sexo sale "N"?* El TSE no lo publica: el campo 3 del archivo es `RELLENO` (lo dice su `LEAME.txt`).
  - *¿Qué pasa con las personas que ya no salen en el padrón?* Se marcan `ESTADO_PADR = 'I'`
    (solo si el archivo trae al menos el 90 % de los activos, para no borrar todo con un archivo de prueba).

### 2.5 Toda factura (compra y venta) modifica el inventario
- **Cómo:** `TRG_VEN_FACTURA_DET_INV_AI` (resta) y `TRG_COM_FACTURA_DET_INV_AI` (suma), en el
  detalle de las facturas. Llaman a `PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA`, que bloquea la fila de
  `INV_EXISTENCIA` (`FOR UPDATE WAIT 5`), actualiza la cantidad y registra el movimiento (kárdex).
- **Pregunta:** *¿Y si no hay existencia?* Se rechaza con `ORA-20015` y no se guarda la venta (prueba 11).

### 2.6 Devoluciones modifican el inventario
- **Cómo:** `TRG_VEN_DEVOLUCION_DET_INV_AI` (devolución de cliente: entra producto) y
  `TRG_COM_DEVOLUCION_DET_INV_AI` (devolución a proveedor: sale producto), con el mismo `PR_AFECTAR_EXISTENCIA`.

### 2.7 Cambio de precio de costo → historial de precios
- **Cómo:** `TRG_PRO_HISTORIAL_PRECIO_AU` (AFTER UPDATE OF `PRECIO_COSTO_PROD` en `PRO_PRODUCTO`):
  si el precio nuevo es distinto, inserta en `PRO_PRECIO_HIST` el anterior, el nuevo y la fecha.
- **Demostrar:** `UPDATE PRO_PRODUCTO SET PRECIO_COSTO_PROD = PRECIO_COSTO_PROD + 10 WHERE ID_PRODUCTO = 1;`
  y `SELECT * FROM PRO_PRECIO_HIST ORDER BY 1 DESC;`

### 2.8 Límites al facturar a crédito (clientes y proveedores)
- **Cómo:** `TRG_VEN_FACTURA_CRED_BIU` y `TRG_COM_FACTURA_CRED_BIU` (BEFORE INSERT OR UPDATE).
  Si saldo actual + factura supera `MONTO_MAX_CREDITO_CLI` (o `LIMITE_CREDITO_PROVE`), lanzan
  `ORA-20010` (cliente) / `ORA-20015` (proveedor) y la factura **no se guarda** con estado pendiente.
- **Demostrar:** prueba 10: venta de 50 millones a crédito → rechazo, y se verifica que no quedó
  ni la factura ni la cuenta por cobrar (atomicidad con `ROLLBACK TO SAVEPOINT`).

### 2.9 Proceso semanal: productos por vencer (1 semana) y con más de 6 meses en bodega
- **Cómo:** `PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO`, ejecutado por `JOB_MERCADEO_SEMANAL`
  (lunes 05:00). Arma **dos secciones separadas** y las envía al coordinador.
  Los rangos son parámetros: `DIAS_ALERTA_POR_VENCER` (7) y `MESES_ANTIGUEDAD_BODEGA` (6).

### 2.10 Tipos de promociones: acciones según productos patrocinadores
- **Cómo:** `PRM_PROMOCION` + `PRM_PATROCINADOR` (producto, `CANT_REQUERIDA_PATR`, `ACCIONES_OTORGA_PATR`).
  `PKG_PRM_MERCADEO.FN_CALCULAR_ACCIONES_FACTURA` calcula
  `TRUNC(cantidad comprada / cantidad requerida) × acciones` para cada línea vigente, y
  `PR_OTORGAR_ACCIONES_LINEA` las registra en `PRM_ACCION_CLIENTE` al facturar.
- **Demostrar:** en la prueba 5 aparece `[PROMOCION AUTOMATICA] Se otorgaron 2 accion(es)...`.
- **Pregunta:** *¿Dónde se define cuántos productos por acción?* En la tabla de patrocinadores
  (`CANT_REQUERIDA_PATR`), como pide el enunciado.

### 2.11 Revisión semanal de descuentos planeados (por vencer o antigüedad)
- **Cómo:** `PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL` (en el mismo job semanal). Revisa
  las reglas de cada descuento (`TIPO_REGLA_DSRE` = `FECHA_VENCIMIENTO` o `FECHA_INGRESO`) e
  inserta automáticamente los lotes que cumplen en `PRM_DESCUENTO_DET` (`MERGE`, sin duplicar).

### 2.12 Premiar a los 10 mejores clientes cada 6 meses (parametrizado)
- **Cómo:** `PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES`, job `JOB_PREMIACION_SEMESTRAL`.
  Cantidad (`TOP_CLIENTES_PREMIADOS` = 10), monto (`MONTO_ORDEN_PREMIACION` = 100.000) y frecuencia
  (`MESES_FRECUENCIA_PREMIACION` = 6) son parámetros. Genera `PRM_ORDEN_PREMIACION` y notifica al coordinador.
  Excluye al cliente genérico de contado (`ES_DEFECTO_CLI = 'S'`).
- **Pregunta:** *Si cambio la frecuencia, ¿hay que tocar el job?* No: el trigger
  `TRG_SEG_PARAM_PREMIACION_AU` detecta el cambio del parámetro y reprograma el job solo
  (prueba 7: lo pasa a 3 meses y lo verifica).

### 2.13 Bitácoras de facturación, precios, inventario, clientes, proveedores, promociones y descuentos
- **Cómo:** triggers `TRG_AUD_VEN_FACTURA`, `TRG_AUD_COM_FACTURA`, `TRG_AUD_PRO_PRODUCTO` (precios),
  `TRG_AUD_INV_MOVIMIENTO`, `TRG_AUD_PER_CLIENTE`, `TRG_AUD_PER_PROVEEDOR`, `TRG_AUD_PRM_PROMOCION`,
  `TRG_AUD_PRM_DESCUENTO` y `TRG_AUD_PRM_DESCUENTO_DET` (INSERT/UPDATE/DELETE). Guardan en
  `AUD_BITACORA` (quién, qué, cuándo) y en `AUD_REGISTRO_CAMBIO` (valor anterior y nuevo por columna).
- **Pregunta:** *¿Si la operación falla, se pierde el registro de error?* No: `PKG_AUD_CONTROL`
  usa `PRAGMA AUTONOMOUS_TRANSACTION`, así el error queda guardado aunque la operación haga rollback.

### 2.14 Notificaciones parametrizadas, clave cifrada y envío directo desde Oracle (sin VPN)
- **Cómo:** `PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO` usa **`UTL_SMTP`** desde la base hacia
  `smtp.gmail.com:465` (SSL). Servidor, puerto, emisor, destinatarios y clave están en `SEG_PARAMETRO`;
  la clave va **cifrada con AES-256** (`DBMS_CRYPTO`). Se necesita:
  - ACL de red (`DBMS_NETWORK_ACL_ADMIN`) para el usuario.
  - Wallet con los certificados de Gmail (`sql/08_Wallet_SMTP_Gmail.sh`).
  - Correo en HTML adaptable al celular (MIME `multipart/alternative`, texto + HTML).
- **Preguntas:**
  - *¿Por qué hace falta el wallet?* Porque la conexión es SSL y Oracle 21c necesita confiar en el
    certificado del servidor; sin él da `ORA-29024`.
  - *¿Qué pasa si no hay internet?* El error se guarda en `AUD_ERROR_SISTEMA` y la operación de
    negocio continúa (la factura no se pierde porque falle un correo).
  - *¿Se puede mandar a cualquier correo?* Sí, cambiando `CORREO_COORDINADOR`, `CORREO_GERENTE`
    o `CORREO_DBA` (varios separados por coma).

---

## 3. Seguridad

### 3.1 Perfiles, roles (Gerente, Jefe Departamento, Jefe Proveeduría, Digitador) y usuarios
- **Cómo (`sql/05_Seguridad_Perfiles_Roles_Usuarios.sql`):**
  - Roles `ROL_GERENTE`, `ROL_JEFE_DEPARTAMENTO`, `ROL_JEFE_PROVEEDURIA` y `ROL_DIGITADOR`, con
    **privilegios mínimos** (solo las tablas y paquetes que necesita cada uno; sin DBA, CONNECT ni RESOURCE).
  - Usuarios `USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV` y `USR_DIGITADOR` con
    `DEFAULT ROLE NONE` (el rol no se activa solo).
  - Perfiles con política de contraseñas:

  | | `PERFIL_CADENA_ADMIN` | `PERFIL_CADENA_OPER` |
  | :--- | :---: | :---: |
  | Intentos fallidos antes de bloquear | 3 | 3 |
  | Bloqueo | 1 día | 1 día |
  | Vida de la contraseña | 60 días | 45 días |
  | Gracia | 7 días | 5 días |
  | Reutilización (tiempo / veces) | 365 días / 5 | 180 días / 3 |
  | Inactividad / sesiones | 30 min / 3 | 15 min / 2 |

- **Demostrar:** conectarse como `USR_DIGITADOR`: antes de activar el rol no ve tablas;
  `EXEC CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');` → consulta; `DELETE` → rechazado.

### 3.2 Roles con clave cifrada en una tabla de parámetros, y procedimientos que la asignan
- **Cómo:** los roles son `IDENTIFIED BY`. La clave está cifrada en `SEG_PARAMETRO`
  (`CLAVE_ROL_*`). `PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL` la descifra y hace `ALTER ROLE ... IDENTIFIED BY`;
  `PRC_ACTIVAR_ROL_SESION` la descifra y activa el rol con `DBMS_SESSION.SET_ROLE`.
  El script nunca escribe la clave en texto plano.
- **Preguntas:**
  - *¿Diferencia entre privilegios de sistema y de objeto?* Sistema = acciones sobre la base
    (`CREATE SESSION`, `CREATE TABLE`); objeto = acciones sobre un objeto concreto
    (`SELECT ON CADENA_NEG.VEN_FACTURA`, `EXECUTE ON PKG_...`). Ver la matriz del script 05 y
    `DBA_SYS_PRIVS` / `DBA_TAB_PRIVS`.
  - *¿Por qué `DEFAULT ROLE NONE`?* Para que el usuario tenga que activar el rol con la clave;
    si fuera rol por defecto la clave no serviría de nada.
  - *¿Dónde está la llave de cifrado?* En el paquete (limitación académica, declarada en el
    Manual Técnico). En producción iría en un Oracle Wallet o un gestor de secretos.

---

## 4. Notificaciones

| Requerimiento | Procedimiento | Destinatario | Job |
| :--- | :--- | :--- | :--- |
| Clientes con ≥ 85 % de su crédito (CxC) | `PR_NOTIF_CLIENTES_85_CREDITO` | Cada cliente (correo en `PER_CONTACTO`) | `JOB_NOTIF_CREDITOS_DIARIO` 07:00 |
| Coordinador: todos los clientes ≥ 85 % | mismo procedimiento (consolidado) | `CORREO_COORDINADOR` | ídem |
| Gerente: proveedores cerca del 70 %, **un solo correo** con todos | `PR_NOTIF_PROVEEDORES_70_CREDITO` | `CORREO_GERENTE` | ídem |
| Clientes con saldo y último pago de hace más de 1 mes | `PR_NOTIF_CLIENTES_MOROSOS` | Gerente y coordinador | ídem |
| Productos vencidos con total | `PR_NOTIF_PRODUCTOS_VENCIDOS` | Coordinador | ídem |
| Cierre diario automático (fecha, vendido, devoluciones, total; detalle por cajero) | `PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO` → `VEN_CIERRE_DIARIO` y `VEN_CIERRE_DIARIO_DET` | Coordinador y gerente | `JOB_CIERRE_DIARIO_AUTO` 23:00 |
| Tablespaces > 85 % | `PKG_ADM_MONITOREO.PR_VERIFICAR_TABLESPACES` | DBA | `JOB_MONITOREO_SALUD_DIARIO` 06:00 |
| Objetos inválidos | `PR_VERIFICAR_OBJETOS_INVALIDOS` | DBA | ídem |
| Índices dañados (estado distinto de `VALID`) | `PR_VERIFICAR_INDICES_DANADOS` | DBA | ídem |

- Los porcentajes son parámetros: `PORC_ALERTA_CREDITO_CLI` (85), `PORC_ALERTA_CREDITO_PROV` (70),
  `MESES_MOROSIDAD_CLIENTE` (1), `PORC_MAX_TABLESPACE` (85).
- **Preguntas:**
  - *¿Qué cambió en la base para el cierre diario?* Se agregaron las tablas `VEN_CIERRE_DIARIO`
    (encabezado) y `VEN_CIERRE_DIARIO_DET` (detalle por cajero), como pide el enunciado.
  - *¿Cómo detecta un índice dañado?* Busca en `DBA_INDEXES` los índices del esquema con estado
    distinto de `VALID` (por ejemplo `UNUSABLE`), lo registra en `AUD_MONITOREO_BD` y avisa al DBA.

---

## 5. Standby (35 % de la nota)

### 5.1 Dos servidores distintos (principal y standby)
- PC 1 con la base `CADENA` (`PRIMARY`) y PC 2 con `CADENA_STBY` (`PHYSICAL STANDBY`), Oracle
  21c EE en Docker (o VM). Se comunican por el puerto 1521 (`tnsnames.ora`: `PRIMARIA_TNS` y
  `STANDBY_TNS`; en la standby, registro estático en `listener.ora`).

### 5.2 Archivo de actualización cada 5 minutos o 50 MB (parametrizado)
- **Cómo (`sql/07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql`):** redo logs de
  **50 MB** (3 grupos con 2 miembros) y **`ARCHIVE_LAG_TARGET = 300`** (5 min). Oracle cambia de
  log cuando se llena (50 MB) o cuando pasan 5 minutos, sin intervención. Valores en
  `STANDBY_SWITCH_MB` y `STANDBY_SWITCH_MIN`.
- **Pregunta:** *¿Qué es un archivelog?* La copia del redo log cuando Oracle cambia de grupo: el
  historial de todos los cambios. Con él se reconstruye o se actualiza otra base.

### 5.3 Trasladar la información cada 10 minutos (parametrizado) y a petición
- **Cómo:**
  - **Data Guard** envía el redo continuamente (`LOG_ARCHIVE_DEST_2 = SERVICE=STANDBY_TNS ASYNC`),
    y la standby lo aplica en tiempo real (`RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE`).
  - Además, `JOB_STANDBY_TRASLADO_ARCHIVELOG` corre cada `STANDBY_SYNC_MIN` (10) minutos: fuerza el
    cambio de log y envía los respaldos nuevos.
  - A petición: `PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA` o la opción 3 de `menu.ps1`.
- **Preguntas:**
  - *¿ASYNC o SYNC?* ASYNC (modo máximo rendimiento): la principal no espera a la standby. SYNC
    daría cero pérdida pero haría lenta cada transacción.
  - *¿Cómo sé que está sincronizada?* `V$DATAGUARD_STATS` (transport/apply lag = 0) y
    `V$ARCHIVE_DEST_STATUS` (`VALID`, `NO GAP`); `PR_ESTADO_STANDBY` lo resume.

### 5.4 Oracle 21c y Linux o Windows
- Oracle 21c Enterprise Edition (imagen `database/enterprise:21.3.0.0`) sobre Oracle Linux en Docker.
  Los scripts de sistema existen en `.sh` (Linux) y `.ps1` (Windows).

### 5.5 Eliminar archivos ya trasladados/aplicados con rango de 3 días (parametrizado)
- **Cómo:** `JOB_STANDBY_PURGA_ARCHIVELOG` (03:00) ejecuta `03_Purga_Archivelogs_3Dias.rman` con
  `STANDBY_PURGE_DIAS` (3) y la política `ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY BACKED UP 1 TIMES`:
  RMAN solo borra lo que **ya se aplicó en la standby y ya se respaldó** (si no, avisa
  `RMAN-08120`/`RMAN-08138` y lo conserva). En la standby: `03_Purga_Archivelogs_Standby.rman`.

### 5.6 Respaldo diario automático trasladado a la standby, y a petición
- **Cómo:** `JOB_RMAN_BACKUP_DIARIO` (01:00) ejecuta `04_RMAN_Backup_Full_Incremental.rman`
  (nivel 0 los domingos, nivel 1 el resto; incluye controlfile de standby). Cada pieza nueva se copia
  a la standby **por la red de Oracle** con `DBMS_FILE_TRANSFER.PUT_FILE` y el database link
  `LNK_STANDBY` (`10_Enlace_Respaldos_DataGuard.sql`). A petición: `PR_RESPALDAR_AHORA` / opción 4 del menú.
- **Preguntas:**
  - *¿Por qué el job es de tipo EXECUTABLE?* Porque RMAN es un programa del sistema operativo;
    `DBMS_SCHEDULER` lo ejecuta con una credencial (`DBMS_CREDENTIAL`, `PR_REGISTRAR_CREDENCIAL_OS`).
  - *¿Por qué `BACKUP OPTIMIZATION OFF`?* Con `ON`, RMAN omite archivos que ya respaldó antes
    (`PDB$SEED`) y el respaldo nuevo no alcanza para recrear la standby (`RMAN-06023`).

### 5.7 Failover, switchover, recuperación y sincronización (demostración)
| Operación | Cómo (verificado) | Menú |
| :--- | :--- | :--- |
| Sincronización | Dato en la principal → visible en la standby `READ ONLY WITH APPLY` | 3 y 5 |
| Switchover (planificado, sin pérdida) | `ALTER DATABASE SWITCHOVER TO CADENA_STBY [VERIFY];` → abrir la nueva principal → montar la antigua y reanudar el apply | 6 → 7 → 2 |
| Failover (desastre) | `RECOVER MANAGED ... CANCEL; ALTER DATABASE FAILOVER TO CADENA_STBY; ALTER DATABASE OPEN;` | 8 |
| Recuperación | Recrear la antigua principal como standby con un respaldo de la nueva (`08_Creacion_Standby_Segunda_PC.rman`) | — |

- **Preguntas:**
  - *¿Diferencia entre switchover y failover?* Switchover: cambio planificado, las dos bases
    funcionan y no se pierde nada; se puede devolver. Failover: la principal murió; la standby se
    activa sola; la antigua principal hay que reconstruirla.
  - *¿Cuántos datos se pierden en un failover?* Con aplicación en tiempo real, prácticamente nada
    (en la prueba no se perdió la última venta). En el peor caso, lo no enviado (segundos).
  - *¿Por qué después de un failover cambian los números de secuencia?* La base se abre con
    `RESETLOGS` y empieza una nueva encarnación; por eso el monitoreo usa `V$ARCHIVE_DEST_STATUS`.

### 5.8 Replicar todas las acciones y qué hacer ante inconvenientes
- `FORCE LOGGING` (ninguna operación se salta el redo) y `STANDBY_FILE_MANAGEMENT = AUTO`
  (los datafiles nuevos se crean solos en la standby). Se probó reinstalar todo el esquema con
  Data Guard activo: se replicó con lag 0.
- Guía de incidentes: Manual de Administración del Standby, sección 10 (NOLOGGING, datafile nuevo,
  archivos externos, huecos de archivelogs, disco lleno, destino en `ERROR`, etc.).

---

## 6. Requerimientos de base de datos (1 a 15)

| # | Requerimiento | Cómo se cumple |
| :---: | :--- | :--- |
| 1 | Arquitectura en paquetes | 10 paquetes por módulo con procedimientos y funciones (tabla de la sección 1) |
| 2 | Transacciones: commit, rollback, savepoint | `SAVEPOINT` al inicio de cada operación crítica y `ROLLBACK TO` en la excepción (17 en el script 03); prueba 10 de atomicidad |
| 3 | Excepciones | Todo procedimiento tiene `EXCEPTION`; registra con `PKG_AUD_CONTROL.PR_REGISTRAR_ERROR` en `AUD_ERROR_SISTEMA` y usa códigos propios `RAISE_APPLICATION_ERROR(-20xxx)` |
| 4 | Auditoría con triggers | 9 triggers `TRG_AUD_*` + `AUD_BITACORA` / `AUD_REGISTRO_CAMBIO` / `AUD_ERROR_SISTEMA` / `AUD_MONITOREO_BD` |
| 5 | Scheduler | 11 jobs `DBMS_SCHEDULER` (sección 7) |
| 6a | Password profile | 2 perfiles (sección 3.1) |
| 6b | Roles mínimos, sin DBA/CONNECT/RESOURCE | 4 roles con privilegios por tabla y paquete |
| 6c | Privilegios de sistema vs objeto | Matriz separada en el script 05 |
| 7 | `DBMS_CRYPTO` | AES-256 CBC PKCS5 para la clave del correo y las de los roles |
| 8 | `EXPLAIN PLAN` | 3 consultas del negocio (cuentas por cobrar, existencias, facturas por fecha) en el script 06, comparando el plan natural, `FULL` e `INDEX` con `DBMS_XPLAN.DISPLAY` |
| 9 | 2 vistas materializadas | `MV_VENTAS_MENSUALES` y `MV_INVENTARIO_CONSOLIDADO` (`BUILD IMMEDIATE`, `REFRESH COMPLETE ON DEMAND`; prueba 9 las refresca) |
| 10 | Parametrización en tablas | `SEG_PARAMETRO` (módulos CORREO, SEGURIDAD, NEGOCIO, MONITOREO, STANDBY) |
| 11 | Concurrencia `FOR UPDATE`, `NOWAIT`, `WAIT` | `FOR UPDATE WAIT 5` en existencias, clientes y proveedores; `FOR UPDATE NOWAIT` en los abonos (evita el doble pago simultáneo) |
| 12 | Integridad con packages/triggers | Límites de crédito, estados, inventario, saldos (triggers) + `CHECK` y llaves foráneas |
| 13 | Paquete de monitoreo | `PKG_ADM_MONITOREO`: tablespaces, objetos inválidos, índices, sesiones, crecimiento, errores |
| 14 | Demostración del standby | Sección 5.7 |
| 15 | RMAN: full, incremental, restore, recovery | `04_...rman` (nivel 0/1) y `05_RMAN_Restore_Recovery_PointInTime.rman` (completo, punto en el tiempo, un PDB) |

**Preguntas típicas sobre esto:**
- *¿`WAIT 5` o `NOWAIT`?* `WAIT 5` espera hasta 5 segundos a que otra sesión libere la fila (por
  ejemplo, dos cajeros vendiendo el mismo producto). `NOWAIT` falla de inmediato (`ORA-00054`):
  se usa en los abonos para no procesar dos pagos de la misma cuenta a la vez.
- *¿Qué muestra el EXPLAIN PLAN?* El camino que elige el optimizador (`FULL TABLE SCAN` o
  `INDEX RANGE SCAN`) y su costo. Con pocos datos el optimizador prefiere `FULL`; con millones de
  filas el índice compuesto `IX_CUCO_ESTADO_VENCIM` baja el costo.
- *¿Por qué `REFRESH ON DEMAND` y no `ON COMMIT`?* Son reportes (ventas por mes, inventario
  consolidado): se refrescan cuando se necesitan sin hacer lenta cada factura.

---

## 7. Los 11 jobs

| Job | Cuándo | Qué hace |
| :--- | :--- | :--- |
| `JOB_CIERRE_DIARIO_AUTO` | Diario 23:00 | Cierre de ventas por cajero + correo |
| `JOB_MONITOREO_SALUD_DIARIO` | Diario 06:00 | Tablespaces, objetos inválidos, índices, sesiones |
| `JOB_NOTIF_CREDITOS_DIARIO` | Diario 07:00 | 85 %, 70 %, morosos, vencidos |
| `JOB_MERCADEO_SEMANAL` | Lunes 05:00 | Reporte por vencer / antigüedad + descuentos |
| `JOB_PREMIACION_SEMESTRAL` | Cada 6 meses (parámetro) | Top 10 clientes |
| `JOB_PADRON_MENSUAL` | Día 5, 02:00 | Descarga y carga del padrón |
| `JOB_PADRON_DESCARGA` | (lo llama el anterior) | Descarga del ZIP del TSE |
| `JOB_STANDBY_TRASLADO_ARCHIVELOG` | Cada 10 min | Cambio de log y envío de respaldos |
| `JOB_RMAN_BACKUP_DIARIO` | Diario 01:00 | RMAN nivel 0/1 + envío a la standby |
| `JOB_STANDBY_PURGA_ARCHIVELOG` | Diario 03:00 | Purga de 3 días |
| `JOB_STANDBY_MONITOREO` | Cada hora | Revisa atraso y fallos; avisa al DBA |

---

## 8. Preguntas generales que pueden salir

| Pregunta | Respuesta corta |
| :--- | :--- |
| ¿Qué es un PDB/CDB? | Oracle 21c es multitenant: el contenedor `CADENA` (CDB) tiene adentro bases "enchufables"; el proyecto vive en el PDB `PDBCADENA`. Los parámetros de redo, archivado y Data Guard son del CDB. |
| ¿Por qué Enterprise Edition? | Porque Data Guard (standby administrada, switchover y failover) solo viene en EE. Hay un "modo manual" para XE/Free como respaldo. |
| ¿Está la base en 5FN? | El modelo base (Entregable 1) sí, con 2 desnormalizaciones declaradas. El Avance 2 agrega **desnormalizaciones controladas** que pide el enunciado (saldos de clientes y proveedores, saldos de cuentas, totales del cierre como fotografía histórica); las mantienen los triggers para que no se desincronicen. |
| ¿Por qué `PRAGMA AUTONOMOUS_TRANSACTION` en la auditoría? | Para que el registro de error o bitácora se confirme aunque la transacción principal haga rollback. |
| ¿Qué pasa si la standby se apaga? | La principal sigue trabajando (ASYNC); al volver, Data Guard detecta el hueco y lo rellena solo (`FAL_SERVER`). El monitoreo avisa al DBA mientras tanto. |
| ¿Qué es RPO y RTO aquí? | RPO (datos que se pueden perder): segundos con Data Guard en tiempo real. RTO (tiempo para volver a operar): lo que tarda el failover, unos minutos. |
| ¿Qué diferencia hay entre respaldo nivel 0 y 1? | Nivel 0 copia todos los bloques (base del incremental); nivel 1 solo los bloques cambiados desde el último respaldo. |
| ¿Cómo se restaura a una hora antes de un error humano? | Recuperación a un punto en el tiempo: `SET UNTIL TIME`, `RESTORE`, `RECOVER` y `OPEN RESETLOGS` (escenario 2 del script 05). Después hay que recrear la standby. |
| ¿Cómo se protege que solo su compañero se conecte? | Data Guard solo acepta redo con el mismo nombre de base, `DG_CONFIG` y archivo de claves. Se recomienda además firewall restringido a la IP del compañero y lista blanca en `sqlnet.ora` (`TCP.INVITED_NODES`). |

---

## 9. Puntos débiles conocidos (mejor saberlos antes de que los pregunten)

- **La llave AES está en el código** (`PKG_SEG_SEGURIDAD`). Respuesta: limitación académica,
  declarada en el Manual Técnico; en producción iría en un Oracle Wallet.
- **Las claves de los usuarios de prueba están en el script 05** (repositorio público). Conviene
  cambiarlas antes de la defensa.
- **El código `-20015` se usa para dos errores:** existencia insuficiente (`PKG_INV_GESTION`) y
  límite de crédito de proveedor (`TRG_COM_FACTURA_CRED_BIU`). El mensaje los distingue, pero un
  profesor puede notarlo.
- **La red entre dos PC reales** (IPs, firewall, Wi-Fi de la universidad) no se probó: todo se
  verificó con dos contenedores en una PC. Plan B: hotspot de un celular.
- **Al reinstalar el esquema se borran la clave de Gmail y el parámetro del wallet:** hay que
  volver a guardarlos (Paso 9 del Manual de Instalación y `08_Wallet_SMTP_Gmail.sh`).
- **Active Data Guard** (abrir la standby en solo lectura mientras aplica) es una opción con
  licencia aparte en producción; para el curso se usa con la licencia de desarrollo.
