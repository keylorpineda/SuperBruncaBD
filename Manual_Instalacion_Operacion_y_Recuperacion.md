# Manual de Instalación, Operación y Recuperación
## Sistema Integral de Cadena de Supermercados — Avance #2
**Universidad Nacional de Costa Rica (UNA)**  
**Sede Regional Brunca — Campus Pérez Zeledón**  
**Curso:** Administración de Bases de Datos  
**Estudiante:** Keylor Pineda Álvarez  
**Motor:** Oracle Database 21c / 23ai / 26ai Free  
**Fecha:** Octubre 2026  

---

## 1. Requisitos Previos del Entorno

Para la ejecución exitosa de los scripts y la evaluación de los requerimientos, el evaluador o DBA debe contar con:
1. **Instancia Oracle Database:** Oracle 21c XE, 23ai Free o 26ai Free en ejecución con un Pluggable Database (PDB) en modo `READ WRITE` (ej. `FREEPDB1` o `XEPDB1`).
2. **Herramientas de Cliente:** SQL*Plus, SQL Developer o DBeaver con conexión administrativa (`SYS as SYSDBA` o `SYSTEM`).
3. **Utilidad de Respaldo:** Oracle Recovery Manager (`rman`).
4. **Intérprete de Scripts:** PowerShell 5.1+ (en Windows) o Bash (en Linux).
5. **Permisos de Archivo:** Permiso de lectura y escritura en los discos locales para creación de tablespaces y directorios de archivado.

---

## 2. Secuencia Oficial de Instalación y Despliegue

Todos los scripts han sido construidos con **idempotencia estricta** (detectan automáticamente el PDB activo, eliminan objetos previos si existen y recrean estructuras limpias sin arrojar errores fatales).

La ejecución debe realizarse en el siguiente orden secuencial exacto:

### Paso 0: Base del Sistema (Entregable #1)
Si la base de datos es nueva o requiere restablecerse desde cero:
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @script_bd_v2.sql
```
> *Nota: Crea el esquema `CADENA_NEG`, tablespaces base y las 25 tablas del Avance #1.*

---

### Paso 1: Adaptaciones DDL, Nuevas Tablas y Vistas Materializadas
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @01_Estructuras_Avance2.sql
```
**Acciones que ejecuta:**
- Adiciona columnas a tablas existentes (`PER_CLIENTE.CODIGO_ELECTORAL_CLI`, etc.).
- Crea las **11 tablas nuevas**: `PER_PADRON_TSE`, `PRO_PRECIO_HIST`, `PRM_ACCION`, `PRM_DESCUENTO_SEMANAL`, `VEN_CIERRE_CAJERO`, `VEN_DEVOLUCION_DET`, `COM_DEVOLUCION_DET`, `AUD_REGISTRO_CAMBIO`, `SEG_PARAMETRO`, `ADM_MONITOREO_LOG`, `ADM_NOTIFICACION_LOG`.
- Crea y puebla las vistas materializadas `MV_VENTAS_MENSUALES` y `MV_INVENTARIO_CONSOLIDADO` en `TBS_HISTORICOS`.
- Inserta datos de prueba (mínimo 5 filas por tabla) y realinea las secuencias numéricas.

---

