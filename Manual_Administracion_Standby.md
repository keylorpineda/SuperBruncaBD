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

# 1. Qué es el Standby y por qué se usan dos computadoras

Una base de datos **Standby** es una copia de la base principal que se mantiene actualizada en **otra computadora**. Si la computadora principal se daña, se apaga o se pierde, la standby se "activa" y pasa a ser la nueva base de producción con casi todos los datos.

Para eso hacen falta dos máquinas distintas (lo exige el enunciado): si la copia estuviera en la misma computadora, una falla de disco o de energía se llevaría las dos.

| Computadora | Rol | Qué corre ahí |
| :--- | :--- | :--- |
| **PC 1 – Principal** | Base `CADENA` abierta en `READ WRITE`. Aquí trabajan las cajas, compras e inventario. | Todo el sistema (scripts `00`–`06`), el paquete `PKG_ADM_STANDBY` y los **jobs DBMS_SCHEDULER** que generan, respaldan, trasladan y purgan. |
| **PC 2 – Standby** | Base `CADENA_STBY` en estado `MOUNT` (no se usa para trabajar). | Recibe los archivelogs y respaldos en carpetas compartidas y los aplica (tareas programadas de Windows o cron). |

### 1.1 Cómo viaja la información

```
 PC 1 - PRINCIPAL                                         PC 2 - STANDBY
 +-----------------------------------+                   +-----------------------------------+
 | Redo log 50 MB / cambio cada 5 min |                   | Base montada (MOUNT)              |
 |   (ARCHIVE_LAG_TARGET = 300)       |                   |                                   |
 |            |                       |   cada 10 min     |  \\PC-STANDBY\standby_archive     |
 |   Archived redo logs  -------------+------------------>|        |                          |
 |            |                       |  JOB_STANDBY_     |        v                          |
 |   RMAN diario 01:00   -------------+--TRASLADO_------->|  \\PC-STANDBY\standby_backups     |
 |   (JOB_RMAN_BACKUP_DIARIO)         |  ARCHIVELOG       |        |                          |
 |            |                       |                   |  09_Aplicar_Archivelogs_Standby   |
 |   Purga > 3 dias aplicados         |                   |  (sincronizacion cada 10 min)     |
 |   (JOB_STANDBY_PURGA_ARCHIVELOG)   |                   |  Purga > 3 dias aplicados         |
 +-----------------------------------+                   +-----------------------------------+
```

1. Cada transacción queda escrita en el **redo log**. Cuando se llena (50 MB) o pasan 5 minutos, Oracle lo cierra y crea un **archivelog**.
2. Cada 10 minutos el job `JOB_STANDBY_TRASLADO_ARCHIVELOG` copia los archivelogs nuevos (y los respaldos RMAN) a las carpetas compartidas de la PC 2.
3. En la PC 2 una tarea programada aplica esos archivelogs a la base standby, que queda igual que la principal.
4. Todos los días se respalda la principal con RMAN y el respaldo también se copia a la PC 2.
5. Los archivelogs con más de 3 días que ya se aplicaron en la standby se borran en las dos computadoras.

### 1.2 Dos formas de funcionamiento

| Modo | Edición de Oracle | Cómo llega y se aplica el redo |
| :--- | :--- | :--- |
| **Manual** (el que se demuestra) | XE, Free o Standard | Copia de archivos cada 10 min + aplicación con RMAN (`09_Aplicar_Archivelogs_Standby.rman`). |
| **Data Guard** (opcional) | Enterprise | Además, `LOG_ARCHIVE_DEST_2` envía el redo por red y el proceso `MRP0` lo aplica solo. |

El modo manual cumple todos los puntos del enunciado y funciona con cualquier edición; Data Guard es un complemento.

### 1.3 Cumplimiento del enunciado

