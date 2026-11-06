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
| **PC 2 – Standby** | Base `CADENA_STBY` en `MOUNT`, o en `READ ONLY WITH APPLY` para consultas (no se usa para trabajar). | Con Data Guard recibe el redo por la red y lo aplica sola (proceso `MRP0`). En modo manual recibe los archivelogs y respaldos en carpetas y los aplica con tareas programadas. |

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
| **Data Guard** (recomendado y probado) | **21c Enterprise Edition** | `LOG_ARCHIVE_DEST_2` envía el redo por la red apenas se genera y el proceso `MRP0` lo aplica solo en la standby. Switchover y failover con un solo comando. |
| **Manual** (respaldo) | XE, Free o Standard | Copia de archivos cada 10 min + aplicación con RMAN (`09_Aplicar_Archivelogs_Standby.rman`). |

El proyecto usa **Oracle 21c Enterprise Edition con Data Guard**: es la versión que pide el enunciado y el modo que se verificó de punta a punta (sección 11). Las secciones 4, 6 y 9 describen también el **modo manual**, que queda como respaldo por si hay que usar una edición sin Data Guard (XE, Free). El diagrama de la sección 1.1 corresponde al modo manual; con Data Guard el redo viaja por Oracle Net en lugar de copiarse en carpetas, y los respaldos RMAN se trasladan igual.

### 1.3 Cumplimiento del enunciado

Todos los archivos de esta tabla están en la carpeta `sql/07_Standby_y_RMAN/` del repositorio.

| Requerimiento | Solución | Archivo |
| :--- | :--- | :--- |
| Dos servidores distintos | PC 1 principal (`CADENA`) y PC 2 standby (`CADENA_STBY`) | Secciones 2, 4 y 11 |
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

1. **Misma versión de Oracle** (21c Enterprise Edition) en las dos PC y, de preferencia, **las mismas rutas** de instalación (en Docker `/opt/oracle`, en Windows por ejemplo `C:\app\oracle`). Así no hace falta convertir nombres de archivos. Con Docker se usan los contenedores `ora_principal` y `ora_standby` (sección 11).
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

Se ejecuta una vez en la PC 1, conectado como `SYSDBA` en `CDB$ROOT` (con SQL\*Plus abierto desde la carpeta `sql` del repositorio). La base debe estar en modo `ARCHIVELOG`:

```sql
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
@07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
```

En Docker la base ya está en `ARCHIVELOG` (`ENABLE_ARCHIVELOG=true`) y el script se corre **dos veces** (la segunda borra los grupos de redo viejos de 200 MB): `docker exec -i -u oracle -w /opt/oracle/proyecto/sql/07_Standby_y_RMAN ora_principal sqlplus -s / as sysdba '@01_Configuracion_Primaria_Redo_Archive.sql'`.

Lo que configura el script:

| Configuración | Para qué sirve |
| :--- | :--- |
| Grupos de redo 4, 5 y 6 de **50 MB** (con segundo miembro multiplexado) | Cada 50 MB de cambios se genera un archivelog. |
| `ARCHIVE_LAG_TARGET = 300` | Si en 5 minutos no se llenaron los 50 MB, Oracle cambia de log igual. Nadie tiene que intervenir. |
| `FORCE LOGGING` | Ninguna operación (ni las `NOLOGGING`) se salta el redo; así todo se replica. |
| `LOG_ARCHIVE_DEST_1` en la Fast Recovery Area | Dónde quedan los archivelogs en la PC 1. La imagen Docker de 21c EE no tiene FRA: se conserva su destino `/opt/oracle/oradata/CADENA/archive_logs`. |
| `LOG_ARCHIVE_DEST_2`, `LOG_ARCHIVE_CONFIG`, `FAL_SERVER` | Solo en Enterprise (Data Guard): `SERVICE=STANDBY_TNS ASYNC ... DB_UNIQUE_NAME=CADENA_STBY` y `DG_CONFIG=(CADENA,CADENA_STBY)`. En **modo manual** el script deja `LOG_ARCHIVE_DEST_2` vacío; si existiera, RMAN nunca purgaría (`RMAN-08120 not yet applied by standby`). |
| `CONTROL_FILE_RECORD_KEEP_TIME = 21` | El controlfile recuerda los respaldos más que la ventana de 14 días de RMAN. |
| `STANDBY_FILE_MANAGEMENT = AUTO` | Si se agrega un datafile en la principal, se crea solo en la standby. |
| Standby redo logs (grupos 11–14, 50 MB) | Necesarios para recibir redo y para cambiar de rol en un switchover. |

