<div align="center">

# Sede Regional Brunca
## Campus Pérez Zeledón

### Manual Técnico de Administración y Mantenimiento

**Curso: Administración de bases de datos**  
**Profesor: Hairol Romero Sandi**  
**II Ciclo - Grupo 84**  

**Estudiantes:**  
Diego Bonilla Mora  
Pineda Alvarez Keylor Steven  

Noviembre del 2026

</div>

---

# 1. Resumen Ejecutivo y Arquitectura del Sistema

El presente manual proporciona el fundamento técnico, las especificaciones de diseño, los algoritmos de seguridad, las directrices de mantenimiento y la documentación técnica detallada del **sistema de la cadena de supermercados** para el Avance #2.

El sistema opera sobre una arquitectura modular de tres capas de almacenamiento y procesamiento:

```
+-----------------------------------------------------------------------------------------+
|                          CAPA DE ACCESO Y CONSUMIDORES                                  |
|         Puntos de Venta (POS)  •  Módulos de Almacén  •  Consultas Gerenciales          |
+-----------------------------------------------------------------------------------------+
                                             │
                       Conexión TNS / Mínimos Privilegios / Rol Cifrado
                                             ▼
+-----------------------------------------------------------------------------------------+
|                  MOTOR ORACLE DATABASE (ESQUEMA: CADENA_NEG / PDBCADENA)                |
|                                                                                         |
|  +---------------------------+  +---------------------------+  +---------------------+  |
|  |         TBS_DATOS         |  |        TBS_INDICES        |  |    TBS_AUDITORIA    |  |
|  | Tablas Transaccionales    |  | Índices B-Tree Compuestos |  | Bitácora Autónoma   |  |
|  | (Ventas, Compras, Stock)  |  | (IX_CUCO_ESTADO_VENCIM)   |  | Inmutable / Errores |  |
|  +---------------------------+  +---------------------------+  +---------------------+  |
|                                                                                         |
|  • Seguridad Criptográfica: Cifrado simétrico AES-256 (DBMS_CRYPTO) en SEG_PARAMETRO.   |
|  • Automatización: 11 Jobs DBMS_SCHEDULER (negocio, padrón TSE y Standby/RMAN).         |
|  • Notificaciones: UTL_SMTP (Gmail, SSL) a los correos de SEG_PARAMETRO.                |
|  • Vistas Materializadas: MV_VENTAS_MENSUALES y MV_INVENTARIO_CONSOLIDADO.              |
|  • 21 Disparadores: crédito, existencias, kardex y auditoría en tiempo real.            |
+-----------------------------------------------------------------------------------------+
                                             │
                     Rotación 5 min / 50 MB  │  Respaldo Diario RMAN
                                             ▼
+-----------------------------------------------------------------------------------------+
|                          CAPA DE DISPONIBILIDAD Y CONTINGENCIA                          |
|             Servidor Standby Replicado  •  Almacenamiento de Respaldos RMAN             |
+-----------------------------------------------------------------------------------------+
```

---

## 2. Almacenamiento Físico y Organización de Tablespaces

El diseño físico distribuye las cargas de lectura y escritura entre tablespaces dedicados, eliminando cuellos de botella de contención de I/O a nivel de cabezales de disco:

| TABLESPACE | ARCHIVO FÍSICO | PROPÓSITO TÉCNICO |
| :--- | :--- | :--- |
| `TBS_DATOS` | <code style="white-space:nowrap">tbs_datos01.dbf</code> | Contiene 56 tablas de negocio (catálogos, transacciones operativas, parámetros y cierres) más los 2 contenedores de las vistas materializadas (`MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO`). Con las 5 tablas de `TBS_AUDITORIA` y las 2 tablas externas del padrón TSE, el diccionario muestra 65 tablas en `CADENA_NEG`. Segmentos con `EXTENT MANAGEMENT LOCAL AUTOALLOCATE`. |
| `TBS_INDICES` | <code style="white-space:nowrap">tbs_indices01.dbf</code> | Aloja los 225 índices del esquema (claves primarias, foráneas, únicos y compuestos de afinamiento). Evita contención con las escrituras en tablas de datos. |
| `TBS_AUDITORIA` | <code style="white-space:nowrap">tbs_auditoria01.dbf</code> | Aloja exclusivamente las tablas inmutables de auditoría (`AUD_REGISTRO_CAMBIO`, `AUD_ERROR_SISTEMA`, `AUD_MONITOREO_BD`, `AUD_BITACORA` y `PRO_PRECIO_HIST`). Diseñado para alta frecuencia de escritura secuencial. |

### 2.1 Principio de Aislamiento del Esquema `CADENA_NEG`
* El usuario `CADENA_NEG` posee cuota ilimitada sobre los tres tablespaces del proyecto (`TBS_DATOS`, `TBS_INDICES`, `TBS_AUDITORIA`).
* **Sin rol DBA ni RESOURCE:** Al usuario no se le otorgan roles genéricos administrativos ni privilegios sobre tablespaces del sistema (`SYSTEM`, `SYSAUX`).
* Todos los identificadores cumplen con el estándar institucional de nomenclatura en mayúsculas (`<PREFIJO>_<CONCEPTO>`).