| Requerimiento | Solución | Archivo |
| :--- | :--- | :--- |
| Dos servidores distintos | PC 1 principal y PC 2 standby | Sección 2 y 4 |
| Archivo de actualización cada 5 min o 50 MB (parametrizado) | Redo logs de 50 MB y `ARCHIVE_LAG_TARGET = 300`; valores en `STANDBY_SWITCH_MIN` y `STANDBY_SWITCH_MB` | `01_Configuracion_Primaria_Redo_Archive.sql` |
| Traslado cada 10 min (parametrizado) y bajo demanda | `JOB_STANDBY_TRASLADO_ARCHIVELOG` con `STANDBY_SYNC_MIN`; `PR_SINCRONIZAR_AHORA` | `07_Paquete_Jobs_Standby_RMAN.sql`, `02_Traslado_...ps1/.sh` |
| Eliminar lo trasladado y lo aplicado con rango de 3 días (parametrizado) | `JOB_STANDBY_PURGA_ARCHIVELOG` y tarea `CADENA_Standby_Purga`; `STANDBY_PURGE_DIAS` | `03_Purga_Archivelogs_3Dias.rman`, `03_Purga_Archivelogs_Standby.rman` |
| Respaldo diario automático, trasladado al standby y a petición | `JOB_RMAN_BACKUP_DIARIO`; `PR_RESPALDAR_AHORA` | `04_RMAN_Backup_Full_Incremental.rman` |
| Backup full, incremental, restore y recovery | Nivel 0 los domingos, nivel 1 el resto; restauración completa y a un punto en el tiempo | `04_...rman`, `05_RMAN_Restore_Recovery_PointInTime.rman` |
| Failover, switchover, recuperación y sincronización | Procedimientos para modo manual y Data Guard | `06_Standby_Switchover_y_Failover.sql` |
| Replicar todas las acciones y manual ante inconvenientes | `FORCE LOGGING`, `STANDBY_FILE_MANAGEMENT=AUTO` y guía de incidentes | Sección 10 |
| Procesos automáticos con DBMS_SCHEDULER | 4 jobs administrados por `PKG_ADM_STANDBY` | Sección 5 |

---

# 2. Preparación de las dos computadoras

1. **Misma versión de Oracle** (21c o 23ai/26ai Free) en las dos PC y, de preferencia, **las mismas rutas** de instalación (por ejemplo `C:\app\oracle`). Así no hace falta convertir nombres de archivos.
2. **Red**: las dos PC en la misma red y con IP fija. Pruebe con `ping` desde la principal hacia la standby.
3. **Carpetas compartidas en la PC 2** (clic derecho → Propiedades → Compartir), con permiso de escritura para el usuario de Windows de la PC 1:
   * `C:\app\oracle\standby_archive` → compartida como `standby_archive`
   * `C:\app\oracle\standby_backups` → compartida como `standby_backups`
4. **Usuario del sistema operativo** en la PC 1 para los jobs: debe pertenecer al grupo `ORA_DBA` (en Linux, al grupo `dba`) y poder escribir en las carpetas compartidas.
5. **Servicio de jobs externos** (solo Windows, PC 1): en `services.msc` iniciar `OracleJobScheduler<SID>` y dejarlo en automático.
6. **Linux**: en lugar de carpetas compartidas se usa `rsync` por SSH con llave pública (`ssh-copy-id oracle@pc-standby`) y el destino `oracle@pc-standby:/opt/oracle/standby_archive`.

> Recomendación: use rutas **sin espacios** en todos los parámetros; los jobs externos de Windows separan los argumentos por espacios.

---

# 3. Configuración de la principal (`01_Configuracion_Primaria_Redo_Archive.sql`)

Se ejecuta una vez en la PC 1, conectado como `SYSDBA` en `CDB$ROOT`. La base debe estar en modo `ARCHIVELOG`:

```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
@07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
```

Lo que configura el script:

| Configuración | Para qué sirve |
| :--- | :--- |
| Grupos de redo 4, 5 y 6 de **50 MB** (con segundo miembro multiplexado) | Cada 50 MB de cambios se genera un archivelog. |
| `ARCHIVE_LAG_TARGET = 300` | Si en 5 minutos no se llenaron los 50 MB, Oracle cambia de log igual. Nadie tiene que intervenir. |
| `FORCE LOGGING` | Ninguna operación (ni las `NOLOGGING`) se salta el redo; así todo se replica. |
| `LOG_ARCHIVE_DEST_1` en la Fast Recovery Area | Dónde quedan los archivelogs en la PC 1. |
| `LOG_ARCHIVE_DEST_2`, `LOG_ARCHIVE_CONFIG`, `FAL_SERVER` | Solo para Data Guard. En **modo manual** se difiere: `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = DEFER SCOPE = BOTH;` |
| `STANDBY_FILE_MANAGEMENT = AUTO` | Si se agrega un datafile en la principal, se crea solo en la standby. |
| Standby redo logs (grupos 11–14, 50 MB) | Necesarios para recibir redo y para cambiar de rol en un switchover. |

