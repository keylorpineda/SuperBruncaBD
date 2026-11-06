# Guía paso a paso: de cero a todo funcionando

Esta guía es para las dos personas del grupo, cada una con su computadora. Al final la PC 1 tiene la base completa con sus jobs, y la PC 2 tiene una copia standby que se actualiza sola.

Los detalles técnicos están en los manuales oficiales de `docs/manuales/`. Aquí van los pasos en orden y los comandos que hay que ejecutar.

---

## 1. Por qué hacen falta dos computadoras

| Computadora | Qué es | Qué corre ahí |
| :--- | :--- | :--- |
| **PC 1: principal** | La base de datos "de verdad". Aquí se factura, se compra y se mueve el inventario. | Todos los scripts `sql/`, los paquetes y los jobs `DBMS_SCHEDULER`. |
| **PC 2: standby** | Una copia de la principal que se actualiza sola cada 10 minutos. No se usa para trabajar. | Recibe los archivelogs y los respaldos de la PC 1 y los aplica. |

Si la PC 1 falla, la PC 2 se **activa** y pasa a ser la base principal con casi todos los datos (failover). El enunciado exige que sean dos servidores distintos: si la copia estuviera en la misma computadora, una falla de disco se llevaría las dos.

---

## 2. Requisitos

En **las dos** computadoras:

1. **Oracle Database 21c Enterprise Edition**. Es la versión que pide el enunciado y la que trae Data Guard. Hay dos formas de tenerla:
   - **Docker** (recomendado) con la imagen oficial `container-registry.oracle.com/database/enterprise:21.3.0.0`.
   - Una **máquina virtual** con Oracle Linux y Oracle 21c instalado. La VM es opcional: solo se usa si no quiere Docker.
2. **Docker Desktop** (si usa Docker), con al menos 4 GB de RAM y unos 15 GB libres en disco para Oracle.
3. **Git** para bajar el repositorio.
4. Las dos PC en la **misma red**, con IP fija. Anote la IP de la PC 2 (la va a necesitar en el paso 6). Pruebe desde la PC 1 con `ping <IP de la PC 2>`.
5. Una cuenta de **Gmail** con verificación en 2 pasos (para la clave de aplicación del paso 6.1).

### 2.1 Descargar la imagen de Oracle 21c EE (una vez por PC)

La imagen es gratis, pero Oracle pide aceptar la licencia:

1. Entre a https://container-registry.oracle.com e inicie sesión con su cuenta de Oracle (si no tiene, créela ahí mismo).
2. Busque **Database** → **enterprise**, elija el idioma y acepte la licencia (*Continue* / *Accept*). Sin este paso la descarga da error de autorización.
3. Genere un **Auth Token**: menú de su perfil (arriba a la derecha) → **Auth Token** → **Generate Secret Key**. Copie el token: solo se muestra una vez.
4. Inicie sesión en Docker. Como usuario use el correo de su cuenta Oracle y como contraseña **pegue el Auth Token** (no la contraseña de la cuenta):

   ```powershell
   docker login container-registry.oracle.com
   ```

5. Descargue la imagen (pesa varios GB):

   ```powershell
   docker pull container-registry.oracle.com/database/enterprise:21.3.0.0
   ```

### 2.2 Crear el contenedor (una vez por PC)

Use la misma clave de `SYS` en las dos PC. En lugar de escribir la clave en el comando, puede guardarla en un archivo local `ORACLE_PWD=<su clave>` y pasarlo con `--env-file` (la carpeta `sql/07_Standby_y_RMAN/docker/` está pensada para eso y su archivo `oracle_ee.env` está en `.gitignore`, no se sube al repositorio).

```powershell
docker run -d --name oracle_una -p 1521:1521 `
  -e ORACLE_SID=ORCLCDB -e ORACLE_PDB=ORCLPDB1 -e ORACLE_PWD=<clave de SYS> `
  -v oracle_una_data:/opt/oracle/oradata `
  container-registry.oracle.com/database/enterprise:21.3.0.0
