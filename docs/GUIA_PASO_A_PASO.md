# Guía paso a paso: de cero a todo funcionando

Esta guía es para las dos personas del grupo. Al final hay una base **principal** completa con sus jobs y una base **standby** que se mantiene igual a la principal con **Oracle Data Guard**.

Los detalles técnicos están en los manuales oficiales de `docs/manuales/`. Aquí van los pasos en orden y los comandos que hay que ejecutar. Todo lo de esta guía se probó con Oracle 21c Enterprise Edition en Docker (ver la sección 10).

---


> **¿Le toca la PC standby?** Hay una guía solo para usted, con cada comando desde instalar Docker: [GUIA_COMPANERO_PC_STANDBY.md](GUIA_COMPANERO_PC_STANDBY.md).

## 1. Las dos bases y dónde corren

| Base | Nombre (`DB_UNIQUE_NAME`) | Contenedor Docker | Qué corre ahí |
| :--- | :--- | :--- | :--- |
| **Principal** | `CADENA` | `ora_principal` (hostname `ora-principal`) | La base "de verdad": facturas, compras, inventario. Todos los scripts `sql/`, los paquetes y los jobs `DBMS_SCHEDULER`. |
| **Standby** | `CADENA_STBY` | `ora_standby` (hostname `ora-standby`) | Copia de la principal. Recibe el redo por la red y lo aplica sola (Data Guard). Se puede consultar en solo lectura. |

Las dos bases se llaman `CADENA` por dentro (`DB_NAME`) y tienen el PDB `PDBCADENA`. Lo que las distingue es el `DB_UNIQUE_NAME`.

Hay dos formas de montarlo:

- **Para probar en una sola PC**: los dos contenedores en la misma computadora, unidos por la red Docker `oranet`. Es lo que se usó para verificar todo.
- **Para la defensa (una PC cada uno)**: la PC 1 corre la principal y la PC 2 la standby. Es la misma idea, con Docker o con una VM / instalación nativa de Oracle 21c EE. Solo cambia la conexión: en `tnsnames.ora` se pone la **IP real** de cada PC en lugar de `ora-principal` / `ora-standby`, y se abre el puerto 1521 en el firewall (sección 2.4).

El enunciado exige dos servidores distintos: si la copia estuviera en la misma computadora, una falla de disco se llevaría las dos. Por eso la defensa se hace con dos PC.

---

## 2. Requisitos y contenedores

### 2.1 Qué instalar

1. **Docker Desktop**. Si va a correr los dos contenedores en la misma PC, déle al menos **6 GB de RAM** (cada contenedor usa hasta 2,5 GB) y deje unos **30 GB libres** en disco. Con un contenedor por PC basta con 4 GB y 15 GB.
2. **Git** para bajar el repositorio.
3. Una cuenta de **Gmail** con verificación en 2 pasos (para la clave de aplicación del paso 6.1).
4. Solo si usa dos PC: las dos en la **misma red**, con IP fija. Pruebe desde la PC 1 con `ping <IP de la PC 2>`.

En lugar de Docker se puede usar una **máquina virtual** con Oracle Linux y Oracle 21c EE instalado. Los pasos son los mismos, pero se ejecutan dentro de la VM sin `docker exec`.

### 2.2 Descargar la imagen de Oracle 21c EE (una vez por PC)

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

### 2.3 Bajar el repositorio y crear el archivo de la clave

1. Baje el repositorio:

   ```powershell
   git clone <url del repositorio> Proyecto
   cd Proyecto
   ```

2. Cree el archivo `sql/07_Standby_y_RMAN/docker/oracle_ee.env` (por ejemplo con el Bloc de notas) con este contenido. Use **la misma clave de SYS** en las dos bases. Este archivo está en `.gitignore`: no se sube al repositorio.

   ```
   ORACLE_PWD=<su clave>
   ORACLE_SID=CADENA
   ORACLE_PDB=PDBCADENA
   INIT_SGA_SIZE=1024
   INIT_PGA_SIZE=300
   ENABLE_ARCHIVELOG=true
   ```

### 2.4 Crear los contenedores

**Las dos bases en una PC (prueba)**. Desde la raíz del repositorio:

1. Cree la red que une los dos contenedores:

   ```powershell
   docker network create oranet
   ```