---

# 4. Creación de la base standby en la PC 2

Se hace **una sola vez**. El respaldo que necesita la PC 2 ya lo genera y traslada el sistema.

> Esta sección describe la creación genérica (ejemplo en Windows, válida también para el modo manual). Con **Oracle 21c EE y Data Guard en Linux/Docker**, el procedimiento verificado, con rutas y comandos exactos, es el de la **sección 11**.

**En la PC 1 (principal):**

```sql
-- 1. Generar el respaldo (incluye un controlfile especial para standby) y copiarlo a la PC 2
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;

-- 2. Obtener el archivo de parámetros como plantilla
CREATE PFILE = 'C:\temp\initCADENA_STBY.ora' FROM SPFILE;
```

3. Copiar a la PC 2 el archivo de claves de Oracle: `%ORACLE_HOME%\database\PWD<SID>.ora` (Linux: `$ORACLE_HOME/dbs/orapw<SID>`; en la imagen Docker de 21c EE: `/opt/oracle/oradata/dbconfig/CADENA/orapwCADENA`), al mismo lugar.

**En la PC 2 (standby):**

4. Copiar `initCADENA_STBY.ora`, borrar las líneas `CADENA.__*` y cambiar `db_unique_name='CADENA_STBY'` y `standby_file_management='AUTO'`. La plantilla `08_init_CADENA_STBY.ora` muestra los valores (rutas de Linux/Docker; las rutas típicas de Windows están comentadas al final del archivo).
5. Crear la instancia (solo Windows) e iniciarla sin montar:

```bat
oradim -NEW -SID CADENA -STARTMODE manual
set ORACLE_SID=CADENA
sqlplus / as sysdba
SQL> STARTUP NOMOUNT PFILE='C:\temp\initCADENA_STBY.ora';
SQL> CREATE SPFILE FROM PFILE='C:\temp\initCADENA_STBY.ora';
```

6. Crear la standby con el orquestador: busca el controlfile de standby más reciente, lo restaura, monta la base, restaura los datafiles y aplica todo el redo disponible (`08_Creacion_Standby_Segunda_PC.rman`):