### Paso 2: Paquetes de Seguridad, Auditoría y Notificaciones
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @02_Paquetes_Seguridad_Auditoria_Notificaciones.sql
```
**Acciones que ejecuta:**
- Compila `PKG_AUD_CONTROL`: Auditoría autónoma de operaciones, cambios por campo y errores.
- Compila `PKG_SEG_SEGURIDAD`: Cifrado y descifrado AES-256 con `DBMS_CRYPTO`, gestión de parámetros y asignación de contraseñas a roles.
- Compila `PRC_ACTIVAR_ROL_SESION`: Procedimiento con `AUTHID CURRENT_USER` para activación segura de roles protegidos.
- Compila `PKG_ADM_NOTIFICACION`: Envío de correos por `UTL_SMTP` y verificación de umbrales (85% CxC, 70% CxP, morosos >1 mes, productos vencidos).

---

### Paso 3: Paquetes de Negocio y Monitoreo del Motor
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @03_Paquetes_Negocio_Monitoreo.sql
```
**Acciones que ejecuta:**
- Compila `PKG_PER_PADRON`: Carga del padrón electoral TSE mediante `UTL_FILE` y vinculación con clientes.
- Compila `PKG_INV_GESTION`: Control de inventario con concurrencia `FOR UPDATE WAIT 5`, Kardex y reporte de productos en riesgo a mercadeo.
- Compila `PKG_COM_OPERACION`: Facturación de compra, abonos a proveedores y devoluciones.
- Compila `PKG_VEN_OPERACION`: Facturación en punto de venta, abonos de clientes, devoluciones y cierre contable diario por cajero.
- Compila `PKG_PRM_MERCADEO`: Descuentos semanales, otorgamiento de acciones a patrocinadores y premiación del Top 10 de clientes con órdenes de ₡100,000.
- Compila `PKG_ADM_MONITOREO`: Monitoreo de tablespaces $> 85\%$, objetos inválidos, índices fragmentados y sesiones activas.

---

### Paso 4: Disparadores de Reglas de Negocio y Auditoría
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @04_Triggers_Negocio_y_Auditoria.sql
```
**Acciones que ejecuta:**
- Disparadores de crédito: Valida límite de crédito en ventas y compras; rechaza transacciones no autorizadas.
- Disparadores de abonos: Descuenta saldos y **cancela automáticamente la factura y la cuenta (cambio de 'P' a 'C')** cuando el saldo llega a 0.
- Disparadores de inventario: Descuenta stock en ventas, aumenta en compras y registra en Kardex.
- Disparadores de auditoría en las **7 tablas principales** (`VEN_FACTURA`, `COM_FACTURA_COMPRA`, `PRO_PRODUCTO`, `INV_MOVIMIENTO`, `PER_CLIENTE`, `PER_PROVEEDOR`, `PRM_PROMOCION`) capturando valores anteriores y nuevos en `AUD_REGISTRO_CAMBIO`.

---

### Paso 5: Perfiles de Seguridad, Roles con Contraseña y Usuarios
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @05_Seguridad_Perfiles_Roles_Usuarios.sql
```
**Acciones que ejecuta:**
- Crea los perfiles `PERFIL_CADENA_ADMIN` y `PERFIL_CADENA_OPER`.
- Crea los roles protegidos: `ROL_GERENTE`, `ROL_JEFE_DEPARTAMENTO`, `ROL_JEFE_PROVEEDURIA`, `ROL_DIGITADOR` con contraseñas cifradas.
- Aplica la matriz de mínimos privilegios sin roles administrativos (`DBA`, `CONNECT`, `RESOURCE`).
- Crea los usuarios `USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR` con `DEFAULT ROLE NONE`.
- Ejecuta pruebas en vivo mostrando `[OK AUTORIZADO]` para transacciones válidas y `[OK RECHAZADO]` ante intentos no autorizados de `DELETE` o `DROP TABLE`.

---

### Paso 6: Automatización de Tareas (Jobs), Optimización SQL y Batería de Pruebas
```bash
sqlplus system/oracle@localhost:1521/FREEPDB1 @06_Scheduler_Optimizacion_y_Pruebas.sql
```
**Acciones que ejecuta:**
- Programa los 5 jobs en `DBMS_SCHEDULER` (Cierre diario 23:00, Monitoreo 06:00, Notificaciones 07:00, Mercadeo semanal lunes 05:00, Premiación semestral).
- Ejecuta el estudio de afinamiento con `EXPLAIN PLAN` + `DBMS_XPLAN` demostrando la transformación de `TABLE ACCESS FULL` a `INDEX RANGE SCAN` mediante `IX_CUCO_EST_VENC`.
- Ejecuta la **batería integral de 9 pruebas de verificación** de extremo a extremo.

---