2. Cree la principal y la standby:

   ```powershell
   docker run -d --name ora_principal --hostname ora-principal --network oranet --memory 2560m --shm-size 1g --env-file sql/07_Standby_y_RMAN/docker/oracle_ee.env -v ora_principal_data:/opt/oracle/oradata -p 1531:1521 container-registry.oracle.com/database/enterprise:21.3.0.0
   docker run -d --name ora_standby --hostname ora-standby --network oranet --memory 2560m --shm-size 1g --env-file sql/07_Standby_y_RMAN/docker/oracle_ee.env -v ora_standby_data:/opt/oracle/oradata -p 1532:1521 container-registry.oracle.com/database/enterprise:21.3.0.0
   ```

3. La primera vez cada base tarda entre **15 y 20 minutos**. Espere hasta que el log diga `DATABASE IS READY TO USE!`:

   ```powershell
   docker logs -f ora_principal
   docker logs -f ora_standby
   ```

Desde Windows (SQL Developer, DBeaver) la principal queda en `localhost:1531` y la standby en `localhost:1532`, servicio `PDBCADENA`.

**Una PC cada uno (defensa)**:

1. En la PC 1 cree solo `ora_principal` y en la PC 2 solo `ora_standby`, con el mismo comando de arriba pero **sin** `--network oranet` y con `-p 1521:1521` (así la otra PC entra por el puerto normal).
2. Abra el puerto 1521 en el firewall de Windows de las dos PC (PowerShell como administrador):

   ```powershell
   New-NetFirewallRule -DisplayName "Oracle 1521" -Direction Inbound -Protocol TCP -LocalPort 1521 -Action Allow
   ```

3. En `tnsnames.ora` (sección 7, paso 1) use `HOST=<IP de la PC 1>` en `PRIMARIA_TNS` y `HOST=<IP de la PC 2>` en `STANDBY_TNS`.

> Datos útiles del contenedor: `ORACLE_HOME` es `/opt/oracle/product/21c/dbhome_1` (solo lectura). Los archivos de red, el spfile y el archivo de claves están en `/opt/oracle/oradata/dbconfig/CADENA/` (`tnsnames.ora`, `listener.ora`, `spfileCADENA.ora`, `orapwCADENA`). Los archivelogs quedan en `/opt/oracle/oradata/CADENA/archive_logs` (no hay Fast Recovery Area).

---

## 3. Entrar a la base

Para abrir SQL*Plus como SYSDBA dentro de un contenedor:

```powershell
docker exec -it -u oracle ora_principal sqlplus / as sysdba
```

(cambie `ora_principal` por `ora_standby` para la otra). Para trabajar con las tablas del proyecto, cámbiese al PDB:

```sql
ALTER SESSION SET CONTAINER = PDBCADENA;
SET SERVEROUTPUT ON
```

Para abrir una terminal Linux dentro del contenedor (la usan los scripts `.sh` de los pasos siguientes):

```powershell
docker exec -it -u oracle ora_principal bash
```

---

## 4. Instalar la base en la principal

1. Copie el repositorio dentro del contenedor y déle los permisos al usuario `oracle` (desde la raíz del repositorio):

   ```powershell
   docker cp . ora_principal:/opt/oracle/proyecto
   docker exec -u root ora_principal chown -R oracle:oinstall /opt/oracle/proyecto
   ```

   Sin Docker, copie la carpeta a `/opt/oracle/proyecto` (Linux) o `C:\app\oracle\proyecto` (Windows). Son las rutas que los scripts usan por defecto.

2. Cree la base del Entregable #1 (tablespaces, usuario `CADENA_NEG`, tablas y datos):

   ```powershell
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql ora_principal sqlplus -s / as sysdba '@script_bd_v2.sql'
   ```

3. Ejecute el instalador maestro. Corre en orden los scripts `01` a `06` y `07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql`:

   ```powershell
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql ora_principal sqlplus -s / as sysdba '@00_Master_Instalacion_Avance2.sql' > instalacion.log
   ```

   Sin Docker: abra una terminal en la carpeta `sql` y ejecute `sqlplus / as sysdba @script_bd_v2.sql` y luego `sqlplus / as sysdba @00_Master_Instalacion_Avance2.sql`.

