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

Octubre del 2026

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
|  | (Ventas, Compras, Stock)  |  | (IX_CUCO_EST_VENC)        |  | Inmutable / Errores |  |
|  +---------------------------+  +---------------------------+  +---------------------+  |
|                                                                                         |
|  • Seguridad Criptográfica: Cifrado simétrico AES-256 (DBMS_CRYPTO) en SEG_PARAMETRO.    |
|  • Automatización: 11 Jobs DBMS_SCHEDULER (negocio, padrón TSE y Standby/RMAN).        |
|  • Notificaciones Directas: UTL_SMTP sin VPN hacia keylorpineda729@gmail.com.           |
|  • Vistas Materializadas: MV_VENTAS_MENSUALES y MV_INVENTARIO_CONSOLIDADO.              |
|  • Disparadores Autónomos: Validación estricta de crédito, stock y kardex en tiempo real|
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
| `TBS_DATOS` | `tbs_datos01.dbf` | Contiene las 62 tablas de negocio del sistema (catálogos, transacciones operativas, parámetros y cierres). Segmentos con `EXTENT MANAGEMENT LOCAL AUTOALLOCATE`. |
| `TBS_INDICES` | `tbs_indices01.dbf` | Aloja los 224 índices del esquema (claves primarias, foráneas, únicos y compuestos de afinamiento). Evita contención con las escrituras en tablas de datos. |
| `TBS_AUDITORIA` | `tbs_auditoria01.dbf` | Aloja exclusivamente las tablas inmutables de auditoría (`AUD_REGISTRO_CAMBIO`, `AUD_ERROR_SISTEMA`, `AUD_MONITOREO_BD` y `PRO_PRECIO_HIST`). Diseñado para alta frecuencia de escritura secuencial. |

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
Ningún rol recibe privilegios `DELETE` sobre catálogos ni permisos de modificación estructural `DDL`:

| OBJETO / ACCIÓN | `ROL_DIGITADOR` | `ROL_JEFE_PROVEEDURIA` | `ROL_JEFE_DEPARTAMENTO` | `ROL_GERENTE` |
| :--- | :---: | :---: | :---: | :---: |
| Facturación Ventas (`VEN_FACTURA`, `DET`) | SELECT, INSERT | SELECT | SELECT | SELECT |
| Cobros y Abonos (`VEN_ABONO_COBRAR`, `CxC`) | SELECT, INSERT | SELECT | SELECT | SELECT |
| Compras Proveedores (`COM_FACTURA`, `DET`) | Sin acceso | SELECT, INSERT, UPDATE | SELECT | SELECT |
| Abonos Proveedores (`COM_ABONO_PAGAR`, `CxP`) | Sin acceso | SELECT, INSERT | SELECT | SELECT |
| Catálogo de Productos (`PRO_PRODUCTO`) | SELECT | SELECT | SELECT, UPDATE | SELECT |
| Vistas Materializadas (`MV_VENTAS`, `MV_INV`) | Sin acceso | Sin acceso | SELECT | SELECT |
| Bitácoras de Auditoría (`AUD_REGISTRO_CAMBIO`) | Sin acceso | Sin acceso | Sin acceso | SELECT |
| Borrado de Registros (`DELETE`) | **DENEGADO** | **DENEGADO** | **DENEGADO** | **DENEGADO** |
| Modificación DDL (`DROP TABLE`, `ALTER`) | **DENEGADO** | **DENEGADO** | **DENEGADO** | **DENEGADO** |

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

El sistema implementa 11 disparadores de negocio para forzar la integridad en el motor de base de datos:

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

### 5.1 Regla de Exclusividad de Proveedores y Personas
El modelo impide inconsistencias mediante el supertipo `PER_PERSONA` y la clave alterna `UK_PERS_NATURALEZA (ID_PERSONA, ES_JURIDICA_PERS)`. Se garantiza por diseño del motor que todo proveedor pertenezca forzosamente a una persona jurídica (`ES_JURIDICA_PERS = 'S'`) y nunca a una persona física.

---

## 6. Módulo de Automatización DBMS_SCHEDULER y Notificaciones UTL_SMTP

### 6.1 Catálogo de Jobs Programados