---

# 4. Creación de la base standby en la PC 2

Se hace **una sola vez**. El respaldo que necesita la PC 2 ya lo genera y traslada el sistema.

**En la PC 1 (principal):**

```sql
-- 1. Generar el respaldo (incluye un controlfile especial para standby) y copiarlo a la PC 2
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;

-- 2. Obtener el archivo de parámetros como plantilla
CREATE PFILE = 'C:\temp\initCADENA_STBY.ora' FROM SPFILE;
```

3. Copiar a la PC 2 el archivo de claves de Oracle: `%ORACLE_HOME%\database\PWD<SID>.ora` (Linux: `$ORACLE_HOME/dbs/orapw<SID>`), al mismo lugar.

**En la PC 2 (standby):**

4. Copiar `initCADENA_STBY.ora` y cambiar `db_unique_name='CADENA_STBY'` y `standby_file_management='AUTO'`. La plantilla `08_init_CADENA_STBY.ora` muestra los valores mínimos.
5. Crear la instancia (solo Windows) e iniciarla sin montar:

```bat
oradim -NEW -SID FREE -STARTMODE manual
set ORACLE_SID=FREE
sqlplus / as sysdba
SQL> STARTUP NOMOUNT PFILE='C:\app\oracle\proyecto\07_Standby_y_RMAN\08_init_CADENA_STBY.ora';
SQL> CREATE SPFILE FROM PFILE='C:\app\oracle\proyecto\07_Standby_y_RMAN\08_init_CADENA_STBY.ora';
```

6. Crear la standby con el orquestador: busca el controlfile de standby más reciente, lo restaura, monta la base, restaura los datafiles y aplica todo el redo disponible (`08_Creacion_Standby_Segunda_PC.rman`):

```powershell
cd C:\app\oracle\proyecto\07_Standby_y_RMAN
.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo CrearStandby -RutaBackupsStandby C:\app\oracle\standby_backups
```

7. Programar la sincronización y la purga en la PC 2 (Programador de tareas de Windows):

```powershell
.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo RegistrarTareasStandby -RutaDestinoStandby C:\app\oracle\standby_archive -IntervaloMin 10 -DiasRetencion 3
```

Crea dos tareas: `CADENA_Standby_Aplicar` (cada 10 minutos) y `CADENA_Standby_Purga` (diaria, 03:30). En Linux se agregan las líneas equivalentes al `crontab` (están en el encabezado del `.sh`).

> **¿Por qué en la PC 2 no se usa DBMS_SCHEDULER?** Una base standby está en `MOUNT`; en ese estado Oracle no ejecuta jobs del Scheduler. Por eso la PC 2 usa el programador del sistema operativo, y **todos** los jobs de la PC 1 sí son DBMS_SCHEDULER.

---

# 5. Automatización con DBMS_SCHEDULER (`07_Paquete_Jobs_Standby_RMAN.sql`)

El instalador maestro ejecuta este script como paso 7. Crea el paquete `CADENA_NEG.PKG_ADM_STANDBY` y cuatro jobs que leen sus valores de `SEG_PARAMETRO`.

### 5.1 Parámetros (tabla `SEG_PARAMETRO`, módulo `STANDBY`)

