# Manual de Administración del Servidor Standby y Alta Disponibilidad
## Sistema Integral de Cadena de Supermercados — Avance #2
**Universidad Nacional de Costa Rica (UNA)**  
**Sede Regional Brunca — Campus Pérez Zeledón**  
**Curso:** Administración de Bases de Datos  
**Estudiante:** Keylor Pineda Álvarez  
**Motor:** Oracle Database 21c / 26ai Free  
**Fecha:** Octubre 2026  

---

## 1. Introducción y Arquitectura de Alta Disponibilidad

Este documento constituye el **Manual de Administración del Servidor Standby**, cubriendo la totalidad de requerimientos del rubro de *Disponibilidad y Recuperación (Standby)* (35% de la calificación):
- Configuración de dos servidores físicos o lógicos distintos (Servidor Principal `CADENA_PRIM` y Servidor Standby `CADENA_STBY`).
- Dimensionamiento de Redo Logs a **50 MB** por grupo con miembros multiplexados.
- Forzado de cambio de log cada **5 minutos** (`ARCHIVE_LAG_TARGET = 300`).
- Traslado continuo cada **10 minutos** y script **Bajo Demanda (On-Demand)** para evaluación interactiva del profesor.
- Purga automática de logs archivados mayores a **3 días** (`SYSDATE-3`) una vez respaldados.
- Estrategia de respaldo y recuperación con Oracle Recovery Manager (RMAN).
- Procedimientos paso a paso de conmutación de roles (**Switchover**) y contingencia por desastre (**Failover**).

```
+---------------------------------------+         +---------------------------------------+
|     SERVIDOR PRINCIPAL (PRIMARIA)     |         |       SERVIDOR STANDBY (REPLICA)      |
|  Host: srv-db-prim (192.168.1.100)    |         |  Host: srv-db-stby (192.168.1.101)    |
|  Instancia: FREE / PDB: FREEPDB1      |         |  Instancia: FREESTBY                  |
|  Estado: READ WRITE (Transaccional)   |         |  Estado: MOUNT / MANAGED RECOVERY     |
|                                       |         |                                       |
|  • Redo Logs: 50 MB (Multiplexados)   |         |  • Standby Redo Logs: 50 MB           |
|  • ARCHIVE_LAG_TARGET: 300 seg (5 min)|         |  • Proceso MRP0 (Managed Recovery)    |
|  • FORCE LOGGING: Habilitado          |         |  • Destino: /opt/oracle/standby_arch  |
+---------------------------------------+         +---------------------------------------+
                    │                                                 ▲
                    │──── Traslado Automático (cada 10 min) ──────────│
                    │──── Sincronización Bajo Demanda (On-Demand) ────│
                    ▼                                                 │
          Archived Redo Logs                                 RMAN Incremental / Logs
          (Purga a los 3 días)                                (Aplicación Continua)
```

---

## 2. Configuración en la Base de Datos Primaria

### 2.1 Conexión y Modo de Operación
Para configurar los parámetros a nivel de motor, conéctese como `SYSDBA` en `CDB$ROOT`:
```sql
sqlplus / as sysdba
ALTER SESSION SET CONTAINER = CDB$ROOT;
```

### 2.2 Forzado de Registro en Redo (FORCE LOGGING)
Evita que operaciones de carga masiva omitan la generación de registros de rehacer:
```sql
ALTER DATABASE FORCE LOGGING;
```

### 2.3 Dimensionamiento de Redo Logs a 50 MB con Multiplexación
Se requiere que cada grupo mida exactamente 50 MB y cuente con 2 miembros en discos o rutas distintas:
```sql
-- 1. Crear grupos de 50 MB
ALTER DATABASE ADD LOGFILE GROUP 4 SIZE 50M;
ALTER DATABASE ADD LOGFILE GROUP 5 SIZE 50M;
ALTER DATABASE ADD LOGFILE GROUP 6 SIZE 50M;

-- 2. Agregar miembros multiplexados
ALTER DATABASE ADD LOGFILE MEMBER 'C:\app\oracle\oradata\redo04b.log' TO GROUP 4;
ALTER DATABASE ADD LOGFILE MEMBER 'C:\app\oracle\oradata\redo05b.log' TO GROUP 5;
ALTER DATABASE ADD LOGFILE MEMBER 'C:\app\oracle\oradata\redo06b.log' TO GROUP 6;

-- 3. Forzar checkpoints y rotación hacia los nuevos grupos
ALTER SYSTEM CHECKPOINT;
ALTER SYSTEM SWITCH LOGFILE;
```

### 2.4 Forzado de Rotación cada 5 Minutos (ARCHIVE_LAG_TARGET = 300)
Garantiza que la base de datos archive un log al menos cada 300 segundos, logrando un **RPO $\le 5$ minutos**:
```sql
ALTER SYSTEM SET ARCHIVE_LAG_TARGET = 300 SCOPE = BOTH;
```

---

## 3. Traslado de Archivelogs: Cada 10 Minutos y Bajo Demanda

### 3.1 Traslado Programado (Cada 10 Minutos)
El script de transferencia se ejecuta de forma desatendida en segundo plano:
- **Windows:** Tarea programada en el *Task Scheduler* ejecutando cada 10 minutos:
  ```powershell
  powershell -ExecutionPolicy Bypass -File "07_Standby_y_RMAN\02_Traslado_Archivelogs_10min_y_Ondemand.ps1" -Modo Programado
  ```
- **Linux:** Entrada en el crontab (`crontab -e`):
  ```bash
  */10 * * * * /opt/oracle/scripts/02_Traslado_Archivelogs_10min_y_Ondemand.sh cron >/dev/null 2>&1
  ```