### Paso 7: Configuración de Alta Disponibilidad y Redo Logs (CDB$ROOT)
Conectándose a nivel de contenedor administrativo (`CDB$ROOT`):
```bash
sqlplus / as sysdba @07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
```
**Acciones que ejecuta:**
- Reconfigura Redo Logs a **50 MB** con 2 miembros multiplexados por grupo.
- Configura `ARCHIVE_LAG_TARGET = 300` para forzar el switch cada **5 minutos**.
- Activa `FORCE LOGGING` y configura destinos de archivado local y remoto hacia la Standby.

---

## 3. Guía de Operación para el Evaluador

### 3.1 Cómo Probar el Traslado de Logs hacia la Standby (Bajo Demanda)
El profesor o evaluador puede forzar la sincronización inmediata hacia la base de datos Standby ejecutando:

**En Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File "07_Standby_y_RMAN\02_Traslado_Archivelogs_10min_y_Ondemand.ps1" -Modo OnDemand
```

**En Linux:**
```bash
chmod +x 07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh
./07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh ondemand
```

**Salida esperada en pantalla:**
```
========================================================================
   SISTEMA DE TRANSFERENCIA DE ARCHIVED REDO LOGS A SERVIDOR STANDBY   
========================================================================
[MODO ON-DEMAND / EVALUADOR]: Ejecutando sincronizacion inmediata...
Solicitando forzar ARCHIVE LOG CURRENT en Oracle...
[OK] Se ejecuto con exito ALTER SYSTEM ARCHIVE LOG CURRENT.
Total de Archived Logs detectados en origen: 4
  -> Transferido: cadena_arch_1_102_123456.arc (50.00 MB)
[OK] Transferencia completada: 1 archivo(s) nuevos enviados al nodo Standby.
>>> Sincronizacion bajo demanda finalizada exitosamente.
```

---

### 3.2 Cómo Probar la Purga de Archivelogs Mayores a 3 Días
Para inspeccionar y purgar logs archivados que superen los 3 días de retención y que ya cuenten con respaldo:

1. **Consulta de diagnóstico en SQL:**
   ```bash
   sqlplus / as sysdba @07_Standby_y_RMAN/03_Purga_Archivelogs_3Dias.sql
   ```
2. **Ejecución física de purga en RMAN:**
   ```bash
   rman target / cmdfile=07_Standby_y_RMAN/03_Purga_Archivelogs_3Dias.rman
   ```

---

### 3.3 Cómo Ejecutar los Respaldos RMAN Full e Incremental
Para ejecutar el ciclo de respaldo con compresión y validación estructural:
```bash
rman target / cmdfile=07_Standby_y_RMAN/04_RMAN_Backup_Full_Incremental.rman
```
**Verificación posterior en RMAN:**
```rman
RMAN> LIST BACKUP SUMMARY;
RMAN> REPORT NEED BACKUP;
```

---

### 3.4 Cómo Probar la Activación de Roles Protegidos por Contraseña
Conectándose con un usuario operativo (ej. `USR_DIGITADOR`):
```sql
CONNECT USR_DIGITADOR/"Digitador2026#Sec"@localhost:1521/FREEPDB1

-- 1. Intentar consultar sin activar rol (Acceso denegado o tablas invisibles)
SELECT * FROM CADENA_NEG.PRO_PRODUCTO;
-- ORA-00942: table or view does not exist

-- 2. Activar el rol protegido mediante el procedimiento seguro con contraseña cifrada
EXEC CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR', 'ClaveDigitador2026*');

-- 3. Consultar nuevamente (Acceso autorizado exitoso)
SELECT ID_PRODUCTO_PROD, CODIGO_BARRAS_PROD, NOMBRE_PROD, PRECIO_VENTA_PROD 
  FROM CADENA_NEG.PRO_PRODUCTO 
 FETCH FIRST 5 ROWS ONLY;