| JOB | FRECUENCIA | ACCIÓN QUE EJECUTA |
| :--- | :--- | :--- |
| `CADENA_NEG.JOB_CIERRE_DIARIO_AUTO` | Diario a las 23:00 | Ejecuta `PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO`, consolidando ventas brutas, devoluciones y montos netos por sucursal y desglosado por cada cajero. Envía reporte al coordinador. |
| `CADENA_NEG.JOB_MONITOREO_SALUD_DIARIO` | Diario a las 06:00 | Ejecuta `PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO`, inspeccionando tablespaces con uso >85%, objetos inválidos, índices corruptos y sesiones concurrentes. |
| `CADENA_NEG.JOB_NOTIF_CREDITOS_DIARIO` | Diario a las 07:00 | Ejecuta `PKG_ADM_NOTIFICACION`: detecta clientes con saldo >= 85% de límite, proveedores con saldo >= 70% de crédito, clientes morosos (>1 mes sin abono) y productos vencidos. |
| `CADENA_NEG.JOB_MERCADEO_SEMANAL` | Lunes a las 05:00 | Ejecuta `PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO` y activa descuentos en `PRM_DESCUENTO` sobre lotes con caducidad próxima (<7 días) o sin rotación (>6 meses). |
| `CADENA_NEG.JOB_PREMIACION_SEMESTRAL` | 30 jun y 31 dic (23:30) | Ejecuta `PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES`, premiando al Top 10 de clientes con órdenes de compra de ₡100,000 c/u emitidas en `PRM_ORDEN_PREMIACION`. |
| `CADENA_NEG.JOB_PADRON_MENSUAL` | Día `PADRON_DIA_CARGA` (5) de cada mes, 02:00 | `PKG_PER_PADRON.PR_ACTUALIZAR_PADRON_MENSUAL`: ejecuta `JOB_PADRON_DESCARGA` (descarga `padron_completo.zip` del TSE) y `PR_CARGAR_PADRON_MASIVO` (tablas externas Latin-1, `MERGE` por provincia, inactiva cédulas que ya no están). |
| `CADENA_NEG.JOB_STANDBY_TRASLADO_ARCHIVELOG` | Cada `STANDBY_SYNC_MIN` (10) min | Job EXECUTABLE: copia archivelogs y respaldos RMAN nuevos a la PC standby. |
| `CADENA_NEG.JOB_RMAN_BACKUP_DIARIO` | Diario, `STANDBY_HORA_BACKUP` (01:00) | Job EXECUTABLE: RMAN nivel 0 (domingo) o nivel 1 y copia del respaldo a la PC standby. |
| `CADENA_NEG.JOB_STANDBY_PURGA_ARCHIVELOG` | Diario, `STANDBY_HORA_PURGA` (03:00) | Job EXECUTABLE: purga archivelogs con más de `STANDBY_PURGE_DIAS` (3) días ya aplicados. |
| `CADENA_NEG.JOB_STANDBY_MONITOREO` | Cada hora | `PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION`: atraso y fallos del standby en `AUD_MONITOREO_BD`, aviso al DBA. |

Los jobs del standby se reconfiguran en caliente con `PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS` después de cambiar un parámetro, y se ejecutan a petición con `PR_SINCRONIZAR_AHORA`, `PR_RESPALDAR_AHORA` y `PR_PURGAR_AHORA` (ver Manual de Administración del Standby).

### 6.2 Envío Directo de Correo Electrónico (`UTL_SMTP`)
* **Sin Dependencia de VPN:** Se conecta de forma directa a servidores SMTP estándar (`smtp.gmail.com` en puerto 465 con SSL; 587 con STARTTLS como alternativa) usando el wallet de Oracle.
* **Formato del correo:** cada notificación sale como mensaje MIME `multipart/alternative` en UTF-8: una versión en texto y otra en **HTML adaptable al celular** (encabezado con el asunto, tablas reales en vez de columnas con espacios y totales en negrita). `PR_ENVIAR_CORREO` convierte automáticamente el texto de cada notificación con `fn_texto_a_html`; `PKG_ADM_NOTIFICACION.FN_VISTA_PREVIA_HTML` devuelve ese HTML para revisarlo sin enviar.
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