---

## 3. Módulo de Seguridad, Perfiles y Criptografía (`PKG_SEG_SEGURIDAD`)

### 3.1 Perfiles de Contraseña y Límites de Recursos
El sistema implementa dos perfiles basados en el estándar CIS Oracle Database Benchmark:

| DIRECTIVA DE SEGURIDAD | `PERFIL_CADENA_ADMIN` (Gerencia/Jefaturas) | `PERFIL_CADENA_OPER` (Cajeros/Digitadores) |
| :--- | :---: | :---: |
| Intentos fallidos permitidos (`FAILED_LOGIN_ATTEMPTS`) | **3** | **3** |
| Tiempo de bloqueo de cuenta (`PASSWORD_LOCK_TIME`) | **1 día** | **1 día** |
| Vigencia de la contraseña (`PASSWORD_LIFE_TIME`) | **60 días** | **45 días** |
| Periodo de gracia para cambio (`PASSWORD_GRACE_TIME`) | **7 días** | **5 días** |
| Histórico de no reutilización (`PASSWORD_REUSE_TIME`) | **365 días** | **180 días** |
| Cantidad de contraseñas retenidas (`PASSWORD_REUSE_MAX`)| **5** | **3** |
| Tiempo máximo de inactividad (`IDLE_TIME`) | **30 minutos** | **15 minutos** |
| Sesiones concurrentes por usuario (`SESSIONS_PER_USER`) | **3** | **2** |

### 3.2 Cifrado Simétrico AES-256 (`DBMS_CRYPTO`)
El paquete `PKG_SEG_SEGURIDAD` implementa el algoritmo **AES-256** en modo encadenado de bloques (CBC) con relleno PKCS#5:
* **Constante del Algoritmo:** `DBMS_CRYPTO.ENCRYPT_AES256 + DBMS_CRYPTO.CHAIN_CBC + DBMS_CRYPTO.PAD_PKCS5`.
* **Llave Criptográfica Maestra:** Cadena binaria de 256 bits (32 bytes) administrada internamente por el paquete.
* **Limitación conocida (versión académica):** la llave es una constante escrita en el código fuente (`PKG_SEG_SEGURIDAD.c_llave_aes` y el bloque de datos semilla de `01_Estructuras_Avance2.sql`), por lo que todas las instalaciones comparten la misma llave y quien lea el código puede descifrar `SEG_PARAMETRO`. Se mantiene así para que cualquier persona pueda instalar y probar el proyecto sin pasos adicionales y para no invalidar los valores ya cifrados. En producción debe sustituirse por una llave propia de cada instalación guardada fuera del código (Oracle Wallet o un administrador de secretos): se genera la llave nueva, se descifran los valores de `SEG_PARAMETRO` con la llave actual, se vuelven a cifrar con la nueva (`PR_GUARDAR_PARAMETRO`) y se recompila el paquete.
* **Almacenamiento Seguro:** Los datos confidenciales (contraseñas de aplicación SMTP y claves de roles de base de datos) se almacenan en la columna `VALOR_RAW_PARA RAW(2000)` de la tabla `SEG_PARAMETRO`, marcados con `ES_CIFRADO_PARA = 'S'`.

### 3.3 Roles Protegidos con Contraseña Cifrada
A diferencia de roles estándar que se activan por defecto al conectar, los roles del sistema están blindados:
* `ROL_GERENTE IDENTIFIED BY <Clave>`
* `ROL_JEFE_DEPARTAMENTO IDENTIFIED BY <Clave>`
* `ROL_JEFE_PROVEEDURIA IDENTIFIED BY <Clave>`
* `ROL_DIGITADOR IDENTIFIED BY <Clave>`

Los usuarios se configuran con `ALTER USER ... DEFAULT ROLE NONE;`. Para operar, el usuario debe invocar el procedimiento invoker's rights:
```sql
CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');
```
El procedimiento lee la clave cifrada de `SEG_PARAMETRO`, la descifra en memoria volátil de sesión mediante `PKG_SEG_SEGURIDAD.FN_OBTENER_CLAVE_ROL`, ejecuta `DBMS_SESSION.SET_ROLE` y registra el inicio de sesión en la bitácora de auditoría.

### 3.4 Matriz de Mínimos Privilegios de Objeto
Cada rol recibe solo lo que su puesto necesita. Ningún rol recibe `DELETE` ni privilegios de modificación estructural (`DDL`). La tabla sale de la consulta real a `DBA_TAB_PRIVS` (S = SELECT, I = INSERT, U = UPDATE; las columnas son los roles `ROL_DIGITADOR`, `ROL_JEFE_PROVEEDURIA`, `ROL_JEFE_DEPARTAMENTO` y `ROL_GERENTE`):

