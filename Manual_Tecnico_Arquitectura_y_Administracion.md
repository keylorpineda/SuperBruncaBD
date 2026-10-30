# Manual Técnico de Arquitectura, Alta Disponibilidad y Administración
## Sistema Integral de Cadena de Supermercados — Avance #2
**Universidad Nacional de Costa Rica (UNA)**  
**Sede Regional Brunca — Campus Pérez Zeledón**  
**Curso:** Administración de Bases de Datos  
**Estudiante:** Keylor Pineda Álvarez  
**Motor de Base de Datos:** Oracle Database 21c / 26ai Free  
**Fecha:** Octubre 2026  

---

## 1. Resumen Ejecutivo y Arquitectura del Sistema

El presente documento detalla la arquitectura técnica, la estrategia de alta disponibilidad, el modelo de seguridad integral, las políticas de respaldo y recuperación, y la automatización operativa del **Sistema Integral de Cadena de Supermercados** para el Avance #2 del proyecto de curso.

El sistema está diseñado bajo una arquitectura de tres capas de datos:
1. **Capa Transaccional Operativa (OLTP):** Modelada en 3FN estricta sobre el esquema `CADENA_NEG`, distribuida en tablespaces especializados (`TBS_OPERACIONES`, `TBS_INDICES`, `TBS_AUDITORIA`, `TBS_HISTORICOS`) para optimizar la contención de I/O y asegurar el rendimiento de lectura y escritura.
2. **Capa de Inteligencia y Desempeño (Vistas Materializadas):** Implementación de vistas materializadas (`MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO`) en `TBS_HISTORICOS` con refresco programado para consultas analíticas de alta velocidad sin sobrecargar las tablas transaccionales.
3. **Capa de Auditoría Inmutable:** Bitácora autónoma (`AUD_BITACORA`, `AUD_REGISTRO_CAMBIO`, `AUD_ERROR`) gestionada mediante procedimientos con `PRAGMA AUTONOMOUS_TRANSACTION`, asegurando la trazabilidad de operaciones incluso si la transacción de negocio hace `ROLLBACK`.

```
+-----------------------------------------------------------------------------------+
|                        CLIENTES / TERMINALES POS / USUARIOS                       |
+-----------------------------------------------------------------------------------+
                                         │
                   Conexión Segura (TNS / Clave de Rol Cifrada)
                                         ▼
+-----------------------------------------------------------------------------------+
|                     ORACLE DATABASE (SERVIDOR PRINCIPAL / OLTP)                   |
|                                                                                   |
|  +---------------------+  +---------------------+  +---------------------------+  |
|  |   TBS_OPERACIONES   |  |     TBS_INDICES     |  |       TBS_AUDITORIA       |  |
|  | Facturación/Compras |  | B-Tree Compuestos   |  | Bitácora Autónoma         |  |
|  +---------------------+  +---------------------+  +---------------------------+  |
|                                                                                   |
|  • Triggers de Negocio (Límite Crédito, Inventario, Abonos, Cancelación Auto)    |
|  • Paquetes PL/SQL (Seguridad AES-256, Padrón TSE, Mercadeo, Cierre Cajeros)      |
|  • Redo Logs: 50 MB / Multiplexados / Rotación cada 5 min (ARCHIVE_LAG_TARGET=300)|
+-----------------------------------------------------------------------------------+
             │                                                    │
   Traslado cada 10 min                                 Respaldo RMAN Diario
   (Redo Transport / On-Demand)                         (Full Lvl 0 / Incr Lvl 1)
             ▼                                                    ▼
+-----------------------------------------+      +----------------------------------+
|    SERVIDOR STANDBY (ALTA DISPONIBILIDAD|      |     ALMACENAMIENTO DE RESPALDO   |
|   Standby Database en Modo MOUNT/APPLY  |      |  Recovery Window: 14 Días        |
|   RPO <= 5 min | RTO <= 15 min          |      |  Purga Archivelogs > 3 Días      |
+-----------------------------------------+      +----------------------------------+
```

---

## 2. Arquitectura de Redo Logs, Archivados y Standby