| Código | Valor por defecto | Uso |
| :--- | :--- | :--- |
| `STANDBY_SWITCH_MIN` / `STANDBY_SWITCH_MB` | 5 / 50 | Cambio de log cada 5 min o 50 MB. |
| `STANDBY_SYNC_MIN` | 10 | Minutos entre traslados. |
| `STANDBY_PURGE_DIAS` | 3 | Días de retención de archivelogs. |
| `STANDBY_HORA_BACKUP` / `STANDBY_HORA_PURGA` | 1 / 3 | Hora del respaldo diario y de la purga. |
| `STANDBY_MAX_LAG_MIN` | 30 | Minutos sin traslado exitoso antes de avisar al DBA. |
| `STANDBY_RUTA_ARCHIVE_ORIGEN` | Detectada de la FRA | Archivelogs en la PC 1. |
| `STANDBY_RUTA_ARCHIVE_DESTINO` | `\\PC-STANDBY\standby_archive` | Carpeta compartida de la PC 2. |
| `STANDBY_RUTA_BACKUP_ORIGEN` | `C:\app\oracle\backups` | Respaldos RMAN en la PC 1. |
| `STANDBY_RUTA_BACKUP_DESTINO` | `\\PC-STANDBY\standby_backups` | Respaldos en la PC 2. |
| `STANDBY_RUTA_SCRIPTS` | `C:\app\oracle\proyecto\07_Standby_y_RMAN` | Ubicación del orquestador y los `.rman`. |
| `STANDBY_SO`, `STANDBY_ORACLE_SID`, `STANDBY_ORACLE_HOME` | Detectados | Entorno que reciben los jobs externos. |

Para cambiar un valor (por ejemplo, la IP real de la PC 2) y aplicarlo en caliente:

```sql
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_ARCHIVE_DESTINO', 'STANDBY', 'Carpeta de archivelogs en la PC standby', 'Carpeta compartida de la segunda PC', 'N', '\\192.168.1.20\standby_archive');
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS;
```

### 5.2 Jobs

| Job | Tipo | Frecuencia | Acción |
| :--- | :--- | :--- | :--- |
| `JOB_STANDBY_TRASLADO_ARCHIVELOG` | EXECUTABLE | Cada `STANDBY_SYNC_MIN` min | Cierra el redo actual y copia archivelogs y respaldos nuevos a la PC 2. |
| `JOB_RMAN_BACKUP_DIARIO` | EXECUTABLE | Diario, `STANDBY_HORA_BACKUP` | RMAN nivel 0 (domingo) o nivel 1, controlfile de standby y copia a la PC 2. |
| `JOB_STANDBY_PURGA_ARCHIVELOG` | EXECUTABLE | Diario, `STANDBY_HORA_PURGA` | Borra archivelogs > `STANDBY_PURGE_DIAS` ya aplicados y respaldados. |
| `JOB_STANDBY_MONITOREO` | PLSQL_BLOCK | Cada hora | `PR_VERIFICAR_SINCRONIZACION`: registra en `AUD_MONITOREO_BD` y envía correo al DBA si hay atraso o fallos. |

Los tres primeros ejecutan `02_Traslado_Archivelogs_10min_y_Ondemand.ps1` (Windows) o `.sh` (Linux) y le pasan los parámetros como argumentos.

### 5.3 Credencial del sistema operativo (una vez)

Los jobs `EXECUTABLE` corren en Windows/Linux con un usuario real. Oracle guarda la clave cifrada en su diccionario (`DBMS_CREDENTIAL`):

```sql
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('usuario_windows', 'clave_windows');
```

Hasta que se registra, los jobs quedan creados pero **deshabilitados** (el script lo indica como `[PENDIENTE]`).

### 5.4 Ejecución a petición del académico

```sql
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;   -- traslado inmediato
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;     -- respaldo RMAN + traslado
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;        -- purga inmediata
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;      -- estado de jobs y última sincronización
```

Cada procedimiento ejecuta el job en la sesión y muestra el resultado y la salida del script. Todo queda en `AUD_BITACORA` y los errores en `AUD_ERROR_SISTEMA`.

---

# 6. Orquestador de traslado (`02_Traslado_Archivelogs_10min_y_Ondemand.ps1` / `.sh`)