4. Revise `instalacion.log`. Debe ver:
   - El mensaje `LAS 12 PRUEBAS (POSITIVAS Y NEGATIVAS) FINALIZARON CON 100% DE EXITO Y CERO ADVERTENCIAS.`
   - En el resumen final, **0 objetos inválidos**: 65 tablas, 225 índices, 10 paquetes, 21 triggers, 11 jobs, 7 vistas y 2 vistas materializadas.

   También puede comprobarlo así (en `PDBCADENA`):

   ```sql
   SELECT COUNT(*) FROM all_objects WHERE owner = 'CADENA_NEG' AND status = 'INVALID';   -- debe dar 0
   ```

---

## 5. Qué deja listo el instalador

- 10 paquetes, 21 triggers, 2 vistas materializadas y la tabla de parámetros `SEG_PARAMETRO`.
- 11 jobs `DBMS_SCHEDULER`. Los de negocio ya quedan programados. Los que ejecutan scripts del sistema operativo (3 del standby y `JOB_PADRON_DESCARGA`) quedan **deshabilitados** hasta registrar la credencial del paso 6.2.
- 4 roles con clave cifrada y 4 usuarios (`USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR`).

---

## 6. Configuración obligatoria después de instalar (principal)

### 6.1 Correo: wallet y clave de aplicación de Gmail

Gmail exige conexión segura (SSL/TLS). Oracle 21c necesita un **wallet** con los certificados raíz de Google; sin él, el correo falla con `ORA-29024: Certificate validation failure`.

1. **Crear el wallet** (Docker / Linux). El script toma los certificados raíz GTS R1-R4 y GlobalSign del propio Linux, crea un wallet auto-login en `/opt/oracle/oradata/wallet_smtp` y registra la ruta en `SEG_PARAMETRO` (`SMTP_WALLET_PATH`):

   ```powershell
   docker exec -u oracle ora_principal bash /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh
   ```

   Debe terminar con `[OK] Wallet listo.`

2. **Crear la clave de aplicación** en la cuenta de Google del correo emisor: **Gestionar tu cuenta** → **Seguridad** → **Verificación en 2 pasos** (actívela) → **Contraseñas de aplicaciones**. Cree una para "Oracle" y copie las 16 letras.

3. **Guardarla cifrada** (se cifra con AES-256 dentro de `PR_GUARDAR_PARAMETRO`; ver los pasos 8 y 9 del Manual de Instalación), en `PDBCADENA`:

   ```sql
   EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '<clave de 16 letras sin espacios>');
   ```

4. Si el correo emisor o los destinatarios no son los suyos, cámbielos igual, con `'N'` (sin cifrar) en lugar de `'S'`: `CORREO_EMISOR`, `CORREO_COORDINADOR`, `CORREO_GERENTE` y `CORREO_DBA`.

   ```sql
   SELECT codigo_para, valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO WHERE codigo_para LIKE '%CORREO%';
   ```

5. Pruebe con una notificación:

   ```sql
   EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;
   ```

   Si no llega, revise `SELECT * FROM CADENA_NEG.AUD_ERROR_SISTEMA ORDER BY 1 DESC;`. Con el wallet listo, un error `535` significa que falta la clave de aplicación real (punto 3).

**Wallet en Windows nativo (alternativa, no probada en este proyecto).** Es el mismo concepto con `orapki`:

1. Exporte los certificados raíz **GTS Root R1** (y R2-R4) y **GlobalSign Root CA**: `certmgr.msc` → *Entidades de certificación raíz de confianza* → *Certificados* → clic derecho → *Todas las tareas* → *Exportar* → formato **X.509 codificado en Base 64 (.CER)**, por ejemplo a `C:\temp\GTS_Root_R1.cer`.
2. Cree el wallet y agregue cada certificado:

   ```bat
   orapki wallet create -wallet C:\app\oracle\wallet_smtp -pwd <clave del wallet> -auto_login
   orapki wallet add -wallet C:\app\oracle\wallet_smtp -trusted_cert -cert C:\temp\GTS_Root_R1.cer -pwd <clave del wallet>
   ```

3. Registre la ruta en `PDBCADENA`:

   ```sql
   EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('SMTP_WALLET_PATH', 'CORREO', 'Ruta del Oracle Wallet SMTP', 'Wallet auto-login con los certificados raiz de Gmail para UTL_SMTP (SSL/TLS).', 'N', 'file:C:\app\oracle\wallet_smtp');
   ```

### 6.2 Credencial del sistema operativo (para los jobs externos)

Los jobs del standby y la descarga del padrón ejecutan scripts `.sh` / `.ps1`, y para eso Oracle necesita un usuario del sistema operativo:

```sql
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('<usuario del SO>', '<clave del SO>');
```

- En Docker el usuario es `oracle`, pero en la imagen **no tiene clave**. Asígnele una: `docker exec -it -u root ora_principal passwd oracle`. Verificado: con esa clave registrada, los 4 jobs del standby corren solos (`SUCCEEDED`).
- En Windows el usuario debe estar en el grupo `ORA_DBA` y el servicio `OracleJobScheduler<SID>` debe estar iniciado.

Al registrarla, los jobs externos se habilitan solos. Mientras tanto, los mismos trabajos se pueden hacer a mano con el orquestador `02_Traslado_Archivelogs_10min_y_Ondemand.sh` (así se hicieron las pruebas de la sección 7).

### 6.3 Rutas hacia la standby

Con Data Guard los archivelogs viajan solos por la red (`LOG_ARCHIVE_DEST_2`). Las rutas de `SEG_PARAMETRO` se usan para copiar los **respaldos RMAN** a la standby. El instalador las crea con un nombre de ejemplo (`pc-standby`). Cámbielas por la IP de la PC 2 y vuelva a crear los jobs:

```sql
-- Linux / Docker (copia por scp con llave SSH)
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_ARCHIVE_DESTINO', 'STANDBY', 'Carpeta de archivelogs en la PC standby', 'Carpeta de la segunda PC', 'N', 'oracle@<IP PC 2>:/opt/oracle/standby_archive');
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('STANDBY_RUTA_BACKUP_DESTINO', 'STANDBY', 'Carpeta de respaldos RMAN en la PC standby', 'Carpeta de la segunda PC', 'N', 'oracle@<IP PC 2>:/opt/oracle/standby_backups');
-- Windows (carpetas compartidas): '\\<IP PC 2>\standby_archive' y '\\<IP PC 2>\standby_backups'

EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_CONFIGURAR_JOBS;
```

Revise también que `STANDBY_RUTA_SCRIPTS` apunte a `/opt/oracle/proyecto/sql/07_Standby_y_RMAN` (o `C:\app\oracle\proyecto\sql\07_Standby_y_RMAN`):

```sql
SELECT codigo_para, valor_texto_para, valor_num_para FROM CADENA_NEG.SEG_PARAMETRO WHERE modulo_para = 'STANDBY' ORDER BY 1;
```

---

## 7. Configurar el Standby con Data Guard

Este es el resumen. El procedimiento completo, con lo que debe salir en cada paso, está en la **sección 11** del [Manual de Administración del Standby](manuales/Manual_Administracion_Standby.md). Los archivos de red de ejemplo están en `sql/07_Standby_y_RMAN/docker/` (ver su `README.md`).

1. **Las dos bases: `tnsnames.ora`.** Agregue las entradas `PRIMARIA_TNS` y `STANDBY_TNS` (archivo `sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora`) al final de `/opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora` de **cada** contenedor:

   ```powershell
   docker cp sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora ora_principal:/tmp/
   docker exec -u root ora_principal bash -c "cat /tmp/tnsnames_dataguard.ora >> /opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora"
   docker cp sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora ora_standby:/tmp/
   docker exec -u root ora_standby bash -c "cat /tmp/tnsnames_dataguard.ora >> /opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora"
   ```

   Compruebe desde cada uno: `docker exec -u oracle ora_principal tnsping STANDBY_TNS` y `docker exec -u oracle ora_standby tnsping PRIMARIA_TNS` (deben decir `OK`). En dos PC, antes cambie `ora-principal` / `ora-standby` por las IP.

2. **Solo la standby: `listener.ora`.** Agregue el `SID_LIST` de `listener_standby.ora` y recargue el listener:

   ```powershell
   docker cp sql/07_Standby_y_RMAN/docker/listener_standby.ora ora_standby:/tmp/
   docker exec -u root ora_standby bash -c "cat /tmp/listener_standby.ora >> /opt/oracle/oradata/dbconfig/CADENA/listener.ora"
   docker exec -u oracle ora_standby lsnrctl reload
   ```