| OBJETO | Digitador | Jefe de proveeduría | Jefe de departamento | Gerente |
| :--- | :---: | :---: | :---: | :---: |
| Ventas (`VEN_FACTURA`, `VEN_FACTURA_DET`) | S, I | — | S, I, U | S |
| Pagos de venta (`VEN_PAGO`) | S, I | — | — | — |
| Abonos de clientes (`VEN_ABONO_COBRAR`) | S, I | — | S, I | — |
| Cuentas por cobrar (`VEN_CUENTA_COBRAR`) | S | — | S | — |
| Clientes (`PER_CLIENTE`) | S, I | — | S, I | S |
| Compras (`COM_FACTURA_COMPRA`, `_DET`) | — | S, I, U | S, I, U | S |
| Devoluciones a proveedor (`COM_DEVOLUCION`, `_DET`) | — | S, I, U | — | — |
| Abonos a proveedores (`COM_ABONO_PAGAR`) | — | S, I | S, I | — |
| Cuentas por pagar (`COM_CUENTA_PAGAR`) | — | S | S | — |
| Proveedores (`PER_PROVEEDOR`) | — | S, I | S, I, U | S |
| Productos (`PRO_PRODUCTO`) | S | S | S, I, U | S |
| Existencias (`INV_EXISTENCIA`) | S | S | S, I, U | S |
| Kardex (`INV_MOVIMIENTO`) | — | — | S, I | S |
| Promociones (`PRM_PROMOCION`, `PRM_DESCUENTO_DET`, `PRM_ACCION_CLIENTE`) | — | — | S, I, U | — |
| Historial de precios (`PRO_PRECIO_HIST`) | — | — | S | S |
| Vistas materializadas (`MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO`) | — | — | S | S |
| Auditoría (`AUD_*`) | — | — | — | S |
| Paquetes (EXECUTE) | `PKG_VEN_OPERACION` | `PKG_COM_OPERACION` | `PKG_VEN_OPERACION`, `PKG_COM_OPERACION`, `PKG_INV_GESTION`, `PKG_PRM_MERCADEO` | `PKG_ADM_MONITOREO`, `PKG_ADM_STANDBY`, `PKG_INV_GESTION`, `PKG_PRM_MERCADEO` |
| Borrado (`DELETE`) y `DDL` | **DENEGADO** | **DENEGADO** | **DENEGADO** | **DENEGADO** |

### 3.5 Privilegios de Sistema vs. Privilegios de Objeto
* **Privilegio de sistema:** permite una *acción* en la base de datos, sin importar el objeto (`CREATE SESSION`, `CREATE TABLE`, `CREATE JOB`). Se consultan en `DBA_SYS_PRIVS`.
* **Privilegio de objeto:** permite una acción sobre *un objeto concreto* de un esquema (`SELECT ON CADENA_NEG.VEN_FACTURA`, `EXECUTE ON PKG_VEN_OPERACION`). Se consultan en `DBA_TAB_PRIVS`.

| QUIÉN | PRIVILEGIOS DE SISTEMA | PRIVILEGIOS DE OBJETO |
| :--- | :--- | :--- |
| `CADENA_NEG` (dueño del esquema) | `CREATE SESSION`, `CREATE TABLE`, `CREATE VIEW`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, `CREATE TRIGGER`, `CREATE TYPE`, `CREATE SYNONYM`, `CREATE MATERIALIZED VIEW`, `CREATE JOB`, `CREATE EXTERNAL JOB`, `CREATE CREDENTIAL`, `CREATE ROLE`, `ALTER ANY ROLE`, `CREATE ANY DIRECTORY` | `EXECUTE` sobre `DBMS_CRYPTO`, `UTL_SMTP`, `UTL_TCP`, `UTL_FILE`; `SELECT` sobre las vistas de monitoreo (`V$SESSION`, `V$DATABASE`, `V$LOG`, `V$ARCHIVED_LOG`, `V$ARCHIVE_DEST_STATUS` y las `DBA_*` de espacio y objetos); `READ, WRITE` sobre el directorio `DIR_PADRON` |
| `ROL_DIGITADOR` | `CREATE SESSION` | Ver matriz 3.4 |
| `ROL_JEFE_PROVEEDURIA`, `ROL_JEFE_DEPARTAMENTO`, `ROL_GERENTE` | `CREATE SESSION`, `ALTER SESSION` | Ver matriz 3.4 |
| `USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR` | `CREATE SESSION` (para conectarse antes de activar su rol) | Ninguno directo: todo llega por el rol, que está en `DEFAULT ROLE NONE` |

No se usan los roles `DBA`, `CONNECT` ni `RESOURCE`. Para revisarlo en la defensa (desde `PDBCADENA` como SYSDBA):
```sql
SELECT grantee, privilege FROM dba_sys_privs
 WHERE grantee IN ('CADENA_NEG', 'ROL_DIGITADOR', 'ROL_JEFE_PROVEEDURIA', 'ROL_JEFE_DEPARTAMENTO', 'ROL_GERENTE') ORDER BY 1, 2;
SELECT grantee, table_name, privilege FROM dba_tab_privs
 WHERE grantee IN ('ROL_DIGITADOR', 'ROL_JEFE_PROVEEDURIA', 'ROL_JEFE_DEPARTAMENTO', 'ROL_GERENTE') ORDER BY 1, 2;
-- Debe devolver 0 filas:
SELECT grantee, granted_role FROM dba_role_privs
 WHERE granted_role IN ('DBA', 'CONNECT', 'RESOURCE') AND (grantee LIKE 'USR%' OR grantee LIKE 'ROL%' OR grantee = 'CADENA_NEG');
```