```

La primera vez tarda entre 10 y 20 minutos en crear la base. Espere hasta que el log diga `DATABASE IS READY TO USE!`:

```powershell
docker logs -f oracle_una
```

> En la PC 2 el contenedor también se crea, pero esa base se va a reemplazar por la copia standby en el paso 7.

---

## 3. Bajar el repositorio

En las dos PC:

```powershell
git clone <url del repositorio> Proyecto
cd Proyecto
```

---

## 4. Instalar la base en la PC 1 (principal)

1. Copie el repositorio completo dentro del contenedor (desde la raíz del repositorio):

   ```powershell
   docker cp . oracle_una:/opt/oracle/proyecto/
   ```

   Si no usa Docker, copie la carpeta a `C:\app\oracle\proyecto` (Windows) o `/opt/oracle/proyecto` (Linux). Son las rutas que los scripts usan por defecto.

2. Cree la base del Entregable #1 (tablespaces, usuario `CADENA_NEG`, tablas y datos) como SYSDBA:

   ```powershell
   docker exec -i -w /opt/oracle/proyecto/sql oracle_una sqlplus -s / as sysdba '@script_bd_v2.sql'
   ```

3. Ejecute el instalador maestro. Corre en orden los scripts `01` a `06` y `07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql`:

   ```powershell
   docker exec -i -w /opt/oracle/proyecto/sql oracle_una sqlplus -s / as sysdba '@00_Master_Instalacion_Avance2.sql' > instalacion.log
   ```

   Sin Docker: abra una terminal en la carpeta `sql` y ejecute `sqlplus / as sysdba @script_bd_v2.sql` y luego `sqlplus / as sysdba @00_Master_Instalacion_Avance2.sql`.

4. Revise el resultado en `instalacion.log`. Debe ver:
   - El mensaje `LAS 12 PRUEBAS (POSITIVAS Y NEGATIVAS) FINALIZARON CON 100% DE EXITO Y CERO ADVERTENCIAS.`
   - En el resumen final, ningún objeto con estado `INVALID` (**0 objetos inválidos**).

   También puede comprobarlo así:

   ```sql
   SELECT COUNT(*) FROM all_objects WHERE owner = 'CADENA_NEG' AND status = 'INVALID';   -- debe dar 0
   ```

Para entrar a SQL*Plus dentro del contenedor y ejecutar los comandos de los pasos siguientes:

```powershell
docker exec -it oracle_una sqlplus / as sysdba
```

```sql
ALTER SESSION SET CONTAINER = ORCLPDB1;
SET SERVEROUTPUT ON
```

---

## 5. Qué deja listo el instalador

- 10 paquetes, 21 triggers, 2 vistas materializadas y la tabla de parámetros `SEG_PARAMETRO`.
- 11 jobs `DBMS_SCHEDULER`. Los de negocio ya quedan programados. Los que ejecutan scripts del sistema operativo (3 del standby y `JOB_PADRON_DESCARGA`) quedan **deshabilitados** hasta registrar la credencial del paso 6.2.
- 4 roles con clave cifrada y 4 usuarios (`USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR`).

---

## 6. Configuración obligatoria después de instalar (PC 1)

### 6.1 Clave de aplicación de Gmail (para que salgan los correos)

1. En la cuenta de Google del correo emisor: **Gestionar tu cuenta** → **Seguridad** → **Verificación en 2 pasos** (actívela) → **Contraseñas de aplicaciones**. Cree una para "Oracle" y copie las 16 letras.
2. Guárdela cifrada (se cifra con AES-256 dentro de `PR_GUARDAR_PARAMETRO`; ver el Paso 8 del Manual de Instalación):

   ```sql
   EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '<clave de 16 letras sin espacios>');
   ```

3. Si el correo emisor o los destinatarios no son los suyos, cámbielos igual, con `'N'` (sin cifrar) en lugar de `'S'`: `CORREO_EMISOR`, `CORREO_COORDINADOR`, `CORREO_GERENTE` y `CORREO_DBA`.

   ```sql
   SELECT codigo_para, valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO WHERE codigo_para LIKE '%CORREO%';
   ```

4. Pruebe con una notificación:

   ```sql
   EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;
   ```

   Si no llega, revise `SELECT * FROM CADENA_NEG.AUD_ERROR_SISTEMA ORDER BY 1 DESC;` (ver la sección 9).

### 6.2 Credencial del sistema operativo (para los jobs externos)

Los jobs del standby y la descarga del padrón ejecutan scripts `.sh` / `.ps1`, y para eso Oracle necesita un usuario del sistema operativo:

```sql
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('<usuario del SO>', '<clave del SO>');
```

- En Docker el usuario es `oracle`. Si no tiene clave, asígnele una: `docker exec -it -u root oracle_una passwd oracle`.
- En Windows el usuario debe estar en el grupo `ORA_DBA` y el servicio `OracleJobScheduler<SID>` debe estar iniciado.

Al registrarla, los jobs externos se habilitan solos.

### 6.3 Rutas hacia la PC 2 (con la IP real)

El instalador crea las rutas del standby con un nombre de ejemplo (`PC-STANDBY` / `pc-standby`). Cámbielas por la IP de la PC 2 y vuelva a crear los jobs:

```sql
-- Linux / Docker (copia por scp con llave SSH)
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_ARCHIVE_DESTINO', 'STANDBY', 'Carpeta de archivelogs en la PC standby', 'Carpeta de la segunda PC', 'N', 'oracle@<IP PC 2>:/opt/oracle/standby_archive');
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_BACKUP_DESTINO', 'STANDBY', 'Carpeta de respaldos RMAN en la PC standby', 'Carpeta de la segunda PC', 'N', 'oracle@<IP PC 2>:/opt/oracle/standby_backups');
-- Windows (carpetas compartidas): '\\<IP PC 2>\standby_archive' y '\\<IP PC 2>\standby_backups'

EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS;
```

Revise también que `STANDBY_RUTA_SCRIPTS` apunte a la carpeta `sql/07_Standby_y_RMAN` del servidor (por defecto `/opt/oracle/proyecto/sql/07_Standby_y_RMAN` o `C:\app\oracle\proyecto\sql\07_Standby_y_RMAN`):

```sql
SELECT codigo_para, valor_texto_para, valor_num_para FROM CADENA_NEG.SEG_PARAMETRO WHERE modulo_para = 'STANDBY' ORDER BY 1;
```

---

## 7. Configurar el Standby (las dos PC)

Los pasos completos están en el [Manual de Administración del Standby](manuales/Manual_Administracion_Standby.md). Resumen:

1. **PC 2: preparar las carpetas** que reciben los archivos (`/opt/oracle/standby_archive` y `/opt/oracle/standby_backups`; en Windows, compartidas por red). En Linux/Docker, la PC 1 copia con `scp`, así que hay que dejar entrar a la PC 1 por SSH con llave (`ssh-copy-id oracle@<IP PC 2>`). Sección 2 del manual.
2. **PC 1: configurar redo y archivelogs** (redo de 50 MB, cambio cada 5 minutos, `FORCE LOGGING`). Pase la base a modo `ARCHIVELOG` y ejecute el script, conectado a `CDB$ROOT` (abra una sesión nueva con `docker exec -it oracle_una sqlplus / as sysdba` y **no** cambie de contenedor):

   ```sql
   SHUTDOWN IMMEDIATE;
   STARTUP MOUNT;
   ALTER DATABASE ARCHIVELOG;
   ALTER DATABASE OPEN;
   @/opt/oracle/proyecto/sql/07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql
   ```

3. **PC 1: primer respaldo**, que se copia solo a la PC 2:

   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;
   ```

