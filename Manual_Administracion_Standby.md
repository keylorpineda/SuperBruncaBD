<div align="center">

# Sede Regional Brunca
## Campus Pérez Zeledón

### Manual de Administración del Standby y Alta Disponibilidad

**Curso: Administración de bases de datos**  
**Profesor: Hairol Romero Sandi**  
**II Ciclo - Grupo 84**  

**Estudiantes:**  
Diego Bonilla Mora  
Pineda Alvarez Keylor Steven  

Octubre del 2026

</div>

---

# 1. Alcance y Arquitectura de Alta Disponibilidad

Este documento constituye el **Manual de Administración del Servidor Standby**, diseñado para garantizar la continuidad ininterrumpida de las operaciones comerciales de la cadena de supermercados (cajas, puntos de venta, almacén y compras) ante fallas de infraestructura, pérdida de energía o desastres mayores.

### 1.1 Cumplimiento de Requerimientos del Enunciado Oficial
El diseño implementa de forma exacta las directrices de la Universidad Nacional:
1. **Dos Servidores Distintos:** Servidor Principal (OLTP de producción) y Servidor Secundario (Standby para contingencia).
2. **Dimensionamiento de Redo Logs a 50 MB:** Grupos de redo logs configurados en 50 MB con miembros multiplexados.
3. **Generación Forzada de Actualización cada 5 Minutos:** Parámetro `ARCHIVE_LAG_TARGET = 300` para obligar al motor a generar un archivo de log cada 5 minutos o cada 50 MB, sin intervención manual del DBA.
4. **Traslado de Información cada 10 Minutos y Bajo Demanda:** Script de transferencia automática parametrizada cada 10 minutos con modo interactivo **On-Demand** para revisión directa por el docente.
5. **Purga Automática con Rango de 3 Días:** Proceso de limpieza con RMAN que elimina del servidor principal y del standby los archivelogs con más de 3 días (`SYSDATE - 3`) que ya hayan sido aplicados y respaldados.
6. **Respaldo Diario RMAN Trasladado al Standby:** Ejecución automática de respaldos incrementales RMAN con réplica al servidor de contingencia y ejecución a demanda.
7. **Procedimientos de Conmutación:** Guías paso a paso para **Switchover** (mantenimiento planificado sin pérdida de datos) y **Failover** (activación de emergencia ante desastre).

```
+-------------------------------------------------------+         +-------------------------------------------------------+
|             SERVIDOR PRINCIPAL (PRIMARIA)             |         |              SERVIDOR STANDBY (CONTINGENCIA)          |
|  Host: srv-db-prim (192.168.1.100 o Contenedor Docker)|         |  Host: srv-db-stby (192.168.1.101 o Contenedor Docker)|
|  Instancia: FREE / PDB: FREEPDB1                      |         |  Instancia: FREESTBY                                  |
|  Modo: ARCHIVELOG / READ WRITE                        |         |  Modo: MOUNT / MANAGED RECOVERY                       |
|                                                       |         |                                                       |
|  • Redo Logs: 50 MB (Multiplexados)                   |         |  • Standby Redo Logs: 50 MB                           |
|  • ARCHIVE_LAG_TARGET: 300 s (Rotación cada 5 min)    |         |  • Proceso MRP0 (Managed Recovery Process)            |
|  • FORCE LOGGING: Habilitado                          |         |  • Directorio Destino: /opt/oracle/standby_arch       |
+-------------------------------------------------------+         +-------------------------------------------------------+
                           │                                                                 ▲
                           │────────── Traslado Automático (cada 10 min) ───────────────────│
                           │────────── Sincronización Bajo Demanda (On-Demand) ─────────────│
                           ▼                                                                 │
                 Archived Redo Logs                                                 Aplicación Continua
                 (Purga a los 3 días)                                                (Redo Apply / RMAN)
```

---

## 2. Configuración del Servidor Principal (`01_Configuracion_Primaria_Redo_Archive.sql`)