-- 4. Demostración de mínimo privilegio: Intento de DELETE (Bloqueado)
DELETE FROM CADENA_NEG.PRO_PRODUCTO WHERE ID_PRODUCTO_PROD = 1;
-- ORA-01031: insufficient privileges
```

---

## 4. Procedimientos de Recuperación y Conmutación de Roles

### 4.1 Recuperación ante Desastre (RMAN Restore & Recover)
Si ocurre una pérdida de datafiles en el servidor principal:
```bash
rman target /
```
```rman
RMAN> STARTUP MOUNT;
RMAN> RESTORE DATABASE;
RMAN> RECOVER DATABASE;
RMAN> ALTER DATABASE OPEN;
```

### 4.2 Switchover (Conmutación Planificada de Roles: Primaria a Standby)
Para mantenimientos planificados sin pérdida de transacciones:
1. **En la Primaria:**
   ```sql
   ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
   SHUTDOWN IMMEDIATE;
   STARTUP MOUNT;
   ```
2. **En la Standby:**
   ```sql
   ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
   ALTER DATABASE OPEN;
   ```

### 4.3 Failover (Activación Forzada por Desastre Mayor)
Si el servidor principal queda destruido o inoperable:
**En el servidor Standby:**
```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
ALTER DATABASE ACTIVATE PHYSICAL STANDBY;
ALTER DATABASE OPEN;
```

---

## 5. Checklist de Verificación para el Evaluador

| # | Requerimiento Evaluado | Archivo de Verificación | Resultado Esperado |
|---|---|---|---|
| 1 | 11 tablas nuevas con secuencias, índices y comentarios | `01_Estructuras_Avance2.sql` | 11 tablas creadas en `CADENA_NEG` |
| 2 | Vistas Materializadas en `TBS_HISTORICOS` | `01_Estructuras_Avance2.sql` | `MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO` |
| 3 | Cifrado AES-256 de parámetros y contraseñas de roles | `02_Paquetes_...sql` | `PKG_SEG_SEGURIDAD` con `DBMS_CRYPTO` |
| 4 | Carga TSE Padrón Electoral (`UTL_FILE`) | `03_Paquetes_...sql` | `PKG_PER_PADRON.PR_ENLAZAR_CLIENTES_CON_PADRON` |
| 5 | Concurrencia de Inventario con `FOR UPDATE WAIT 5` | `03_Paquetes_...sql` | `PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA` |
| 6 | Cierre contable diario con desglose por cajero | `03_Paquetes_...sql` | `VEN_CIERRE_DIARIO` y `VEN_CIERRE_CAJERO` |
| 7 | Validación de límite de crédito en facturas | `04_Triggers_...sql` | Rechazo automático ante sobregiro |
| 8 | Cancelación automática de factura al liquidar cuenta ('P' a 'C') | `04_Triggers_...sql` | `TRG_VEN_ABONO_SALDO_AI` |
| 9 | Disparadores de auditoría en las 7 tablas principales | `04_Triggers_...sql` | Registro detallado en `AUD_REGISTRO_CAMBIO` |
| 10 | Roles protegidos por clave y mínimo privilegio | `05_Seguridad_...sql` | Sin `DBA`/`CONNECT`/`RESOURCE`; pruebas `[OK]` y `[RECHAZADO]` |
| 11 | 5 Jobs con `DBMS_SCHEDULER` | `06_Scheduler_...sql` | Jobs registrados en `ALL_SCHEDULER_JOBS` |
| 12 | Optimización `EXPLAIN PLAN` (FTS vs Index Range Scan) | `06_Scheduler_...sql` | Cuadro comparativo y reducción de costo |
| 13 | Redo Logs a 50 MB / Switch cada 5 min | `07_Standby_y_RMAN/01_...` | `ARCHIVE_LAG_TARGET = 300` |
| 14 | Traslado cada 10 min y Bajo Demanda (On-Demand) | `07_Standby_y_RMAN/02_...` | Script ejecutable en modo interactivo |
| 15 | Purga automática de Archivelogs a 3 días | `07_Standby_y_RMAN/03_...` | RMAN Delete archivelog until sysdate-3 |
| 16 | Respaldo Full Semanal e Incremental Diario | `07_Standby_y_RMAN/04_...` | RMAN Level 0 / Level 1 comprimido |