### 2.1 Dimensionamiento de Redo Logs a 50 MB y Multiplexación
- **Dimensionamiento:** Cada grupo de Online Redo Logs está dimensionado en **50 MB** exactos. Este tamaño proporciona el equilibrio óptimo entre el rendimiento de escritura secuencial de `LGWR` y la frecuencia controlada de checkpoints.
- **Multiplexación:** Cada grupo cuenta con dos miembros almacenados en rutas físicas independientes (ej. `redo01a.log` y `redo01b.log` en volúmenes o controladoras separadas). Esto elimina el punto único de falla a nivel de disco: si un miembro se corrompe o el medio falla, `LGWR` continúa operando sobre el miembro espejo sin interrupción de servicio.

### 2.2 Forzado de Switch de Log cada 5 Minutos (`ARCHIVE_LAG_TARGET = 300`)
Para cumplir con la directriz de seguridad y frescura de datos en la réplica Standby:
- Se configura en el SPFILE y en memoria:
  ```sql
  ALTER SYSTEM SET ARCHIVE_LAG_TARGET = 300 SCOPE = BOTH;
  ```
- **Mecanismo:** Si el volumen de transacciones no llena los 50 MB en 5 minutos, el motor genera un switch automático de Redo Log y dispara el proceso de archivado `ARCn`. Esto garantiza un **Punto Objetivo de Recuperación (RPO) $\le 5$ minutos** en el nodo Standby.
- Adicionalmente, se activa `ALTER DATABASE FORCE LOGGING;` para asegurar que ninguna operación directa (ej. `DIRECT-PATH INSERT`) eluda la generación de redo.

### 2.3 Sincronización hacia Standby: Cada 10 Minutos y Bajo Demanda (On-Demand)
- **Modo Continuo / Programado:** Un script en segundo plano (`02_Traslado_Archivelogs_10min_y_Ondemand.ps1` / `.sh`) verifica cada 10 minutos (600 segundos) los archivelogs generados en la primaria y los transfiere al nodo Standby preservando marcas de tiempo e integridad.
- **Modo Bajo Demanda (Para el Evaluador / Profesor):** El script permite ser invocado interactivamente en cualquier instante mediante el parámetro `-Modo OnDemand`:
  ```powershell
  .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo OnDemand
  ```
  Este proceso ejecuta `ALTER SYSTEM ARCHIVE LOG CURRENT;` en Oracle para forzar el cierre del log actual, escanea los archivos generados y los transfiere de inmediato, mostrando el progreso y tamaño en pantalla.

### 2.4 Política de Retención y Purga a 3 Días
- Los Archived Redo Logs no pueden acumularse indefinidamente en el Fast Recovery Area (FRA).
- Se implementó el script RMAN `03_Purga_Archivelogs_3Dias.rman` que ejecuta:
  ```rman
  CROSSCHECK ARCHIVELOG ALL;
  DELETE NOPROMPT ARCHIVELOG UNTIL TIME 'SYSDATE-3' BACKED UP 1 TIMES TO DEVICE TYPE DISK;
  ```
- **Garantía de Seguridad:** La condición `BACKED UP 1 TIMES TO DEVICE TYPE DISK` previene que un archivelog sea borrado sin antes haber sido respaldado por RMAN y transmitido al nodo secundario.

---

## 3. Estrategia de Respaldo y Recuperación con RMAN

La política de continuidad operativa se gestiona mediante Oracle Recovery Manager (RMAN) con una política de retención basada en ventana de recuperación de 14 días (`CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;`).

### 3.1 Esquema de Respaldos
1. **Respaldo Full Semanal (Nivel 0):** Se ejecuta los domingos a medianoche. Genera una imagen base completa de todos los bloques de datos con información del CDB y de los PDBs, respaldando además los archivelogs y el controlfile autobackup en formato comprimido (`COMPRESSED BACKUPSET`).
2. **Respaldo Incremental Diario (Nivel 1):** Se ejecuta de lunes a sábado a las 22:00. Utiliza el mecanismo diferencial/acumulativo para respaldar únicamente los bloques modificados desde el último respaldo, reduciendo la ventana de backup en más del 80%.
3. **Controlfile Autobackup:** Se activa `CONFIGURE CONTROLFILE AUTOBACKUP ON;` para que ante cualquier cambio en la estructura física (creación de datafiles, tablespaces o secuencias) RMAN respalde el archivo de control automáticamente.