---

## 4. Módulo de Auditoría Inmutable y Control de Errores (`PKG_AUD_CONTROL`)

### 4.1 Transacciones Autónomas
Para garantizar que las pistas de auditoría no puedan ser alteradas ni revertidas por transacciones que terminen en fallo, los procedimientos `PR_REGISTRAR_OPERACION` y `PR_REGISTRAR_ERROR` declaran:

```sql
PRAGMA AUTONOMOUS_TRANSACTION;
```

Esto inicia un contexto de transacción independiente que ejecuta `INSERT` y `COMMIT` en las tablas de auditoría sin interferir con la transacción padre del usuario.

### 4.2 Estructuras de Auditoría
* `AUD_REGISTRO_CAMBIO`: Almacena el nombre de la tabla, llave primaria afectada, tipo de operación (`INSERT`, `UPDATE`, `DELETE`, `LOGIN`), campo modificado, valor anterior, valor nuevo, usuario de BD, usuario de SO, terminal y dirección IP del cliente obtenida mediante `SYS_CONTEXT('USERENV', 'IP_ADDRESS')`.
* `AUD_ERROR_SISTEMA`: Bitácora técnica de excepciones. Captura el código SQL (`SQLCODE`), mensaje (`SQLERRM`), paquete, procedimiento emisor y la traza completa de pila (`DBMS_UTILITY.FORMAT_ERROR_BACKTRACE`).
* `AUD_MONITOREO_BD`: Registro histórico de revisiones de salud de infraestructura.

---

## 5. Módulo de Reglas de Negocio y Triggers

El esquema tiene **21 disparadores**: 12 de reglas de negocio y 9 de auditoría. Las reglas que no se pueden expresar con restricciones (`CHECK`, `FOREIGN KEY`) se programan aquí o en los paquetes:

```
[Venta a Crédito] ──► TRG_VEN_FACTURA_CRED_BIU ──► Valida: Saldo Actual + Total <= Límite Máximo
                             │ (Si es aprobado)
                             ▼
                      TRG_VEN_FACTURA_CRED_AI  ──► Crea registro en VEN_CUENTA_COBRAR
                                               ──► Aumenta SALDO_ACTUAL_CLI en PER_CLIENTE

[Líneas de Venta] ──► TRG_VEN_FACTURA_DET_INV_AI ──► Verifica stock >= cantidad
                                                 ──► Descuenta CANTIDAD_EXIS en INV_EXISTENCIA
                                                 ──► Registra movimiento de salida en Kardex

[Abono a Factura] ──► TRG_VEN_ABONO_SALDO_AI   ──► Descuenta SALDO_CUCO en VEN_CUENTA_COBRAR
                                               ──► Descuenta SALDO_ACTUAL_CLI en PER_CLIENTE
                                               ──► Si saldo = 0: ESTADO_FAVE pasa de 'P' a 'C'
```

| DISPARADOR | TABLA | QUÉ HACE |
| :--- | :--- | :--- |
| `TRG_VEN_FACTURA_CRED_BIU` | `VEN_FACTURA` | Rechaza la venta a crédito si supera el límite del cliente (`ORA-20010`), si el cliente está inactivo (`ORA-20011`) o si no existe (`ORA-20013`). |
| `TRG_VEN_FACTURA_CRED_AI` | `VEN_FACTURA` | Crea la cuenta por cobrar y suma al saldo del cliente. |
| `TRG_VEN_FACTURA_DET_INV_AI` | `VEN_FACTURA_DET` | Descuenta la existencia y registra la salida en el kardex. |
| `TRG_VEN_ABONO_SALDO_AI` | `VEN_ABONO_COBRAR` | Rebaja la cuenta por cobrar y el saldo del cliente; cancela la factura al llegar a 0. |
| `TRG_VEN_DEVOLUCION_DET_INV_AI` | `VEN_DEVOLUCION_DET` | Regresa al inventario lo devuelto por el cliente. |
| `TRG_COM_FACTURA_CRED_BIU` | `COM_FACTURA_COMPRA` | Rechaza la compra a crédito si el proveedor está inactivo (`ORA-20017`), supera el límite que da el proveedor (`ORA-20018`) o no existe (`ORA-20019`). |
| `TRG_COM_FACTURA_CRED_AI` | `COM_FACTURA_COMPRA` | Crea la cuenta por pagar y suma al saldo con el proveedor. |
| `TRG_COM_FACTURA_DET_INV_AI` | `COM_FACTURA_COMPRA_DET` | Suma la existencia y registra la entrada en el kardex. |
| `TRG_COM_ABONO_SALDO_AI` | `COM_ABONO_PAGAR` | Rebaja la cuenta por pagar y el saldo con el proveedor. |
| `TRG_COM_DEVOLUCION_DET_INV_AI` | `COM_DEVOLUCION_DET` | Saca del inventario lo devuelto al proveedor. |
| `TRG_PRO_HISTORIAL_PRECIO_AU` | `PRO_PRODUCTO` | Guarda el precio anterior en `PRO_PRECIO_HIST` cada vez que cambia. |
| `TRG_SEG_PARAM_PREMIACION_AU` | `SEG_PARAMETRO` | Si cambia la frecuencia de premiación, reprograma `JOB_PREMIACION_SEMESTRAL`. |
| `TRG_AUD_*` (9) | `VEN_FACTURA`, `COM_FACTURA_COMPRA`, `PER_CLIENTE`, `PER_PROVEEDOR`, `PRO_PRODUCTO`, `INV_MOVIMIENTO`, `PRM_PROMOCION`, `PRM_DESCUENTO`, `PRM_DESCUENTO_DET` | Registran cada `INSERT`, `UPDATE` y `DELETE` en `AUD_REGISTRO_CAMBIO` con valor anterior, valor nuevo, usuario, terminal e IP. |