| Modo | Dónde | Qué hace |
| :--- | :--- | :--- |
| `Archivelogs` / `OnDemand` | PC 1 | `ALTER SYSTEM ARCHIVE LOG CURRENT` y copia incremental (solo archivos nuevos) de archivelogs y respaldos `.bkp`. |
| `Backup` | PC 1 | RMAN con `04_RMAN_Backup_Full_Incremental.rman` y copia del respaldo a la PC 2. |
| `Purga` | PC 1 | RMAN con `03_Purga_Archivelogs_3Dias.rman`. |
| `Continuo` | PC 1 | Alternativa sin Scheduler: traslado cada `-IntervaloMin` minutos. |
| `CrearStandby` | PC 2 | Crea la base standby (sección 4). |
| `AplicarStandby` | PC 2 | Sincroniza: aplica los archivelogs recibidos. |
| `PurgaStandby` | PC 2 | Purga los ya aplicados con más de N días. |
| `RegistrarTareasStandby` | PC 2 | Programa `AplicarStandby` y `PurgaStandby` en Windows. |

Si algo falla, el script termina con código 1; así DBMS_SCHEDULER marca el job como `FAILED` y el monitoreo avisa al DBA. La bitácora queda en `C:\app\oracle\logs\standby_orquestador.log` y una bitácora RMAN por ejecución.

---

# 7. Purga de archivelogs a los 3 días

| Lado | Script | Regla |
| :--- | :--- | :--- |
| PC 1 | `03_Purga_Archivelogs_3Dias.rman` (job diario) | `ARCHIVELOG DELETION POLICY TO APPLIED ON ALL STANDBY BACKED UP 1 TIMES` y `DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-&1'`. |
| PC 2 | `03_Purga_Archivelogs_Standby.rman` (tarea diaria) | `CATALOG` de la carpeta recibida, política `APPLIED ON ALL STANDBY` y borrado de lo aplicado con más de `&1` días. |

`&1` es el valor de `STANDBY_PURGE_DIAS`. RMAN no borra un archivelog que no cumpla la política: muestra `RMAN-08120` y lo conserva. Así nunca se pierde redo que la standby todavía necesita.

---

# 8. Respaldo y recuperación con RMAN

### 8.1 Estrategia (`04_RMAN_Backup_Full_Incremental.rman`)

* **Domingo:** nivel 0 (full) de toda la base.
* **Lunes a sábado:** nivel 1 (incremental, solo bloques cambiados).
* Cada día además: archivelogs no respaldados, controlfile, **controlfile de standby** y autobackup del controlfile.
* Retención: ventana de recuperación de 14 días (`DELETE OBSOLETE`), `CROSSCHECK` y `RESTORE VALIDATE` para comprobar que el respaldo sirve.

Ejecución manual: `rman target / cmdfile=04_RMAN_Backup_Full_Incremental.rman using 'C:/app/oracle/backups' 0` (`&1` = carpeta, `&2` = nivel).

### 8.2 Restauración y recuperación (`05_RMAN_Restore_Recovery_PointInTime.rman`)

| Escenario | Comandos clave |
| :--- | :--- |
| Pérdida de datafiles (recuperación completa) | `STARTUP MOUNT; RESTORE DATABASE; RECOVER DATABASE; ALTER DATABASE OPEN;` |
| Error lógico (por ejemplo, se borró una tabla a las 14:00) | `SET UNTIL TIME "TO_DATE('2026-10-29 13:59:00','YYYY-MM-DD HH24:MI:SS')"; RESTORE DATABASE; RECOVER DATABASE; ALTER DATABASE OPEN RESETLOGS;` |
| Daño en un datafile o PDB | `RESTORE PLUGGABLE DATABASE FREEPDB1; RECOVER PLUGGABLE DATABASE FREEPDB1;` |

Como los respaldos también están en la PC 2, se pueden restaurar allí si la PC 1 se pierde por completo.

---

# 9. Sincronización, switchover, failover y monitoreo (`06_Standby_Switchover_y_Failover.sql`)

### 9.1 Verificar la sincronización

```sql
-- PC 1: última secuencia generada
SELECT MAX(sequence#) FROM v$archived_log WHERE dest_id = 1;
-- PC 2: última secuencia aplicada (deben coincidir después de AplicarStandby)
SELECT MAX(sequence#) FROM v$archived_log WHERE applied = 'YES';
SELECT database_role, open_mode FROM v$database;   -- PHYSICAL STANDBY / MOUNTED
```

Desde la PC 1, `PR_ESTADO_STANDBY` muestra los jobs, sus últimas ejecuciones y las últimas verificaciones de `AUD_MONITOREO_BD`.