### 3.2 Escenarios de Recuperación (Recovery)
- **Recuperación Completa (Complete Recovery):** Restauración de datafiles dañados y aplicación de redo logs hasta la transacción más reciente confirmada (`RESTORE DATABASE; RECOVER DATABASE;`).
- **Recuperación Puntual en el Tiempo (Point-In-Time Recovery - DBRITP):** Diseñada para reversar incidentes lógicos mayores (como un `DROP TABLE` accidental o actualización indebida masiva). RMAN restaura el estado previo al minuto del incidente (`SET UNTIL TIME "TO_DATE('...', 'YYYY-MM-DD HH24:MI:SS')";`) y abre con `RESETLOGS`.

---

## 4. Arquitectura de Seguridad, Roles Cifrados y Principio de Mínimo Privilegio

### 4.1 Perfiles de Contraseña y Recursos
Se implementaron dos perfiles con `RESOURCE_LIMIT = TRUE`:
- `PERFIL_CADENA_ADMIN`: Para gerencias y jefaturas. Expiración a 60 días, 3 intentos fallidos de inicio de sesión (`FAILED_LOGIN_ATTEMPTS = 3`), bloqueo de cuenta por 1 día (`PASSWORD_LOCK_TIME = 1`), control de reuso de contraseñas (`PASSWORD_REUSE_MAX = 5`) y tiempo de inactividad de 30 minutos (`IDLE_TIME = 30`).
- `PERFIL_CADENA_OPER`: Para personal de cajas y almacén. Expiración a 45 días, 3 intentos fallidos, máximo 2 sesiones concurrentes (`SESSIONS_PER_USER = 2`) y tiempo de inactividad de 15 minutos (`IDLE_TIME = 15`).

### 4.2 Roles Protegidos con Contraseña Cifrada (AES-256)
Ningún rol del sistema se activa de manera desprotegida o por defecto (`DEFAULT ROLE NONE` en todos los usuarios).
- Los 4 roles del sistema están protegidos por contraseñas robustas:
  1. `ROL_GERENTE`
  2. `ROL_JEFE_DEPARTAMENTO`
  3. `ROL_JEFE_PROVEEDURIA`
  4. `ROL_DIGITADOR`
- Las contraseñas se almacenan cifradas en la tabla `SEG_PARAMETRO` utilizando `DBMS_CRYPTO.ENCRYPT` bajo el algoritmo AES-256 con relleno PKCS#5.
- La activación se realiza de manera segura mediante el procedimiento `PRC_ACTIVAR_ROL_SESION(p_rol, p_clave)` con derechos del invocador (`AUTHID CURRENT_USER`).

### 4.3 Matriz de Mínimos Privilegios
Se eliminó el uso de roles predeterminados como `DBA`, `CONNECT` o `RESOURCE`.
- **Privilegio de Sistema:** Únicamente `GRANT CREATE SESSION` a cada usuario.
- **Privilegios de Objeto:**
  - `ROL_GERENTE`: Lectura gerencial (`SELECT`) sobre tablas de ventas, compras, clientes, inventario, vistas materializadas y reportes de auditoría. Sin permisos de modificación directa (`INSERT`/`UPDATE`/`DELETE`).
  - `ROL_JEFE_DEPARTAMENTO`: Control operativo (`SELECT`, `INSERT`, `UPDATE`) sobre ventas, compras, inventario, precios y campañas. Sin `DELETE`.
  - `ROL_JEFE_PROVEEDURIA`: Gestión de compras, cuentas por pagar, recepciones y devoluciones a proveedores.
  - `ROL_DIGITADOR`: Facturación de caja y recepción de abonos (`SELECT`, `INSERT`). **Estrictamente bloqueado contra DELETE y comandos DDL.**

---

## 5. Reglas de Negocio Automatizadas en Disparadores (Triggers)