### 5.1 Regla de Exclusividad de Proveedores y Personas
El modelo impide inconsistencias mediante el supertipo `PER_PERSONA` y la clave alterna `UK_PERS_NATURALEZA (ID_PERSONA, ES_JURIDICA_PERS)`. Se garantiza por diseño del motor que todo proveedor pertenezca forzosamente a una persona jurídica (`ES_JURIDICA_PERS = 'S'`) y nunca a una persona física.

### 5.2 Catálogo de Códigos de Error del Sistema
Cada error propio del sistema tiene un código único de `RAISE_APPLICATION_ERROR` (rango de Oracle `-20000` a `-20999`), agrupado por módulo. Al ver el código en pantalla o en `AUD_ERROR_SISTEMA` se sabe exactamente qué regla se incumplió:

| CÓDIGO | DÓNDE | SIGNIFICADO |
| :--- | :--- | :--- |
| `-20001` | `script_bd_v2.sql` | No hay ningún PDB abierto en lectura y escritura para instalar. |
| `-20010` | `TRG_VEN_FACTURA_CRED_BIU` | Límite de crédito del cliente excedido. |
| `-20011` | `TRG_VEN_FACTURA_CRED_BIU` | Cliente inactivo para ventas a crédito. |
| `-20013` | `TRG_VEN_FACTURA_CRED_BIU` | El cliente no existe. |
| `-20014` | `PKG_INV_GESTION` | La cantidad a mover en inventario debe ser mayor a cero. |
| `-20015` | `PKG_INV_GESTION` | Existencia insuficiente (o sin inventario registrado) en la bodega. |
| `-20016` | `PKG_INV_GESTION` | El inventario está bloqueado por otro cajero (`NOWAIT`); se debe intentar de nuevo. |
| `-20017` | `TRG_COM_FACTURA_CRED_BIU` | Proveedor inactivo para compras a crédito. |
| `-20018` | `TRG_COM_FACTURA_CRED_BIU` | Límite de crédito otorgado por el proveedor excedido. |
| `-20019` | `TRG_COM_FACTURA_CRED_BIU` | El proveedor no existe. |
| `-20021` / `-20022` | `PKG_SEG_SEGURIDAD` | Error al cifrar / descifrar con `DBMS_CRYPTO`. |
| `-20023` / `-20024` | `PKG_SEG_SEGURIDAD` | Parámetro de texto / numérico inexistente o inactivo en `SEG_PARAMETRO`. |
| `-20025` | `PKG_SEG_SEGURIDAD` | Nombre de rol inválido. |
| `-20031` | `PKG_PER_PADRON` | La cédula no existe en el padrón (`CAT_PADRON`). |
| `-20035` | `PKG_PER_PADRON` | Nombre de archivo de padrón inválido. |
| `-20036` | `PKG_PER_PADRON` | No se puede leer el archivo del padrón en `DIR_PADRON`. |
| `-20037` | `PKG_PER_PADRON` | El archivo del padrón no tiene registros válidos. |
| `-20038` | `PKG_PRM_MERCADEO` | La frecuencia de premiación (meses) debe ser mayor a cero. |
| `-20041` | `PKG_COM_OPERACION` | El abono al proveedor supera el saldo de la factura. |
| `-20042` | `PKG_COM_OPERACION` | Factura de compra sin líneas de detalle. |
| `-20043` | `PKG_VEN_OPERACION` | Factura de venta sin líneas de detalle. |
| `-20044` | `PKG_VEN_OPERACION` | El abono del cliente supera el saldo de la factura. |
| `-20090` a `-20095` | `06_Scheduler_Optimizacion_y_Pruebas.sql` | Falla de una prueba automática del instalador (solo aparecen si algo no funciona). |
| `-20131` a `-20134` | `PKG_ADM_STANDBY` | Job inexistente, falta la credencial del sistema operativo, usuario o clave vacíos, o falta `STANDBY_RUTA_SCRIPTS`. |