### 9.2 Switchover (cambio planificado, sin pérdida)

**Modo manual:**
1. PC 1: `ALTER SYSTEM ARCHIVE LOG CURRENT;`, `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;` y `SHUTDOWN IMMEDIATE;`
2. PC 2: `-Modo AplicarStandby`, luego `ALTER DATABASE ACTIVATE STANDBY DATABASE; ALTER DATABASE OPEN; ALTER PLUGGABLE DATABASE ALL OPEN;`
3. La antigua principal se recrea como standby con un respaldo de la nueva (sección 4 en sentido inverso).

**Data Guard:** `ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;` en la principal y `ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY;` en la standby (pasos completos en el script).

### 9.3 Failover (la principal se perdió)

En la PC 2: aplicar lo último recibido (`-Modo AplicarStandby`) y `ALTER DATABASE ACTIVATE STANDBY DATABASE; ALTER DATABASE OPEN; ALTER PLUGGABLE DATABASE ALL OPEN;`. Luego se cambia la conexión de la aplicación a la IP de la PC 2. La pérdida máxima es lo generado después del último traslado (como máximo `STANDBY_SYNC_MIN` minutos).

Con Data Guard: `RECOVER MANAGED STANDBY DATABASE CANCEL`, `... FINISH` y `ACTIVATE STANDBY DATABASE`.

---

# 10. Acciones que pueden no replicarse y cómo actuar

El enunciado pide replicar todas las acciones de la principal. Estas son las que pueden causar problemas y su solución:

| Situación | Síntoma | Solución |
| :--- | :--- | :--- |
| Operación `NOLOGGING` o carga directa | Bloques corruptos en la standby (`ORA-01578`) | Prevenido con `FORCE LOGGING`. Si se desactivó, volver a activarlo y respaldar/restaurar el datafile afectado en la standby. |
| Se agrega un datafile o tablespace | `ORA-01111` / `ORA-01157` al aplicar | Prevenido con `STANDBY_FILE_MANAGEMENT=AUTO`. Si falla: en la standby `ALTER DATABASE CREATE DATAFILE '<UNNAMED>' AS '<ruta>';` y volver a aplicar. |
| Archivos externos (`padron_muestra.csv`, directorio `DIR_PADRON`, respaldos) | El padrón no está en la PC 2 al activarla | Son archivos del sistema operativo, no viajan en el redo: copiar el CSV a la misma ruta en la PC 2. |
| Cambio de claves de usuarios SYS o del archivo de claves | Fallan conexiones `SYSDBA` remotas | Volver a copiar `PWD<SID>.ora` a la PC 2. |
| Falta un archivelog (hueco) | `RMAN-06054` pidiendo una secuencia vieja que no llega | `PR_SINCRONIZAR_AHORA` en la PC 1; si el archivo ya no existe, respaldo incremental desde el SCN de la standby (`BACKUP INCREMENTAL FROM SCN <scn> DATABASE`) y `RECOVER` en la PC 2. |
| Carpeta compartida inaccesible (PC 2 apagada, red) | Job `FAILED`; correo "inconsistencia en la sincronización" | Revisar red/permisos y ejecutar `PR_SINCRONIZAR_AHORA`: la copia es incremental y se pone al día sola. |
| Disco lleno en la Fast Recovery Area | `ORA-19809` / la base se detiene | `PR_PURGAR_AHORA`; si sigue lleno, aumentar `DB_RECOVERY_FILE_DEST_SIZE`. |
| Nueva PDB creada en la principal | La PDB no se abre en la standby | Respaldar la PDB y restaurarla en la standby, o recrear la standby (sección 4). |

---

# 11. Guion para la demostración

1. **PC 1:** `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;` – jobs habilitados y última sincronización.
2. **PC 1:** insertar una factura de prueba y `COMMIT`.
3. **PC 1:** `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;` – se ve el archivelog copiado.
4. **PC 2:** `.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo AplicarStandby` y comparar secuencias (sección 9.1).
5. **PC 1:** `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;` – respaldo y copia a la PC 2.
6. **PC 1:** `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;`
7. **PC 2:** failover (sección 9.3) y consultar la factura de prueba en la base activada.