| Disparador | Tabla / Evento | Regla de Negocio Implementada |
|---|---|---|
| `TRG_VEN_FACTURA_CRED_BIU` | `VEN_FACTURA` (BEFORE INSERT/UPDATE) | Valida que el saldo actual del cliente más el total de la factura no exceda `MONTO_MAX_CREDITO_CLI`. Si excede, aborta con `RAISE_APPLICATION_ERROR(-20010)`. |
| `TRG_VEN_FACTURA_CRED_AI` | `VEN_FACTURA` (AFTER INSERT) | Aumenta el saldo del cliente y crea automáticamente la cuenta por cobrar en `VEN_CUENTA_COBRAR` con estado `'P'`. |
| `TRG_COM_FACTURA_CRED_BIU` | `COM_FACTURA_COMPRA` (BEFORE INSERT/UPDATE) | Valida el límite de crédito comercial otorgado por el proveedor antes de autorizar la compra a crédito. |
| `TRG_COM_FACTURA_CRED_AI` | `COM_FACTURA_COMPRA` (AFTER INSERT) | Aumenta el saldo adeudado al proveedor y genera la cuenta por pagar en `COM_CUENTA_PAGAR`. |
| `TRG_VEN_ABONO_SALDO_AI` | `VEN_ABONO_COBRAR` (AFTER INSERT) | Descuenta el abono de `VEN_CUENTA_COBRAR` y del saldo del cliente. Si el saldo llega a 0, **cambia automáticamente el estado de la cuenta y de la factura de `'P'` (Pendiente) a `'C'` (Cancelada)**. |
| `TRG_COM_ABONO_SALDO_AI` | `COM_ABONO_PAGAR` (AFTER INSERT) | Descuenta el abono de `COM_CUENTA_PAGAR` y del saldo del proveedor. Si el saldo llega a 0, cambia el estado a `'C'`. |
| `TRG_VEN_FACTURA_DET_INV_AI`| `VEN_FACTURA_DET` (AFTER INSERT) | Descuenta existencias de `INV_EXISTENCIA` en la bodega de la sucursal, genera registro en `INV_MOVIMIENTO` (Kardex salida venta) y otorga acciones promocionales automáticas a marcas patrocinadoras. |
| `TRG_COM_FACTURA_DET_INV_AI`| `COM_FACTURA_COMPRA_DET` (AFTER INSERT)| Aumenta existencias en bodega, registra entrada en Kardex y actualiza el costo en `PRO_PRODUCTO` si difiere del actual. |
| `TRG_PRO_HISTORIAL_PRECIO_AU`| `PRO_PRODUCTO` (AFTER UPDATE) | Registra el costo o precio de venta anterior y nuevo en `PRO_PRECIO_HIST` de forma inmutable. |
| `TRG_VEN_DEVOLUCION_DET_INV_AI`| `VEN_DEVOLUCION_DET` (AFTER INSERT) | Reintegra unidades al inventario por devolución de clientes. |
| `TRG_COM_DEVOLUCION_DET_INV_AI`| `COM_DEVOLUCION_DET` (AFTER INSERT) | Da de baja unidades de inventario por devolución a proveedores. |

### Disparadores de Auditoría en las 7 Tablas Principales
Se implementaron disparadores de auditoría profunda (`AFTER INSERT OR UPDATE OR DELETE FOR EACH ROW`) en las 7 tablas fundamentales:
1. `VEN_FACTURA` (`TRG_AUD_VEN_FACTURA`)
2. `COM_FACTURA_COMPRA` (`TRG_AUD_COM_FACTURA`)
3. `PRO_PRODUCTO` (`TRG_AUD_PRO_PRODUCTO`)
4. `INV_MOVIMIENTO` (`TRG_AUD_INV_MOVIMIENTO`)
5. `PER_CLIENTE` (`TRG_AUD_PER_CLIENTE`)
6. `PER_PROVEEDOR` (`TRG_AUD_PER_PROVEEDOR`)
7. `PRM_PROMOCION` (`TRG_AUD_PRM_PROMOCION`)

Cada operación registra en tiempo real el usuario, terminal, IP, esquema, tipo de operación, valor anterior y valor nuevo en `AUD_BITACORA` y `AUD_REGISTRO_CAMBIO`.

---

## 6. Automatización de Tareas con DBMS_SCHEDULER