Para ver los últimos errores registrados:
```sql
SELECT fecha_ersi, paquete_ersi, subprograma_ersi, codigo_sql_ersi, mensaje_error_ersi
  FROM CADENA_NEG.AUD_ERROR_SISTEMA ORDER BY id_error_sistema DESC FETCH FIRST 20 ROWS ONLY;
```

---

## 6. Módulo de Automatización DBMS_SCHEDULER y Notificaciones UTL_SMTP

### 6.1 Catálogo de Jobs Programados

| JOB | FRECUENCIA | ACCIÓN QUE EJECUTA |
| :--- | :--- | :--- |
| `CADENA_NEG.JOB_CIERRE_DIARIO_AUTO` | Diario a las 23:00 | Ejecuta `PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO`, consolidando ventas brutas, devoluciones y montos netos por sucursal y desglosado por cada cajero. Envía reporte al coordinador. |
| `CADENA_NEG.JOB_MONITOREO_SALUD_DIARIO` | Diario a las 06:00 | Ejecuta `PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO`, inspeccionando tablespaces con uso >85%, objetos inválidos, índices corruptos, errores de las últimas 24 h y sesiones concurrentes. Solo envía correo al DBA si encuentra un problema (los productos vencidos los avisa el job de las 07:00, para no repetir el correo). |
| `CADENA_NEG.JOB_NOTIF_CREDITOS_DIARIO` | Diario a las 07:00 | Ejecuta `PKG_ADM_NOTIFICACION`: detecta clientes con saldo >= 85% de límite, proveedores con saldo >= 70% de crédito, clientes morosos (>1 mes sin abono) y productos vencidos. |
| `CADENA_NEG.JOB_MERCADEO_SEMANAL` | Lunes a las 05:00 | Ejecuta `PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO` y activa descuentos en `PRM_DESCUENTO` sobre lotes con caducidad próxima (<7 días) o sin rotación (>6 meses). |
| `CADENA_NEG.JOB_PREMIACION_SEMESTRAL` | 30 jun y 31 dic (23:30) | Ejecuta `PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES`, premiando al Top 10 de clientes con órdenes de compra de ₡100,000 c/u emitidas en `PRM_ORDEN_PREMIACION`. |
| `CADENA_NEG.JOB_PADRON_MENSUAL` | Día `PADRON_DIA_CARGA` (5) de cada mes, 02:00 | `PKG_PER_PADRON.PR_ACTUALIZAR_PADRON_MENSUAL`: ejecuta `JOB_PADRON_DESCARGA` (descarga `padron_completo.zip` del TSE) y `PR_CARGAR_PADRON_MASIVO` (tablas externas Latin-1, `MERGE` por provincia, inactiva cédulas que ya no están). |
| `CADENA_NEG.JOB_PADRON_DESCARGA` | Sin horario propio (lo lanza `JOB_PADRON_MENSUAL`) | Job EXECUTABLE deshabilitado a propósito: ejecuta `descargar_padron_tse.sh` en el servidor (descarga y descomprime el padrón del TSE en `DIR_PADRON`). |
| `CADENA_NEG.JOB_STANDBY_TRASLADO_ARCHIVELOG` | Cada `STANDBY_SYNC_MIN` (10) min | Job EXECUTABLE: copia archivelogs y respaldos RMAN nuevos a la PC standby. |
| `CADENA_NEG.JOB_RMAN_BACKUP_DIARIO` | Diario, `STANDBY_HORA_BACKUP` (01:00) | Job EXECUTABLE: RMAN nivel 0 (domingo) o nivel 1 y copia del respaldo a la PC standby. |
| `CADENA_NEG.JOB_STANDBY_PURGA_ARCHIVELOG` | Diario, `STANDBY_HORA_PURGA` (03:00) | Job EXECUTABLE: purga archivelogs con más de `STANDBY_PURGE_DIAS` (3) días ya aplicados. |
| `CADENA_NEG.JOB_STANDBY_MONITOREO` | Cada hora | `PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION`: atraso y fallos del standby en `AUD_MONITOREO_BD`, aviso al DBA. |

**Envío a petición:** cualquier aviso de esta tabla se puede mandar en el momento con `menu.ps1`, **opción 13** (por ejemplo durante la revisión), sin esperar el horario del job.

Los jobs del standby se reconfiguran en caliente con `PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS` después de cambiar un parámetro, y se ejecutan a petición con `PR_SINCRONIZAR_AHORA`, `PR_RESPALDAR_AHORA` y `PR_PURGAR_AHORA` (ver Manual de Administración del Standby).