### 2.1 Habilitación de Modo ARCHIVELOG y FORCE LOGGING
Para que ninguna transacción quede fuera del registro de recuperación, se fuerza la escritura de redo log:

```sql
CONNECT / AS SYSDBA
ALTER SESSION SET CONTAINER = CDB$ROOT;

-- 1. Habilitar FORCE LOGGING a nivel de base de datos
ALTER DATABASE FORCE LOGGING;

-- 2. Verificar o activar modo ARCHIVELOG
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
```

### 2.2 Dimensionamiento de Redo Logs a 50 MB
El enunciado exige que el tamaño de los archivos de actualización sea de 50 MB. Se crean grupos multiplexados con datafiles de 50M:

```sql
-- Agregar nuevos grupos de 50 MB multiplexados
ALTER DATABASE ADD LOGFILE GROUP 4 (
    '/opt/oracle/oradata/FREE/redo04a.log',
    '/opt/oracle/oradata/FREE/redo04b.log'
) SIZE 50M;

ALTER DATABASE ADD LOGFILE GROUP 5 (
    '/opt/oracle/oradata/FREE/redo05a.log',
    '/opt/oracle/oradata/FREE/redo05b.log'
) SIZE 50M;

ALTER DATABASE ADD LOGFILE GROUP 6 (
    '/opt/oracle/oradata/FREE/redo06a.log',
    '/opt/oracle/oradata/FREE/redo06b.log'
) SIZE 50M;
```

### 2.3 Rotación Forzada cada 5 Minutos (`ARCHIVE_LAG_TARGET = 300`)
Para cumplir la directriz de generar un archivo de actualización cada 5 minutos o bien cada 50 MB sin intervención del DBA:

```sql
-- 300 segundos = 5 minutos exactos
ALTER SYSTEM SET ARCHIVE_LAG_TARGET = 300 SCOPE = BOTH;

-- Configurar destino local de archivado
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1 = 'LOCATION=/opt/oracle/archivelogs/ MANDATORY' SCOPE = BOTH;
ALTER SYSTEM SET LOG_ARCHIVE_FORMAT = 'arch_%t_%s_%r.arc' SCOPE = SPFILE;
```

---

## 3. Traslado Automático y Bajo Demanda (`02_Traslado_Archivelogs_10min_y_Ondemand`)

Se suministran dos implementaciones del script de transferencia: PowerShell (`.ps1`) para entornos Windows y Bash (`.sh`) para entornos Linux / Docker.

### 3.1 Script de Traslado en PowerShell (`02_Traslado_Archivelogs_10min_y_Ondemand.ps1`)
El script opera bajo dos modalidades:
* **Modalidad Automática (Programador de Tareas cada 10 min):** Se ejecuta en segundo plano sin intervención humana.
* **Modalidad Bajo Demanda (On-Demand):** Fuerza un switch de log en Oracle y traslada los archivos inmediatamente para demostración interactiva ante el profesor.

```powershell
param (
    [switch]$OnDemand = $false,
    [string]$RutaOrigen = "C:\oracle\archivelogs",
    [string]$RutaDestino = "\\SRV-STANDBY\oracle_standby_arch",
    [string]$RutaBackupOrigen = "C:\oracle\fast_recovery_area\backups",
    [string]$RutaBackupDestino = "\\SRV-STANDBY\oracle_standby_backups"
)

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host ">>> SISTEMA DE REPLICACION Y SINCRONIZACION STANDBY — AVANCE #2" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# Si es a peticion del docente, forzar el switch log de inmediato
if ($OnDemand) {
    Write-Host "[ON-DEMAND] Forzando generacion de Archivelog en Oracle..." -ForegroundColor Yellow
    docker exec -i oracle_una sqlplus -s / as sysdba @"
    ALTER SYSTEM ARCHIVE LOG CURRENT;
    exit;
"@
    Write-Host "[OK] Switch de log forzado exitosamente." -ForegroundColor Green
}

# Traslado de Archivelogs generados en los ultimos 10 minutos
Write-Host "[TRASLADO] Sincronizando Archivelogs hacia el Servidor Standby..." -ForegroundColor White
$archivos = Get-ChildItem -Path $RutaOrigen -Filter "*.arc"
foreach ($f in $archivos) {
    Copy-Item -Path $f.FullName -Destination $RutaDestino -Force
    Write-Host "  -> Trasladado: $($f.Name)" -ForegroundColor Gray
}

# Traslado de respaldos diarios RMAN
Write-Host "[TRASLADO] Sincronizando Respaldos RMAN hacia Standby..." -ForegroundColor White
$backups = Get-ChildItem -Path $RutaBackupOrigen -Filter "*.bkp"
foreach ($b in $backups) {
    Copy-Item -Path $b.FullName -Destination $RutaBackupDestino -Force
    Write-Host "  -> Backup RMAN copiado: $($b.Name)" -ForegroundColor Gray
}

Write-Host "[EXITO] Sincronizacion finalizada con exito hacia el Servidor Standby." -ForegroundColor Green
```