4. **PC 2: crear la base standby** con ese respaldo (sección 4 del manual: archivo de claves, `08_init_CADENA_STBY.ora`, `STARTUP NOMOUNT` y el modo `crearstandby`). En Linux/Docker:

   ```bash
   cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
   ./02_Traslado_Archivelogs_10min_y_Ondemand.sh crearstandby x x x /opt/oracle/standby_backups
   ```

   En Windows: `.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo CrearStandby -RutaBackupsStandby C:\app\oracle\standby_backups`.

5. **PC 2: programar la sincronización y la purga** (cada 10 minutos y diaria). En Linux, agregue al `crontab` las dos líneas del encabezado de `02_Traslado_Archivelogs_10min_y_Ondemand.sh`. En Windows: `-Modo RegistrarTareasStandby` (sección 4, paso 7 del manual).
6. **Comprobar la sincronización** (sección 9.1 del manual): la última secuencia generada en la PC 1 debe coincidir con la última aplicada en la PC 2.

   ```sql
   -- PC 1
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
   SELECT MAX(sequence#) FROM v$archived_log WHERE dest_id = 1;
   -- PC 2 (después de aplicar)
   SELECT MAX(sequence#) FROM v$archived_log WHERE applied = 'YES';
   ```

7. **Purga a los 3 días**: la hacen solos `JOB_STANDBY_PURGA_ARCHIVELOG` en la PC 1 y la tarea programada en la PC 2. Para probarla: `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;` (sección 7 del manual).

---

## 8. Cargar el padrón del TSE

Siga la [Guía del padrón del TSE](GUIA_PADRON_TSE.md). En corto: descargar `padron_completo.zip`, dejar los `.txt` en la carpeta de `DIR_PADRON` y ejecutar `EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;` (unos 40 minutos).

---

## 9. Problemas frecuentes

| Problema | Causa | Solución |
| :--- | :--- | :--- |
| `ORA-28000: the account is locked` | Se falló la clave 3 veces (perfiles `PERFIL_CADENA_ADMIN` / `PERFIL_CADENA_OPER`). | Como SYSDBA: `ALTER USER USR_DIGITADOR ACCOUNT UNLOCK;` (cambie el usuario). |
| `docker login` dice `unauthorized` o *Auth failed* | Se usó la contraseña de Oracle en lugar del Auth Token, o no se aceptó la licencia. | Acepte la licencia de Database → enterprise y use el **Auth Token** como contraseña (paso 2.1). |
| `docker pull` dice `denied` | No se aceptó la licencia de la imagen. | Paso 2.1, punto 2. |
| El correo falla con `535` (*Username and Password not accepted*) | La clave de aplicación de Gmail es incorrecta, o se guardó la contraseña normal de Gmail. | Genere una nueva clave de aplicación y guárdela otra vez (paso 6.1). |
| El correo falla con `ORA-24247` | Falta el permiso de red (ACL) para el puerto SMTP. | Sección 6 del Manual de Instalación (`DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE`). |
| `ORA-29913` con `KUP-04040: file PADRON_COMPLETO.txt in DIR_PADRON not found` | El archivo del padrón no está en la carpeta de `DIR_PADRON`. | Descárguelo a esa carpeta ([Guía del padrón](GUIA_PADRON_TSE.md)). |
| `ORA-65096` al ejecutar algo a mano | La sesión está en `CDB$ROOT`. | `ALTER SESSION SET CONTAINER = ORCLPDB1;` |
| Un job del standby queda `FAILED` | Red, permisos o ruta mal escrita. | Revise `/opt/oracle/logs/standby_orquestador.log` y `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;`. Sección 10 del Manual del Standby. |

---

## 10. Estado de las pruebas

> PENDIENTE: resultados de las pruebas en Oracle 21c EE (en curso).