3. **Principal: redo y destinos.** Ejecute el script como SYSDBA en `CDB$ROOT`, **dos veces** (la segunda borra los grupos de redo viejos de 200 MB). La base de Docker ya está en `ARCHIVELOG` por `ENABLE_ARCHIVELOG=true`:

   ```powershell
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql/07_Standby_y_RMAN ora_principal sqlplus -s / as sysdba '@01_Configuracion_Primaria_Redo_Archive.sql'
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql/07_Standby_y_RMAN ora_principal sqlplus -s / as sysdba '@01_Configuracion_Primaria_Redo_Archive.sql'
   ```

   En Enterprise deja: `LOG_ARCHIVE_DEST_2` hacia `STANDBY_TNS`, `LOG_ARCHIVE_CONFIG='DG_CONFIG=(CADENA,CADENA_STBY)'`, `FAL_SERVER`, `STANDBY_FILE_MANAGEMENT=AUTO`, 3 grupos de redo de 50 MB con 2 miembros y 4 standby redo logs de 50 MB.

4. **Principal: respaldo completo, pfile y archivo de claves.** En una terminal del contenedor (`docker exec -it -u oracle -w /opt/oracle/proyecto/sql/07_Standby_y_RMAN ora_principal bash`):

   ```bash
   NIVEL_BACKUP=0 bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh backup /opt/oracle/oradata/CADENA/archive_logs x /opt/oracle/backups /tmp/stby_bk 3 CADENA $ORACLE_HOME 10
   sqlplus -s / as sysdba <<< "CREATE PFILE='/opt/oracle/backups/initCADENA_STBY.ora' FROM SPFILE;"
   cp /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA /opt/oracle/backups/
   ls /opt/oracle/backups      # debe haber bkp_ctrl_stby_*.bkp (controlfile de standby)
   ```

   El 5.º argumento es la carpeta donde el script deja una copia del respaldo (en la prueba se usó `/tmp/stby_bk`; en dos PC ponga ahí la carpeta compartida de la standby y se salta el paso 5).

5. **Pasar `/opt/oracle/backups` a la standby** en `/opt/oracle/standby_backups`. En una PC (desde Windows):

   ```powershell
   docker cp ora_principal:/opt/oracle/backups .\backups_stby
   docker cp .\backups_stby ora_standby:/opt/oracle/standby_backups
   docker exec -u root ora_standby chown -R oracle:oinstall /opt/oracle/standby_backups
   ```

   En dos PC: carpeta compartida o `scp -r /opt/oracle/backups/* oracle@<IP PC 2>:/opt/oracle/standby_backups/`. Copie también el repositorio a la standby igual que en el punto 1 de la sección 4 (`docker cp . ora_standby:/opt/oracle/proyecto` y el `chown`).

6. **Standby: pfile, archivo de claves e instancia en `NOMOUNT`.** Ajuste el pfile: quite las líneas `CADENA.__*` y deje `db_unique_name`, `fal_server` y `log_archive_dest_2` como en la plantilla `sql/07_Standby_y_RMAN/08_init_CADENA_STBY.ora` (`db_name` sigue siendo `'CADENA'`). En una terminal de la standby (`docker exec -it -u oracle ora_standby bash`):

   ```bash
   cd /opt/oracle/standby_backups
   sed -i "/^CADENA\.__/d; /^\*\.db_unique_name/d; /^\*\.fal_server/d; /^\*\.log_archive_dest_2/d" initCADENA_STBY.ora
   cat >> initCADENA_STBY.ora <<'EOF'
   *.db_unique_name='CADENA_STBY'
   *.fal_server='PRIMARIA_TNS'
   *.log_archive_dest_2='SERVICE=PRIMARIA_TNS ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA'
   EOF
   ```

   Luego borre la base que trae la imagen y arranque con ese pfile. **Cuidado: el `rm` se hace solo en la standby.**

   ```bash
   sqlplus -s / as sysdba <<< "SHUTDOWN ABORT"
   rm -rf /opt/oracle/oradata/CADENA/*
   mkdir -p /opt/oracle/oradata/CADENA/archive_logs /opt/oracle/standby_archive
   cp /opt/oracle/standby_backups/orapwCADENA /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA
   sqlplus / as sysdba
   ```

   ```sql
   STARTUP NOMOUNT PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   CREATE SPFILE='/opt/oracle/oradata/dbconfig/CADENA/spfileCADENA.ora' FROM PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   SHUTDOWN IMMEDIATE;
   STARTUP NOMOUNT;
   EXIT
   ```