### 6.2 Envío Directo de Correo Electrónico (`UTL_SMTP`)
* **Sin Dependencia de VPN:** Se conecta de forma directa a servidores SMTP estándar (`smtp.gmail.com` en puerto 465 con SSL; 587 con STARTTLS como alternativa) usando el wallet de Oracle.
* **Formato del correo:** cada notificación sale como mensaje MIME `multipart/alternative` en UTF-8: una versión en texto y otra en HTML (`fn_texto_a_html`). El HTML tiene una identidad propia del supermercado: la cifra principal del aviso va en una **etiqueta de góndola** (amarilla, o roja en las alertas de la base de datos) y los datos se leen como un **tiquete de caja**, con puntos guía entre el concepto y el monto y el símbolo del colón (₡). Las tablas se ven como tablas en la computadora y como fichas en el celular (hasta 600 px), con modo oscuro en Apple Mail; en Apple Mail la etiqueta se mece una vez al abrir, y en Gmail se ve quieta. `PKG_ADM_NOTIFICACION.FN_VISTA_PREVIA_HTML` devuelve ese HTML para revisarlo sin enviar.
* **Destinatarios parametrizados:** los correos de destino están en `SEG_PARAMETRO` (`CORREO_COORDINADOR`, `CORREO_GERENTE`, `CORREO_DBA`; se aceptan varios separados por coma) y el remitente en `CORREO_EMISOR`, con su clave cifrada en `CLAVE_CORREO_EMISOR`. Se cambian sin tocar código con el menú (`menu.ps1`: opción 11 para los destinatarios, opción 12 para la clave de Gmail) o con `PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO`.
* **Tolerancia a Fallos de Red:** Si la conexión a Internet o el servidor SMTP no responde, la excepción es capturada y registrada en bitácora local (`AUD_ERROR_SISTEMA`), evitando que la facturación de los cajeros se interrumpa.

---

## 7. Caso de Estudio: Optimización y Afinamiento SQL (EXPLAIN PLAN)

### 7.1 Escenarios Críticos de Producción y Requerimientos Funcionales
El análisis de afinamiento evalúa las tres consultas más demandantes del sistema:
1. **Cobros y Morosidad (`VEN_CUENTA_COBRAR`):** Monitoreo continuo de cuentas pendientes y vencidas.
2. **Existencias de Inventario por Bodega (`INV_EXISTENCIA`):** Validación en tiempo real de disponibilidad para ventas.
3. **Facturación por Rango de Fechas (`VEN_FACTURA`):** Consolidación contable de cierres de caja y auditoría de ventas.

```sql
-- Consulta 1: Cuentas por Cobrar en Mora
SELECT c.ID_CUENTA_COBRAR,
       c.ID_FACTURA_VENTA,
       cl.CODIGO_CLI,
       c.FECHA_VENCIM_CUCO,
       c.SALDO_CUCO,
       c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE = cl.ID_CLIENTE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIM_CUCO < SYSDATE;
```

### 7.2 Comportamiento Natural del Optimizador CBO vs Escala de Producción
En bases de datos con volumen semilla (tablas de 5 a 10 filas contenidas en un único bloque de 8 KB), el Optimizador Basado en Costos (CBO) selecciona de forma natural y matemáticamente correcta la operación **`TABLE ACCESS FULL`**:
* **Lectura Multibloque:** El motor lee la totalidad del segmento en una única llamada de I/O de sistema operativo (costo estimado por el CBO $\approx 3$ I/Os).
* **Acceso por Índice B-Tree:** Requeriría leer el bloque raíz, descender por bloques rama hasta el bloque hoja, y posteriormente realizar una lectura aleatoria de bloque individual (*single block I/O*) hacia la tabla mediante `ROWID` (costo estimado $\approx 4$ I/Os).
* **Conclusión CBO para Tablas Pequeñas:** Dado que $\text{Costo}(\text{FTS}) < \text{Costo}(\text{Index})$, el optimizador evita naturalmente el índice cuando los datos caben en un bloque.

Para modelar y comprobar el comportamiento del motor a escala de producción (donde la tabla supera decenas de miles o millones de transacciones), se evalúan tanto el **Plan Natural sin Hints** como los **Planes Forzados mediante Hints** (`/*+ FULL */` vs `/*+ INDEX */`), demostrando la divergencia entre la complejidad lineal $\mathcal{O}(N)$ del escaneo completo y la complejidad logarítmica $\mathcal{O}(\log N)$ del acceso indexado.

### 7.3 Diseño e Implementación del Índice Compuesto Estratégico
Se implementa el índice compuesto `IX_CUCO_ESTADO_VENCIM` en el tablespace dedicado `TBS_INDICES`:
1. **Columna de Alta Selectividad / Filtro Directo en Primera Posición:** `ESTADO_CUCO` ('P') descarta inmediatamente la mayoría histórica de cuentas canceladas ('C').
2. **Columna de Rango Temporal en Segunda Posición:** `FECHA_VENCIM_CUCO` (< SYSDATE) permite recorrer únicamente el subconjunto de hojas del árbol B-Tree que satisfacen el rango de mora.

```sql
-- Indice creado en 01_Estructuras_Avance2.sql
CREATE INDEX IX_CUCO_ESTADO_VENCIM 
    ON VEN_CUENTA_COBRAR (ESTADO_CUCO, FECHA_VENCIM_CUCO)
    TABLESPACE TBS_INDICES;

EXEC DBMS_STATS.GATHER_TABLE_STATS('CADENA_NEG', 'VEN_CUENTA_COBRAR', CASCADE => TRUE);
```