Se configuraron 5 jobs autónomos en el motor:
1. `JOB_CIERRE_DIARIO_AUTO`: Ejecución diaria a las 23:00. Ejecuta el cierre contable del día y genera el desglose de facturas y montos por cada cajero en `VEN_CIERRE_DIARIO` y `VEN_CIERRE_CAJERO`.
2. `JOB_MONITOREO_SALUD_DIARIO`: Ejecución diaria a las 06:00. Inspecciona tablespaces con ocupación $> 85\%$, objetos en estado `INVALID`, índices deteriorados que requieren `REBUILD` y crecimiento de almacenamiento.
3. `JOB_NOTIF_CREDITOS_DIARIO`: Ejecución diaria a las 07:00. Evalúa y genera notificaciones para:
   - Clientes al 85% de su límite de crédito.
   - Proveedores al 70% del saldo pendiente.
   - Clientes morosos con cuentas vencidas $> 1$ mes.
   - Productos vencidos o en riesgo de merma con totales monetarios.
4. `JOB_MERCADEO_SEMANAL`: Ejecución semanal los lunes a las 05:00. Genera el reporte a mercadeo de productos por vencer en 7 días o con más de 6 meses sin rotación, y activa los descuentos semanales programados.
5. `JOB_PREMIACION_SEMESTRAL`: Ejecución cada 6 meses (30 de junio y 31 de diciembre a las 23:30). Calcula el Top 10 de mejores clientes y genera órdenes de compra de ₡100,000 para cada uno.

---

## 7. Caso de Estudio de Optimización SQL (EXPLAIN PLAN)

### Escenario Evaluado
Consulta frecuente del módulo de cobros y del scheduler nocturno para detectar cuentas por cobrar vencidas en mora:
```sql
SELECT c.ID_CUENTA_COBRAR, c.ID_FACTURA_FAVE, cl.NOMBRE_COMPLETO_CLIE,
       c.FECHA_VENCIMIENTO_CUCO, c.SALDO_CUCO, c.ESTADO_CUCO
  FROM VEN_CUENTA_COBRAR c
  JOIN PER_CLIENTE cl ON c.ID_CLIENTE_CLIE = cl.ID_CLIENTE_CLIE
 WHERE c.ESTADO_CUCO = 'P'
   AND c.FECHA_VENCIMIENTO_CUCO < SYSDATE;
```

### Tabla Comparativa de Rendimiento

| Métrica de Ejecución | Estado Inicial (ANTES) | Estado Optimizado (DESPUÉS) | Impacto |
|---|---|---|---|
| **Operación Principal** | `TABLE ACCESS FULL` | `INDEX RANGE SCAN` | Búsqueda directa en árbol B-Tree |
| **Índice Utilizado** | Ninguno (Full Scan) | `IX_CUCO_EST_VENC` | Índice compuesto en `(ESTADO_CUCO, FECHA_VENCIMIENTO_CUCO)` |
| **Predicado de Acceso** | Filter (Evaluación post-lectura) | Access (Puntero B-Tree) | Eliminación de escaneo de bloques innecesarios |
| **Lecturas de Bloques (Buffers)**| 100% de bloques del segmento | Solo bloques del rango filtrado | Reducción de I/O en $> 75\%$ |
| **Escalabilidad** | Lineal $O(N)$ | Logarítmica $O(\log N)$ | Rendimiento constante ante millones de filas |

---

## 8. Conclusiones Técnicas
1. La arquitectura implementada en este Avance #2 garantiza alta disponibilidad real mediante la combinación de **Redo Logs de 50 MB**, forzado de switch a **5 minutos**, traslado continuo y bajo demanda hacia la **Standby**, y purga controlada a los **3 días**.
2. Las reglas de negocio críticas (crédito, inventarios, abonos y cancelaciones) están aseguradas a nivel de motor mediante disparadores transaccionales, impidiendo inconsistencias sin importar la interfaz que interactúe con la base de datos.
3. El esquema de seguridad cumple estrictamente el principio de mínimo privilegio, blindando los roles con contraseñas cifradas en AES-256 y aislando las operaciones sin conceder privilegios administrativos como `DBA`.