7. **Standby: crear la base standby** con el respaldo (usa `08_Creacion_Standby_Segunda_PC.rman`; tarda unos 3,5 minutos):

   ```bash
   cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
   bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh crearstandby x /opt/oracle/standby_archive x /opt/oracle/standby_backups 3 CADENA $ORACLE_HOME 10
   ```

   Al final `SELECT database_role, open_mode FROM v$database;` debe dar `PHYSICAL STANDBY` / `MOUNTED`.

8. **Standby: iniciar la aplicación automática del redo** (proceso `MRP0`) y comprobar:

   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   ```

   ```sql
   -- En la principal: VALID y NO GAP
   SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id = 2;
   -- En la standby: transport lag y apply lag en 0
   SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';
   SELECT process, status, sequence# FROM v$managed_standby;   -- MRP0 APPLYING_LOG y RFS
   ```

9. **Standby: abrirla para consultar (Active Data Guard).** Se detiene el MRP, se abre en solo lectura y se vuelve a iniciar el MRP:

   ```sql
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
   ALTER DATABASE OPEN READ ONLY;
   ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   SELECT open_mode FROM v$database;   -- READ ONLY WITH APPLY
   ```

   Prueba: cree una tabla o una factura en la principal (con `COMMIT`) y consúltela en la standby, en `PDBCADENA`, a los pocos segundos.

10. **Switchover (cambio de roles planificado).** En la principal:

    ```sql
    ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;
    ALTER DATABASE SWITCHOVER TO CADENA_STBY;
    ```

    La antigua principal se apaga (en Docker el contenedor se detiene). En la nueva principal (`ora_standby`): `ALTER DATABASE OPEN;` y `ALTER PLUGGABLE DATABASE ALL OPEN;`. Luego `docker start ora_principal` y en ella: `STARTUP MOUNT` (si el contenedor la abrió sola, queda `READ ONLY`, también sirve) y `ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;`. Para volver: `ALTER DATABASE SWITCHOVER TO CADENA;` desde la que sea principal en ese momento y los mismos pasos al revés.

11. **Failover (la principal se perdió).** En la standby:

    ```sql
    ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
    ALTER DATABASE FAILOVER TO CADENA_STBY;
    ALTER DATABASE OPEN;
    ALTER PLUGGABLE DATABASE ALL OPEN;
    ALTER PLUGGABLE DATABASE ALL SAVE STATE;
    ```

    Queda `PRIMARY` / `READ WRITE` con todos los datos confirmados.

12. **Recuperar la standby después de un failover.** Respaldo nivel 0 en la nueva principal (paso 4), copiarlo a la antigua (paso 5), y en la antigua: `SHUTDOWN ABORT`, `rm -rf /opt/oracle/oradata/CADENA/*`, `STARTUP NOMOUNT` (su spfile ya es el de `CADENA`) y el modo `crearstandby` (paso 7). Vuelve como `PHYSICAL STANDBY`. Después, un switchover devuelve los roles originales.

> **Al reiniciar el contenedor de la standby** la imagen no levanta la instancia sola: entre con SQL*Plus y ejecute `STARTUP MOUNT` y el comando del paso 8.

**Respaldo diario trasladado solo a la standby, sin intervención (Data Guard).** Una sola vez, en la principal:

1. Credencial del SO (sección 6.2). En Docker, asígnele clave al usuario `oracle` **en los dos contenedores** y regístrela:

   ```powershell
   docker exec -it -u root ora_principal passwd oracle
   docker exec -it -u root ora_standby passwd oracle
   ```

   ```sql
   -- en PDBCADENA (menú, opción 9)
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('oracle', '<la clave que puso>');
   ```

2. Enlace para enviar los respaldos por la red de Oracle (la standby debe estar en `READ ONLY WITH APPLY`: menú, opción 2; y en la standby debe existir `/opt/oracle/standby_backups`, paso 5):

   ```bash
   # dentro de ora_principal
   cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
   sqlplus / as sysdba @10_Enlace_Respaldos_DataGuard.sql '<clave de SYSTEM de la principal>'
   ```

   Crea los directorios `DIR_RESPALDOS` / `DIR_RESPALDOS_STBY`, el database link `LNK_STANDBY` y deja
   `STANDBY_RUTA_ARCHIVE_DESTINO = dataguard` (los archivelogs los manda Data Guard) y
   `STANDBY_RUTA_BACKUP_DESTINO = oracle:LNK_STANDBY` (cada respaldo nuevo se copia con
   `DBMS_FILE_TRANSFER.PUT_FILE`, por el mismo puerto 1521, sin carpetas compartidas).

Desde ese momento todo es automático: `JOB_STANDBY_TRASLADO_ARCHIVELOG` cada 10 min,
`JOB_RMAN_BACKUP_DIARIO` a la 01:00 (nivel 0 domingo / 1 el resto) con envío a la standby,
`JOB_STANDBY_PURGA_ARCHIVELOG` a las 03:00 y `JOB_STANDBY_MONITOREO` cada hora.
Para probarlos a petición: `PR_SINCRONIZAR_AHORA`, `PR_RESPALDAR_AHORA`, `PR_PURGAR_AHORA`.

**Purga a los 3 días y respaldo diario.** Los hacen `JOB_STANDBY_PURGA_ARCHIVELOG` y `JOB_RMAN_BACKUP_DIARIO` cuando la credencial del paso 6.2 está registrada. A mano: `bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh purga x x x x 3 CADENA $ORACLE_HOME 10`. Con Data Guard la purga solo borra lo que ya se aplicó en la standby **y** está respaldado (sección 7 del manual).

**Monitoreo** (en la principal, `PDBCADENA`):

```sql
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION;
```

---

## 8. Cargar el padrón del TSE

Siga la [Guía del padrón del TSE](GUIA_PADRON_TSE.md). En corto: descargar `padron_completo.zip`, dejar los `.txt` en la carpeta de `DIR_PADRON` (en Docker `/opt/oracle/oradata/CADENA/PDBCADENA`) y ejecutar `EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;` (unos 40 minutos).

---

## 9. Problemas frecuentes

| Problema | Causa | Solución |
| :--- | :--- | :--- |
| `ORA-28000: the account is locked` | Se falló la clave 3 veces (perfiles `PERFIL_CADENA_ADMIN` / `PERFIL_CADENA_OPER`). | Como SYSDBA: `ALTER USER USR_DIGITADOR ACCOUNT UNLOCK;` (cambie el usuario). |
| `docker login` dice `unauthorized` o *Auth failed* | Se usó la contraseña de Oracle en lugar del Auth Token, o no se aceptó la licencia. | Acepte la licencia de Database → enterprise y use el **Auth Token** como contraseña (paso 2.2). |
| `docker pull` dice `denied` | No se aceptó la licencia de la imagen. | Paso 2.2, punto 2. |
| El contenedor se detiene solo o la base no arranca | Docker no tiene memoria suficiente. | Déle más RAM a Docker Desktop (paso 2.1). |
| El correo falla con `ORA-29024: Certificate validation failure` | Falta el wallet con los certificados de Gmail. | Paso 6.1, punto 1. |
| El correo falla con `535` (*Username and Password not accepted*) | La clave de aplicación de Gmail es incorrecta, o se guardó la contraseña normal de Gmail. | Genere una nueva clave de aplicación y guárdela otra vez (paso 6.1). |
| El correo falla con `ORA-24247` | Falta el permiso de red (ACL) para el puerto SMTP. | Sección 6 del Manual de Instalación (`DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE`). |
| `tnsping` falla o `v$archive_dest_status` muestra `ERROR` en el destino 2 | Falta la entrada en `tnsnames.ora`, la IP está mal o el firewall bloquea el 1521. | Sección 7, pasos 1 y 2; en dos PC, sección 2.4. |
| La standby no aparece después de reiniciar su contenedor | La imagen no levanta la instancia standby sola. | `STARTUP MOUNT` y el comando del paso 8 de la sección 7. |
| `ORA-29913` con `KUP-04040: file PADRON_COMPLETO.txt in DIR_PADRON not found` | El archivo del padrón no está en la carpeta de `DIR_PADRON`. | Descárguelo a esa carpeta ([Guía del padrón](GUIA_PADRON_TSE.md)). |
| `ORA-65096` al ejecutar algo a mano | La sesión está en `CDB$ROOT`. | `ALTER SESSION SET CONTAINER = PDBCADENA;` |
| Un job del standby queda `FAILED` | Red, permisos o ruta mal escrita. | Revise `/opt/oracle/logs/standby_orquestador.log` y `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;`. Sección 10 del Manual del Standby. |

---

## 10. Estado de las pruebas

Verificado en dos contenedores Docker con `container-registry.oracle.com/database/enterprise:21.3.0.0` (Oracle 21c Enterprise Edition), red `oranet`, principal `CADENA` y standby `CADENA_STBY`:

| Prueba | Resultado |
| :--- | :--- |
| Instalación (`script_bd_v2.sql` + `00_Master_Instalacion_Avance2.sql`) | 0 objetos inválidos (65 tablas, 225 índices, 10 paquetes, 21 triggers, 11 jobs, 7 vistas, 2 vistas materializadas). Las 12 pruebas con 100 % de éxito. |
| Correo con wallet (`08_Wallet_SMTP_Gmail.sh`) | El `ORA-29024` desaparece; el siguiente error es `535` hasta guardar la clave de aplicación real de Gmail. |
| Configuración de la principal (`01_...sql`, dos veces) | `LOG_ARCHIVE_DEST_2` hacia `CADENA_STBY`, `DG_CONFIG=(CADENA,CADENA_STBY)`, redo 3 × 50 MB × 2 miembros y 4 standby redo logs de 50 MB. |
| Respaldo nivel 0 con el orquestador | 682 MB, sin advertencias, incluye el controlfile de standby. |
| Creación de la standby (`crearstandby`) | `PHYSICAL STANDBY` / `MOUNTED` en unos 3,5 minutos. |
| Sincronización Data Guard | Destino 2 `VALID` / `NO GAP`; transport lag y apply lag en 0; `MRP0 APPLYING_LOG` y `RFS`. |
| Active Data Guard | `READ ONLY WITH APPLY`: la tabla `CADENA_NEG.DG_PRUEBA` creada en la principal se leyó en la standby. |
| Switchover ida y vuelta | `CADENA` → `CADENA_STBY` → `CADENA`, sin pérdida. |
| Failover | Tras `docker kill ora_principal`, la standby quedó `PRIMARY` / `READ WRITE` con la última venta (0 pérdida, por la aplicación en tiempo real). |
| Recuperación tras el failover | La antigua principal se recreó como standby desde un respaldo de la nueva y se sincronizó; un switchover devolvió los roles. |
| Purga con Data Guard (0 días, de prueba) | Borra solo lo aplicado en la standby y respaldado; avisa `RMAN-08120` (no aplicado) y `RMAN-08138` (falta respaldo) y conserva esos archivos. |
| Reinstalar el esquema con Data Guard activo | `DROP USER`, borrar y crear tablespaces se replicó a la standby con lag 0 (`STANDBY_FILE_MANAGEMENT=AUTO`). |
| Monitoreo (`PR_ESTADO_STANDBY`, `PR_VERIFICAR_SINCRONIZACION`) | Detectan Data Guard: destino 2 `VALID`, sin huecos. |
| Jobs `EXECUTABLE` con la credencial del SO (usuario `oracle` con clave) | `JOB_STANDBY_TRASLADO_ARCHIVELOG`, `JOB_RMAN_BACKUP_DIARIO` y `JOB_STANDBY_PURGA_ARCHIVELOG` corren solos y a petición: `SUCCEEDED`. El de traslado se ejecuta cada 10 minutos sin intervención. |
| Respaldo diario trasladado a la standby por la red de Oracle (`10_Enlace_Respaldos_DataGuard.sql`) | El respaldo nivel 1 del job envió sus 9 piezas nuevas a `/opt/oracle/standby_backups` de la standby con `DBMS_FILE_TRANSFER` por `LNK_STANDBY`; las que ya estaban se omiten. |
| Monitoreo después de los jobs | `PR_VERIFICAR_SINCRONIZACION`: "Standby sincronizado: sin inconsistencias"; último traslado hace 1 minuto, 0 fallos. |

**No verificado todavía:**

| Prueba | Motivo |
| :--- | :--- |
| Wallet en Windows nativo con `orapki` | Solo se probó en Linux / Docker. |
| Descarga automática mensual del padrón (`JOB_PADRON_DESCARGA`) por el job | Quedó habilitada con la credencial; la descarga y la carga se probaron con el script y el procedimiento a mano. |
| Red entre dos PC distintas | Todo se probó con dos contenedores en una misma PC. |

> **Verificado en Oracle 21c EE con Data Guard activo:** padrón del 30/09/2026, 3.762.240 personas, 0 rechazos, 2.179 distritos electorales, ~52 minutos (más lento que sin Data Guard porque cada cambio viaja también a la standby). Al terminar, la standby seguía sincronizada: `transport lag` y `apply lag` en 0 y `GAP_STATUS = NO GAP`.