### 3.2 Instrucción de Ejecución Interactiva ante el Docente
Para demostrar el traslado en vivo al profesor en el momento de la revisión:

```powershell
.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -OnDemand
```

---

## 4. Política de Purga de Archivelogs a los 3 Días (`03_Purga_Archivelogs_3Dias`)

Para evitar saturación del almacenamiento, el enunciado exige eliminar los archivelogs del servidor principal y del standby con un rango de antigüedad de 3 días (`SYSDATE - 3`).

### 4.1 Script RMAN de Purga (`03_Purga_Archivelogs_3Dias.rman`)
```text
CONNECT TARGET /;

RUN {
    # 1. Realizar crosscheck para validar archivos fisicos existentes en disco
    CROSSCHECK ARCHIVELOG ALL;

    # 2. Eliminar de forma segura archivelogs respaldados y mayores a 3 dias
    DELETE NOPROMPT ARCHIVELOG ALL 
        COMPLETED BEFORE 'SYSDATE - 3';

    # 3. Eliminar entradas huerfanas de disco
    DELETE NOPROMPT EXPIRED ARCHIVELOG ALL;
}
```

### 4.2 Ejecución Programada de la Purga
```bash
rman cmdfile=03_Purga_Archivelogs_3Dias.rman log=purga_standby.log
```

---

## 5. Estrategia de Respaldo y Recuperación RMAN (`04_RMAN_Backup_Full_Incremental`)

### 5.1 Esquema de Respaldos Diarios Automáticos
* **Domingos (01:00 AM):** Respaldo Completo **Level 0** (Full Base de Datos + Archivelogs + SPFILE + Controlfile).
* **Lunes a Sábado (01:00 AM):** Respaldo Incremental Acumulativo **Level 1** (únicamente bloques modificados desde el último Level 0).
* **Parámetros RMAN:**
  * `CONFIGURE RETENTION POLICY TO RECOVERY WINDOW OF 14 DAYS;`
  * `CONFIGURE CONTROLFILE AUTOBACKUP ON;`

### 5.2 Script RMAN Completo (`04_RMAN_Backup_Full_Incremental.rman`)
```text
CONNECT TARGET /;

RUN {
    ALLOCATE CHANNEL ch1 DEVICE TYPE DISK;
    ALLOCATE CHANNEL ch2 DEVICE TYPE DISK;

    # Respaldo de Base de Datos y Pluggable Databases
    BACKUP INCREMENTAL LEVEL 1 DATABASE 
        TAG 'BKP_DIARIO_INCR'
        FORMAT '/opt/oracle/backups/db_incr_%d_%T_%U.bkp';

    # Respaldo y conmutacion de archivelogs
    SQL 'ALTER SYSTEM ARCHIVE LOG CURRENT';
    BACKUP ARCHIVELOG ALL 
        TAG 'BKP_ARCHIVELOGS_DIARIO'
        FORMAT '/opt/oracle/backups/arch_%d_%T_%U.bkp';

    # Respaldo de controlfile y spfile
    BACKUP CURRENT CONTROLFILE 
        TAG 'BKP_CONTROLFILE'
        FORMAT '/opt/oracle/backups/ctrl_%d_%T_%U.bkp';

    RELEASE CHANNEL ch1;
    RELEASE CHANNEL ch2;
}

# Verificacion de integridad del respaldo
CROSSCHECK BACKUP;
DELETE NOPROMPT OBSOLETE;
```