```powershell
cd C:\app\oracle\proyecto\sql\07_Standby_y_RMAN
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
| `STANDBY_RUTA_SCRIPTS` | `C:\app\oracle\proyecto\sql\07_Standby_y_RMAN` (Linux: `/opt/oracle/proyecto/sql/07_Standby_y_RMAN`) | Ubicación del orquestador y los `.rman`. |
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

`&1` es el valor de `STANDBY_PURGE_DIAS`. RMAN no borra un archivelog que no cumpla la política: muestra `RMAN-08120` y lo conserva. En modo manual RMAN avisa `RMAN-08591` (no hay destino standby registrado) y exige solo el respaldo; que el archivo ya llegó a la PC 2 lo garantiza el traslado cada 10 minutos, vigilado por `JOB_STANDBY_MONITOREO`.

> Verificado en Oracle 26ai Free (Docker, modo manual): con 86 archivelogs, la purga eliminó los 41 que tenían más de 3 días y ya estaban respaldados.
>
> Verificado en Oracle 21c EE con Data Guard (con 0 días, de prueba): la purga borró solo los archivelogs aplicados en la standby **y** respaldados; avisó `RMAN-08120` (aún no aplicado) y `RMAN-08138` (falta respaldo) y conservó esos archivos.

---

# 8. Respaldo y recuperación con RMAN

### 8.1 Estrategia (`04_RMAN_Backup_Full_Incremental.rman`)

* **Domingo:** nivel 0 (full) de toda la base.
* **Lunes a sábado:** nivel 1 (incremental, solo bloques cambiados).
* Cada día además: archivelogs no respaldados, controlfile, **controlfile de standby** y autobackup del controlfile.
* Retención: ventana de recuperación de 14 días (`DELETE OBSOLETE`), `CROSSCHECK` y `RESTORE VALIDATE` para comprobar que el respaldo sirve.

Ejecución manual (desde `sql/07_Standby_y_RMAN`): `rman target / cmdfile=04_RMAN_Backup_Full_Incremental.rman using 'C:/app/oracle/backups' 0` (`&1` = carpeta, `&2` = nivel).

### 8.2 Restauración y recuperación (`05_RMAN_Restore_Recovery_PointInTime.rman`)

| Escenario | Comandos clave |
| :--- | :--- |
| Pérdida de datafiles (recuperación completa) | `STARTUP MOUNT; RESTORE DATABASE; RECOVER DATABASE; ALTER DATABASE OPEN;` |
| Error lógico (por ejemplo, se borró una tabla a las 14:00) | `SET UNTIL TIME "TO_DATE('2026-10-29 13:59:00','YYYY-MM-DD HH24:MI:SS')"; RESTORE DATABASE; RECOVER DATABASE; ALTER DATABASE OPEN RESETLOGS;` |
| Daño en un datafile o PDB | `RESTORE PLUGGABLE DATABASE PDBCADENA; RECOVER PLUGGABLE DATABASE PDBCADENA;` |

Como los respaldos también están en la PC 2, se pueden restaurar allí si la PC 1 se pierde por completo.

---

# 9. Sincronización, switchover, failover y monitoreo (`06_Standby_Switchover_y_Failover.sql`)

### 9.1 Verificar la sincronización

Con Data Guard se usan `V$ARCHIVE_DEST_STATUS` y `V$DATAGUARD_STATS` (sección 11.8). En modo manual se comparan secuencias:

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

**Data Guard (verificado):** en la principal `ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;` y `ALTER DATABASE SWITCHOVER TO CADENA_STBY;` (pasos completos en la sección 11.10). La sintaxis antigua `COMMIT TO SWITCHOVER` sigue en `06_Standby_Switchover_y_Failover.sql` como alternativa.

### 9.3 Failover (la principal se perdió)

En la PC 2: aplicar lo último recibido (`-Modo AplicarStandby`) y `ALTER DATABASE ACTIVATE STANDBY DATABASE; ALTER DATABASE OPEN; ALTER PLUGGABLE DATABASE ALL OPEN;`. Luego se cambia la conexión de la aplicación a la IP de la PC 2. La pérdida máxima es lo generado después del último traslado (como máximo `STANDBY_SYNC_MIN` minutos).

**Data Guard (verificado):** en la standby `ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;`, `ALTER DATABASE FAILOVER TO CADENA_STBY;`, `ALTER DATABASE OPEN;` y `ALTER PLUGGABLE DATABASE ALL OPEN;`. Con la aplicación en tiempo real no se pierde nada de lo confirmado (sección 11.11).

---

# 10. Acciones que pueden no replicarse y cómo actuar

El enunciado pide replicar todas las acciones de la principal. Estas son las que pueden causar problemas y su solución:

| Situación | Síntoma | Solución |
| :--- | :--- | :--- |
| Operación `NOLOGGING` o carga directa | Bloques corruptos en la standby (`ORA-01578`) | Prevenido con `FORCE LOGGING`. Si se desactivó, volver a activarlo y respaldar/restaurar el datafile afectado en la standby. |
| Se agrega un datafile o tablespace | `ORA-01111` / `ORA-01157` al aplicar | Prevenido con `STANDBY_FILE_MANAGEMENT=AUTO`. Si falla: en la standby `ALTER DATABASE CREATE DATAFILE '<UNNAMED>' AS '<ruta>';` y volver a aplicar. |
| Archivos externos (`PADRON_COMPLETO.txt`, `DISTELEC.txt` en `DIR_PADRON`) | La tabla `CAT_PADRON` sí está replicada, pero los archivos del TSE no | Son archivos del sistema operativo, no viajan en el redo: tras activar la PC 2, ejecutar `datos/padron/Descargar_Padron_TSE.ps1` allí antes de la siguiente carga mensual. |
| Cambio de claves de usuarios SYS o del archivo de claves | Fallan conexiones `SYSDBA` remotas | Volver a copiar `PWD<SID>.ora` a la PC 2. |
| Falta un archivelog (hueco) | `RMAN-06054` pidiendo una secuencia vieja que no llega | `PR_SINCRONIZAR_AHORA` en la PC 1; si el archivo ya no existe, respaldo incremental desde el SCN de la standby (`BACKUP INCREMENTAL FROM SCN <scn> DATABASE`) y `RECOVER` en la PC 2. |
| Carpeta compartida inaccesible (PC 2 apagada, red) | Job `FAILED`; correo "inconsistencia en la sincronización" | Revisar red/permisos y ejecutar `PR_SINCRONIZAR_AHORA`: la copia es incremental y se pone al día sola. |
| Disco lleno en la Fast Recovery Area | `ORA-19809` / la base se detiene | `PR_PURGAR_AHORA`; si sigue lleno, aumentar `DB_RECOVERY_FILE_DEST_SIZE`. |
| Nueva PDB creada en la principal | La PDB no se abre en la standby | Respaldar la PDB y restaurarla en la standby, o recrear la standby (sección 4). |

---

# 11. Procedimiento con Data Guard (Oracle 21c Enterprise)

Este es el procedimiento **recomendado y verificado** del proyecto. Se probó con dos contenedores Docker de la imagen `container-registry.oracle.com/database/enterprise:21.3.0.0` en la red `oranet`:

| | Principal | Standby |
| :--- | :--- | :--- |
| Contenedor / hostname | `ora_principal` / `ora-principal` (puerto host 1531) | `ora_standby` / `ora-standby` (puerto host 1532) |
| `DB_NAME` / `DB_UNIQUE_NAME` | `CADENA` / `CADENA` | `CADENA` / `CADENA_STBY` |
| PDB | `PDBCADENA` | `PDBCADENA` |
| Archivos de red, spfile y claves | `/opt/oracle/oradata/dbconfig/CADENA/` | igual |
| Archivelogs | `/opt/oracle/oradata/CADENA/archive_logs` | igual |

`ORACLE_HOME` es `/opt/oracle/product/21c/dbhome_1`. Cómo levantar los contenedores: `sql/07_Standby_y_RMAN/docker/README.md` y sección 2 de `docs/GUIA_PASO_A_PASO.md`. En **dos PC** el procedimiento es el mismo: en `tnsnames.ora` se cambian `ora-principal` / `ora-standby` por las IP reales y se abre el puerto 1521 en el firewall.

Para entrar: `docker exec -it -u oracle <contenedor> sqlplus / as sysdba` (SQL) o `docker exec -it -u oracle <contenedor> bash` (terminal).

### 11.1 Oracle Net en las dos bases (`tnsnames.ora`)

Agregar al `tnsnames.ora` de `dbconfig` de **ambos** servidores (archivo de ejemplo `sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora`):

```
PRIMARIA_TNS = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora-principal)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CADENA)(UR=A)))
STANDBY_TNS  = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=ora-standby)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CADENA_STBY)(UR=A)))
```

`(UR=A)` permite conectarse a una instancia en `NOMOUNT` o `MOUNT`. Verificar con `tnsping STANDBY_TNS` (en la principal) y `tnsping PRIMARIA_TNS` (en la standby).

### 11.2 Servicio estático en la standby (`listener.ora`)

Solo en la standby (archivo `sql/07_Standby_y_RMAN/docker/listener_standby.ora`), y luego `lsnrctl reload`:

```
SID_LIST_LISTENER=(SID_LIST=(SID_DESC=(GLOBAL_DBNAME=CADENA_STBY)(ORACLE_HOME=/opt/oracle/product/21c/dbhome_1)(SID_NAME=CADENA)))
```

Sin este registro la principal no puede conectarse a la standby mientras está en `NOMOUNT` (durante su creación).

### 11.3 Configurar la principal

Ejecutar `01_Configuracion_Primaria_Redo_Archive.sql` como SYSDBA en `CDB$ROOT`, **dos veces** (la segunda borra los grupos de redo viejos de 200 MB que trae la imagen). En Enterprise configura:

* `LOG_ARCHIVE_DEST_2='SERVICE=STANDBY_TNS ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA_STBY'`
* `LOG_ARCHIVE_CONFIG='DG_CONFIG=(CADENA,CADENA_STBY)'`, `FAL_SERVER` y `STANDBY_FILE_MANAGEMENT=AUTO`.
* 3 grupos de redo de 50 MB con 2 miembros y 4 standby redo logs de 50 MB.

### 11.4 Respaldo de la principal, pfile y archivo de claves

En la terminal de la principal, desde `/opt/oracle/proyecto/sql/07_Standby_y_RMAN`:

```bash
NIVEL_BACKUP=0 bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh backup /opt/oracle/oradata/CADENA/archive_logs x /opt/oracle/backups /tmp/stby_bk 3 CADENA $ORACLE_HOME 10
sqlplus -s / as sysdba <<< "CREATE PFILE='/opt/oracle/backups/initCADENA_STBY.ora' FROM SPFILE;"
cp /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA /opt/oracle/backups/
```

El respaldo nivel 0 incluye el controlfile de standby (`bkp_ctrl_stby_*.bkp`). Resultado verificado: 682 MB, sin advertencias.

### 11.5 Trasladar el respaldo a la standby

Copiar todo `/opt/oracle/backups` a `/opt/oracle/standby_backups` de la standby. En dos PC: carpeta compartida o `scp`. En la prueba con Docker:

```powershell
docker cp ora_principal:/opt/oracle/backups .\backups_stby
docker cp .\backups_stby ora_standby:/opt/oracle/standby_backups
docker exec -u root ora_standby chown -R oracle:oinstall /opt/oracle/standby_backups
```

### 11.6 Preparar la instancia standby

1. El pfile es el de la principal **sin** las líneas `CADENA.__*` y con estos tres valores (plantilla `08_init_CADENA_STBY.ora`; `db_name` sigue siendo `'CADENA'`):

   ```
   *.db_unique_name='CADENA_STBY'
   *.fal_server='PRIMARIA_TNS'
   *.log_archive_dest_2='SERVICE=PRIMARIA_TNS ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA'
   ```

2. Detener la base que trae la imagen y borrarla (**solo en la standby**), y poner el archivo de claves de la principal:

   ```bash
   sqlplus -s / as sysdba <<< "SHUTDOWN ABORT"
   rm -rf /opt/oracle/oradata/CADENA/*
   mkdir -p /opt/oracle/oradata/CADENA/archive_logs /opt/oracle/standby_archive
   cp /opt/oracle/standby_backups/orapwCADENA /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA
   ```

3. Iniciar en `NOMOUNT`, crear el spfile y reiniciar con él:

   ```sql
   STARTUP NOMOUNT PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   CREATE SPFILE='/opt/oracle/oradata/dbconfig/CADENA/spfileCADENA.ora' FROM PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   SHUTDOWN IMMEDIATE;
   STARTUP NOMOUNT;
   ```

### 11.7 Crear la standby

```bash
cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh crearstandby x /opt/oracle/standby_archive x /opt/oracle/standby_backups 3 CADENA $ORACLE_HOME 10
```

Usa `08_Creacion_Standby_Segunda_PC.rman`. Resultado verificado: `PHYSICAL STANDBY` / `MOUNTED` en unos 3,5 minutos.

### 11.8 Iniciar la aplicación del redo y verificar la sincronización

En la standby:

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
```

| Dónde | Consulta | Resultado verificado |
| :--- | :--- | :--- |
| Principal | `SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id = 2;` | `VALID` / `NO GAP` |
| Standby | `SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';` | transport lag y apply lag en 0 |
| Standby | `SELECT process, status, sequence# FROM v$managed_standby;` | `MRP0` en `APPLYING_LOG` y procesos `RFS` |

Desde la principal también lo muestran `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;` y `PR_VERIFICAR_SINCRONIZACION` (detectan Data Guard: destino 2 `VALID`, sin huecos).

> Al reiniciar el contenedor de la standby, la imagen no levanta la instancia: hay que ejecutar `STARTUP MOUNT` y el comando de arriba.

### 11.9 Consultar los datos en la standby (Active Data Guard)

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
SELECT open_mode FROM v$database;     -- READ ONLY WITH APPLY
```

Verificado: la tabla `CADENA_NEG.DG_PRUEBA` creada en la principal se leyó en la standby (en `PDBCADENA`) a los pocos segundos.

### 11.10 Switchover (verificado ida y vuelta)

1. En la principal:

   ```sql
   ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;
   ALTER DATABASE SWITCHOVER TO CADENA_STBY;
   ```

2. La antigua principal se apaga (en Docker el contenedor se detiene). En la nueva principal (`ora_standby`):

   ```sql
   ALTER DATABASE OPEN;
   ALTER PLUGGABLE DATABASE ALL OPEN;
   ```

3. `docker start ora_principal` y en ella `STARTUP MOUNT` (si el contenedor la abrió sola, queda `READ ONLY`, que también sirve) y `ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;`.
4. Para volver: `ALTER DATABASE SWITCHOVER TO CADENA;` desde la que sea principal y los pasos 2 y 3 al revés.

### 11.11 Failover (verificado)

Prueba: se insertó una venta en la principal y se hizo `docker kill ora_principal` (desastre). En la standby:

```sql
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE FAILOVER TO CADENA_STBY;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
```

Resultado: `PRIMARY` / `READ WRITE` con la última venta (0 pérdida, gracias a la aplicación en tiempo real `USING CURRENT LOGFILE`). Luego se cambia la conexión de la aplicación a la IP de la nueva principal.

### 11.12 Recuperación después del failover (verificado)

1. Respaldo nivel 0 en la nueva principal con el orquestador (11.4) y copiarlo a la antigua (11.5).
2. En la antigua: `SHUTDOWN ABORT`, `rm -rf /opt/oracle/oradata/CADENA/*` y `STARTUP NOMOUNT` (su spfile ya es el de `CADENA`).
3. Modo `crearstandby` (11.7): vuelve como `PHYSICAL STANDBY` y se sincroniza (11.8).
4. Un switchover (11.10) devuelve los roles originales.

> Después de un failover la numeración de los archivelogs reinicia (nueva encarnación de la base). Por eso el monitoreo usa `V$ARCHIVE_DEST_STATUS` y no compara números de secuencia.

### 11.13 Purga y replicación de todas las acciones

* **Purga:** con Data Guard borra solo lo aplicado en la standby **y** respaldado. Lo demás lo conserva con el aviso `RMAN-08120` (no aplicado) o `RMAN-08138` (falta respaldo). Verificado con 0 días de retención, de prueba (sección 7).
* **Replicación:** reinstalar todo el esquema con Data Guard activo (`DROP USER`, borrar y crear tablespaces) se replicó a la standby con lag 0, gracias a `STANDBY_FILE_MANAGEMENT=AUTO` y `FORCE LOGGING`.
* **Pendiente de verificar:** los jobs `EXECUTABLE` con credencial del sistema operativo (en Docker el usuario `oracle` no tiene clave); sus trabajos se probaron ejecutando el orquestador a mano.

---

# 12. Guion para la demostración

Con Data Guard (sección 11), con las dos bases sincronizadas y la standby en `READ ONLY WITH APPLY`:

1. **PC 1:** `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;` y `SELECT dest_id, status, gap_status FROM v$archive_dest_status WHERE dest_id = 2;` – destino `VALID`, sin huecos.
2. **PC 2:** `SELECT database_role, open_mode FROM v$database;` (`PHYSICAL STANDBY` / `READ ONLY WITH APPLY`) y `SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';` (lag 0).
3. **PC 1:** insertar una factura de prueba (o crear la tabla `CADENA_NEG.DG_PRUEBA` con una fila) y `COMMIT`.
4. **PC 2:** consultarla en `PDBCADENA` a los pocos segundos: la sincronización es automática.
5. **PC 1:** respaldo RMAN a petición (`EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;`, o el orquestador en modo `backup` si la credencial del SO no está registrada) y purga (`PR_PURGAR_AHORA` o modo `purga`).
6. **Switchover** (11.10): la PC 2 pasa a principal, se consulta la factura en ella y se devuelven los roles con `SWITCHOVER TO CADENA`.
7. **Failover** (11.11), al final: detener la PC 1 (en Docker `docker kill ora_principal`), activar la PC 2 y consultar la factura en la base activada. Si hay tiempo, recuperar la PC 1 como standby (11.12).