### 3.2 Traslado Bajo Demanda (Para Evaluación del Profesor)
Cuando el profesor solicite verificar la sincronización inmediata en la defensa:

**En Windows (PowerShell):**
```powershell
.\07_Standby_y_RMAN\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo OnDemand
```

**En Linux:**
```bash
./07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh ondemand
```

**Comportamiento del Script:**
1. Ejecuta en Oracle: `ALTER SYSTEM ARCHIVE LOG CURRENT;` forzando el cierre del log activo.
2. Identifica todos los archivos de redo archivado pendientes de transferir.
3. Transfiere los archivos mediante copia segura (Robocopy / Rsync).
4. Despliega en pantalla el listado de archivos transferidos con su peso en megabytes.

---

## 4. Política de Purga de Archivelogs a 3 Días

Para no agotar el espacio del Fast Recovery Area (FRA) ni del servidor Standby, los logs archivados con más de **3 días de antigüedad** son eliminados automáticamente, **siempre y cuando ya hayan sido respaldados por RMAN al menos una vez**.

### 4.1 Comando RMAN de Purga
```bash
rman target / cmdfile=07_Standby_y_RMAN/03_Purga_Archivelogs_3Dias.rman
```

**Contenido de la instrucción RMAN:**
```rman
CROSSCHECK ARCHIVELOG ALL;
DELETE NOPROMPT ARCHIVELOG UNTIL TIME 'SYSDATE-3' BACKED UP 1 TIMES TO DEVICE TYPE DISK;
```

---

## 5. Estrategia de Respaldo y Recuperación RMAN

### 5.1 Respaldo Full Semanal (Nivel 0) e Incremental Diario (Nivel 1)
Ejecutar el script RMAN integral:
```bash
rman target / cmdfile=07_Standby_y_RMAN/04_RMAN_Backup_Full_Incremental.rman
```

- **Respaldo Nivel 0 (Domingos 00:00):** Respalda la totalidad de bloques utilizados en el CDB y PDBs en formato comprimido (`COMPRESSED BACKUPSET`).
- **Respaldo Nivel 1 (Lunes a Sábado 22:00):** Respalda exclusivamente los bloques modificados desde el último backup, reduciendo el consumo de disco y tiempo de ejecución.
- **Autobackup del Controlfile:** Se genera con formato `%F` en cada operación de respaldo.

### 5.2 Validación Estructural de Respaldos
Para verificar que las piezas de respaldo no sufran corrupción física:
```rman
RMAN> RESTORE VALIDATE DATABASE;
RMAN> RESTORE VALIDATE CONTROLFILE;
```

---

## 6. Monitoreo de Brecha de Sincronización (Redo Gap)

Para verificar en cualquier momento que la Standby está al día con la Primaria:

### 6.1 En la Primaria:
```sql
SELECT thread#, MAX(sequence#) AS ultima_secuencia_primaria
  FROM v$archived_log
 WHERE status = 'A'
 GROUP BY thread#;
```

### 6.2 En la Standby:
```sql
SELECT thread#, MAX(sequence#) AS ultima_secuencia_recibida,
       MAX(sequence#) KEEP (DENSE_RANK LAST ORDER BY first_time) AS ultima_aplicada
  FROM v$archived_log
 WHERE applied = 'YES'
 GROUP BY thread#;
```

### 6.3 Verificación de Gaps Faltantes:
```sql
SELECT * FROM v$archive_gap;
```
*Si la consulta devuelve 0 filas, la réplica Standby está completamente sincronizada sin retrasos.*

---

## 7. Procedimientos de Conmutación de Roles (Switchover y Failover)

### 7.1 Switchover (Conmutación Planificada de Roles)
Se utiliza para realizar mantenimientos preventivos en el servidor principal sin pérdida de transacciones.

1. **En la Primaria (Cambiar a Standby):**
   ```sql
   ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
   SHUTDOWN IMMEDIATE;
   STARTUP MOUNT;
   ```
2. **En la Standby (Promover a Primaria):**
   ```sql
   ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
   ALTER DATABASE OPEN;
   ```
3. **En la nueva Standby (Iniciar aplicación de redo):**
   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
   ```

---

### 7.2 Failover (Activación de Emergencia ante Desastre)
Se utiliza si el servidor principal sufre una catástrofe irreversible (falla de hardware mayor, pérdida de red total o daño físico).

1. **En el Servidor Standby (Detener recuperación y aplicar últimos logs):**
   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;
   ```
2. **Activar la Standby como Base de Datos Principal:**
   ```sql
   ALTER DATABASE ACTIVATE PHYSICAL STANDBY;
   ALTER DATABASE OPEN;
   ```
3. **Redirección de Clientes:**
   Actualizar la cadena de conexión TNS de las aplicaciones hacia la dirección IP del servidor Standby.

---

## 8. Guía Rápida para el Día de la Defensa

1. **Tener ambos servidores encendidos** con Oracle en ejecución.
2. **Demostración de Redo Logs a 50 MB y switch a 5 min:**
   ```sql
   SELECT group#, bytes/1024/1024, status FROM v$log;
   SHOW PARAMETER archive_lag_target;
   ```
3. **Demostración de Traslado Bajo Demanda:**
   Ejecutar el script PowerShell o Bash frente al profesor:
   ```powershell
   .\07_Standby_y_RMAN\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo OnDemand
   ```
4. **Demostración de Respaldo RMAN y Purga a 3 Días:**
   Ejecutar los scripts `.rman` y mostrar la salida de consola sin errores.