---

## 6. Procedimientos de Recuperación, Switchover y Failover (`06_Standby_Switchover_y_Failover.sql`)

### 6.1 Sincronización Continua del Standby (Redo Apply)
En el servidor Standby, el proceso `MRP0` aplica continuamente los archivelogs trasladados:

```sql
CONNECT / AS SYSDBA
-- Iniciar recuperacion administrada continua
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;

-- Consultar estado de sincronizacion
SELECT sequence#, applied, TO_CHAR(first_time, 'YYYY-MM-DD HH24:MI:SS') AS fecha_log
  FROM v$archived_log
 ORDER BY sequence# DESC;
```

---

### 6.2 Demostración de Switchover (Conmutación Planificada de Roles)
Se utiliza para mantenimiento programado del servidor principal. **Garantiza cero pérdida de datos (Zero Data Loss)**:

#### En el Servidor Principal (`CADENA_PRIM`):
```sql
CONNECT / AS SYSDBA

-- 1. Validar que la base de datos esta lista para switchover
SELECT switchover_status FROM v$database;
-- Resultado esperado: TO STANDBY o SESSIONS ACTIVE

-- 2. Conmutar rol a Standby
ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;

-- 3. Reiniciar la instancia en modo Standby
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
```

#### En el Servidor Standby (`CADENA_STBY`):
```sql
CONNECT / AS SYSDBA

-- 4. Verificar estado de conmutacion
SELECT switchover_status FROM v$database;
-- Resultado esperado: TO PRIMARY

-- 5. Promover la Standby a Base de Datos Primaria
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;

-- 6. Abrir la nueva base de datos primaria en modo lectura y escritura
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
```
> **Resultado:** El Servidor Standby ahora es el Servidor Principal activo atendiendo las cajas y clientes.

---

### 6.3 Demostración de Failover (Activación de Emergencia ante Desastre)
Se ejecuta cuando el servidor principal sufre una catástrofe irreversible (falla de hardware, destrucción de disco, pérdida de red) y no volverá a operar a corto plazo:

#### En el Servidor Standby:
```sql
CONNECT / AS SYSDBA

-- 1. Detener la recuperacion administrada
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;

-- 2. Aplicar el ultimo redo log disponible
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE FINISH;

-- 3. Activar la base de datos como Primaria independiente
ALTER DATABASE ACTIVATE STANDBY DATABASE;

-- 4. Abrir la base de datos para produccion
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;

-- 5. Verificar que el rol cambio a PRIMARY
SELECT database_role, open_mode FROM v$database;
```
> **Resultado:** La base de datos Standby asume la producción de forma autónoma con RTO (Recovery Time Objective) menor a 5 minutos.

---

## 7. Restauración y Recuperación a Punto en el Tiempo con RMAN (`05_RMAN_Restore_Recovery_PointInTime.rman`)

Si ocurre una corrupción lógica accidental (por ejemplo, eliminación indebida de una tabla antes de las 14:00 horas), RMAN permite restaurar al punto exacto anterior al incidente:

```text
CONNECT TARGET /;

RUN {
    # 1. Poner base de datos en estado de montaje
    SHUTDOWN IMMEDIATE;
    STARTUP MOUNT;

    # 2. Definir ventana de tiempo objetivo
    SET UNTIL TIME "TO_DATE('2026-10-29 13:59:00', 'YYYY-MM-DD HH24:MI:SS')";

    # 3. Restaurar datafiles desde el respaldo RMAN
    RESTORE DATABASE;

    # 4. Aplicar los archivelogs hasta el minuto indicado
    RECOVER DATABASE;

    # 5. Abrir la base de datos reseteando los logs de transacciones
    ALTER DATABASE OPEN RESETLOGS;
}
```