### 7.4 Cuadro Comparativo de Rendimiento y Rutas de Acceso

| MÉTRICA TÉCNICA | RUTA NATURAL CBO (Pocas Filas) | ESCANEO COMPLETO FORZADO (FTS) | ACCESO POR ÍNDICE FORZADO (Index Scan) |
| :--- | :---: | :---: | :---: |
| **Operación Principal** | `TABLE ACCESS FULL` | `TABLE ACCESS FULL` | `INDEX RANGE SCAN` |
| **Índice Utilizado** | Ninguno (1 solo bloque) | Ninguno (Multiblock I/O) | `IX_CUCO_ESTADO_VENCIM` |
| **Justificación CBO** | Menor costo I/O en micro-tablas (3 vs 4) | Incurre en I/O proporcional a High Water Mark | Acceso directo a punteros `ROWID` |
| **Comportamiento a Escala ($N \to \infty$)** | Conmuta automáticamente a Index Scan | Degenera a costo prohibitivo $\mathcal{O}(N)$ | Mantiene latencia mínima $\mathcal{O}(\log N)$ |
| **Tipo de Predicado** | Filtro posterior sobre bloque | Filtro secuencial completo | *Access Predicate* en raíz y rama |
| **Reducción Proyectada en Producción** | N/A (Entorno de laboratorio) | Línea base no afinada | **Reducción superior al 75% en lecturas de disco** |


---

## 8. Mantenimiento Preventivo y Operativo del DBA

### 8.1 Actualización Periódica de Estadísticas del Optimizador
Para garantizar que el CBO seleccione siempre las mejores rutas de acceso:

```sql
-- Recoleccion de estadisticas de todo el esquema
EXEC DBMS_STATS.GATHER_SCHEMA_STATS( -
    ownname          => 'CADENA_NEG', -
    estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE, -
    method_opt       => 'FOR ALL COLUMNS SIZE AUTO', -
    cascade          => TRUE, -
    degree           => 2 -
);
```

### 8.2 Inspección de Salud y Detección de Objetos Inválidos
```sql
SELECT owner, object_name, object_type, status
  FROM all_objects
 WHERE owner = 'CADENA_NEG'
   AND status <> 'VALID';
```
*(Resultado esperado del sistema: 0 filas / Cero objetos inválidos).*

### 8.3 Verificación de Capacidad de Tablespaces
```sql
SELECT tablespace_name,
       ROUND(used_space * 8192 / 1024 / 1024, 2) AS usado_mb,
       ROUND(tablespace_size * 8192 / 1024 / 1024, 2) AS total_mb,
       ROUND(used_percent, 2) AS porc_uso
  FROM dba_tablespace_usage_metrics
 WHERE tablespace_name IN ('TBS_DATOS', 'TBS_INDICES', 'TBS_AUDITORIA');
```

---

## 9. Documentación Interna del Código

Todo el código fuente está comentado en español con la misma convención, para que cualquier DBA pueda mantenerlo:

| NIVEL | QUÉ DOCUMENTA | DÓNDE VERLO |
| :--- | :--- | :--- |
| Encabezado de cada archivo | Universidad, curso, entregable, módulo, motor de base de datos, requisitos previos, orden de ejecución y forma de uso | Primeras líneas de cada `.sql`, `.rman`, `.sh` y `.ps1` |
| Bloques por sección | Título numerado del paquete, tabla o paso (`-- 1. PAQUETE: PKG_PER_PADRON`) y qué requerimiento del enunciado atiende | Separadores `----` dentro de cada script |
| Especificación de cada paquete | Una línea de comentario antes de cada procedimiento y función pública explicando qué hace | `CREATE OR REPLACE PACKAGE ...` de los archivos `02`, `03` y `07` |
| Cuerpo de los procedimientos | Pasos numerados (`-- 1) Descargar el padrón`, `-- 2) Cargarlo`), el porqué de cada decisión (bloqueos `FOR UPDATE NOWAIT`, `SAVEPOINT`, transacciones autónomas) y los códigos de error que lanza | Cuerpos (`PACKAGE BODY`) y triggers |
| Diccionario de datos | `COMMENT ON TABLE` y `COMMENT ON COLUMN` en las tablas del modelo | `SELECT table_name, comments FROM all_tab_comments WHERE owner = 'CADENA_NEG';` |
| Modelo | Nota por tabla y por columna, tablas del Avance 2 marcadas con `[AVANCE 2]` y la justificación de cada desnormalización | Carpeta `Modelo_Relacional/`: `modelo_relacional_avance2.dbml` y el documento de desnormalizaciones |

Para revisar en la base la descripción de cualquier objeto del modelo:
```sql
SELECT column_name, comments FROM all_col_comments
 WHERE owner = 'CADENA_NEG' AND table_name = 'VEN_CUENTA_COBRAR';
```
