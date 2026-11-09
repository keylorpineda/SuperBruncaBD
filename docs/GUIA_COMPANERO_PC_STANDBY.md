# Guía para el compañero: montar la PC Standby desde cero

Esta guía es para **la persona que pone la segunda computadora** (la *standby*).
No necesita saber nada del proyecto: siga los pasos en orden y copie los comandos.

**Qué va a lograr:** tener en su PC una copia exacta de la base de datos de la PC principal
(la de Keylor), que se actualiza sola cada vez que hay un cambio, y que puede tomar el
control si la principal falla. Eso es lo que se demuestra en la defensa (35 % de la nota).

```
 PC 1 - KEYLOR (principal)                      PC 2 - USTED (standby)
 contenedor ora_principal                        contenedor ora_standby
 base CADENA  (PRIMARY, READ WRITE)  ==== red ==> base CADENA_STBY (PHYSICAL STANDBY)
            Data Guard envia cada cambio por el puerto 1521
```

Hay pasos que hace **usted** (🟢) y pasos que hace **Keylor** (🔵). Cuando diga
"🔵 Keylor", espere a que él lo termine antes de seguir.

> **Regla de oro:** los comandos de Oracle (`sqlplus`, scripts `.sh`) se escriben **dentro del
> contenedor** (`docker exec -it -u oracle <contenedor> bash`). En PowerShell solo van los comandos
> `docker ...`. Así se evitan problemas de Windows con las comillas y el símbolo `$`.

> **Ya probado:** todo este procedimiento se probó en Oracle 21c EE con dos contenedores
> en una misma PC: la standby se creó, sincronizó con 0 segundos de atraso, y se hicieron
> switchover, failover y recuperación. Lo único **no probado** es la red entre dos PC
> distintas (IPs y firewall de Windows, pasos 6 y 9): si algo falla ahí, vea
> [Problemas frecuentes](#problemas-frecuentes).

---

## Antes de empezar

| Necesita | Detalle |
| :--- | :--- |
| Windows 10/11 de 64 bits | Con virtualización activada en la BIOS (casi todas las PC nuevas la traen). |
| RAM | 8 GB mínimo (16 GB recomendado). La base usa ~2,5 GB. |
| Disco | 40 GB libres (la imagen de Oracle pesa ~8 GB y la base unos 10 GB). |
| Red | Las dos PC conectadas **a la misma red** (mismo Wi-Fi o mismo router). |
| Cuenta de Oracle | Gratis. Se crea en el paso 2. |
| Git | Para descargar el proyecto: https://git-scm.com/download/win |

Tiempo total: ~1 hora (la mayor parte es esperar descargas).

---

## 🟢 Paso 1. Instalar Docker Desktop

1. Descargue Docker Desktop: https://www.docker.com/products/docker-desktop/
2. Instálelo con las opciones por defecto (usa **WSL 2**). Reinicie si lo pide.
3. Ábralo y espere a que abajo a la izquierda diga **"Engine running"**.
4. Abra **PowerShell** y compruebe:

   ```powershell
   docker version
   ```

   Debe mostrar "Client" y "Server" sin errores.

## 🟢 Paso 2. Cuenta de Oracle y permiso para descargar Oracle 21c EE

Oracle Enterprise es gratis para estudiar, pero pide cuenta y aceptar la licencia.

1. Entre a https://container-registry.oracle.com e inicie sesión (o cree una cuenta con su correo).
2. Busque **Database → enterprise**. A la derecha elija el idioma y acepte la licencia
   (*Continue*). Debe quedar un mensaje de que ya la aceptó.
3. Arriba a la derecha: **su usuario → Auth Token → Generate Secret Key**.
   **Copie la clave** que aparece (solo se muestra una vez).
4. En PowerShell:

   ```powershell
   docker login container-registry.oracle.com
   ```

   - Username: su correo de Oracle
   - Password: **pegue el Auth Token** (no su contraseña de Oracle)

   Debe decir **Login Succeeded**. Si dice `unauthorized: Auth failed`, revise que usó el
   token y que aceptó la licencia del paso 2.

## 🟢 Paso 3. Descargar Oracle 21c EE (~8 GB)

```powershell
docker pull container-registry.oracle.com/database/enterprise:21.3.0.0
```

Tarda según su internet. Puede seguir con el paso 4 mientras tanto.

## 🟢 Paso 4. Descargar el proyecto

```powershell
cd $HOME\Documents
git clone https://github.com/keylorpineda/ProyectoAdminBD.git
cd ProyectoAdminBD
```

## 🟢 Paso 5. Crear su servidor Oracle (contenedor `ora_standby`)

1. Cree el archivo de configuración `sql\07_Standby_y_RMAN\docker\oracle_ee.env`
   (no se sube a GitHub). Cambie `<su clave>` por una clave suya (letras y números, sin espacios):

   ```powershell
   @"
   ORACLE_PWD=<su clave>
   ORACLE_SID=CADENA
   ORACLE_PDB=PDBCADENA
   INIT_SGA_SIZE=1024
   INIT_PGA_SIZE=300
   ENABLE_ARCHIVELOG=true
   "@ | Set-Content -Encoding ascii sql\07_Standby_y_RMAN\docker\oracle_ee.env
   ```

   `ORACLE_SID=CADENA` y `ORACLE_PDB=PDBCADENA` **deben ser exactamente esos**: la standby
   tiene que llamarse igual que la principal.

2. Cree el contenedor (publica el puerto 1521 para que la PC de Keylor lo alcance):

   ```powershell
   docker run -d --name ora_standby --hostname ora-standby `
     -p 1521:1521 --memory 2560m --shm-size 1g `
     --env-file sql\07_Standby_y_RMAN\docker\oracle_ee.env `
     -v ora_standby_data:/opt/oracle/oradata `
     container-registry.oracle.com/database/enterprise:21.3.0.0
   ```

3. Espere **15 a 20 minutos** a que Oracle cree la base inicial. Vea el avance con:

   ```powershell
   docker logs -f ora_standby
   ```

   Cuando aparezca **`DATABASE IS READY TO USE!`** presione `Ctrl + C` (el contenedor sigue corriendo).

> Esta base inicial es solo para que Oracle quede instalado. En el paso 11 se borra y se
> reemplaza por la copia de la base de Keylor.

## 🟢🔵 Paso 6. Red: IPs y firewall (los dos)

Cada uno, en su PC:

1. Averigüe su IP (busque "Dirección IPv4" del adaptador Wi-Fi o Ethernet, p. ej. `192.168.1.25`):

   ```powershell
   ipconfig
   ```

2. Abra el puerto 1521 en el firewall. **PowerShell como administrador** (clic derecho → *Ejecutar como administrador*):

   ```powershell
   New-NetFirewallRule -DisplayName "Oracle 1521 (proyecto)" -Direction Inbound -Protocol TCP -LocalPort 1521 -Action Allow
   ```

3. Intercambien las IPs. En esta guía se escriben como `<IP_KEYLOR>` y `<IP_STANDBY>`.
4. Compruebe que se ven (usted hacia Keylor):

   ```powershell
   Test-NetConnection <IP_KEYLOR> -Port 1521
   ```

   Debe decir `TcpTestSucceeded : True`. Keylor hace lo mismo con `<IP_STANDBY>`.

> Las IP de Wi-Fi pueden cambiar si apagan el router. Si cambian, repita el paso 7 con las nuevas.

## 🟢🔵 Paso 7. Decirle a Oracle dónde está cada servidor (`tnsnames.ora`)

Los **dos** agregan estas dos entradas, cambiando las IPs. En su PC (copie todo el bloque en PowerShell):

```powershell
@"

PRIMARIA_TNS = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=<IP_KEYLOR>)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CADENA)(UR=A)))

STANDBY_TNS = (DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=<IP_STANDBY>)(PORT=1521))(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=CADENA_STBY)(UR=A)))
"@ | Set-Content -Encoding ascii tns.txt
docker cp tns.txt ora_standby:/tmp/tns.txt
docker exec -u root ora_standby bash -c "cat /tmp/tns.txt >> /opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora"
```

🔵 Keylor hace lo mismo con `ora_principal` en lugar de `ora_standby`.

## 🟢 Paso 8. Permitir conexiones a la standby aunque esté apagada a medias (listener)

Solo en **su** PC:

```powershell
docker cp sql\07_Standby_y_RMAN\docker\listener_standby.ora ora_standby:/tmp/listener_standby.ora
docker exec -u root ora_standby bash -c "cat /tmp/listener_standby.ora >> /opt/oracle/oradata/dbconfig/CADENA/listener.ora"
docker exec -u oracle ora_standby lsnrctl reload
docker exec -u oracle ora_standby bash -c "lsnrctl status | grep CADENA_STBY"
```

Debe aparecer `Service "CADENA_STBY"`.

## 🟢 Paso 9. Probar la conexión hacia la principal

```powershell
docker exec -u oracle ora_standby tnsping PRIMARIA_TNS
docker exec -u oracle ora_standby tnsping STANDBY_TNS
```

Los dos deben terminar en `OK (xx msec)`. Si `PRIMARIA_TNS` falla, revise el paso 6
(firewall de Keylor) y que el contenedor de Keylor esté encendido.

## 🔵 Paso 10. Keylor prepara la principal y le envía el respaldo (solo esta vez)

Esto lo hace **Keylor** en su PC (instrucciones completas en `docs/GUIA_PASO_A_PASO.md`, sección 7):

1. Instala el proyecto y ejecuta `sql/07_Standby_y_RMAN/01_Configuracion_Primaria_Redo_Archive.sql` (2 veces).
2. Saca el respaldo y los archivos para la standby. Entra a su contenedor:

   ```powershell
   docker exec -it -u oracle ora_principal bash
   ```

   y dentro del contenedor:

   ```bash
   mkdir -p /opt/oracle/backups /opt/oracle/logs
   cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
   NIVEL_BACKUP=0 bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh backup /opt/oracle/oradata/CADENA/archive_logs x /opt/oracle/backups /tmp/stby_bk 3 CADENA $ORACLE_HOME 10
   sqlplus -s / as sysdba <<'EOF'
   CREATE PFILE='/opt/oracle/backups/initCADENA_STBY.ora' FROM SPFILE;
   EOF
   cp /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA /opt/oracle/backups/
   exit
   ```

   De vuelta en PowerShell, saca la carpeta del contenedor:

   ```powershell
   docker cp ora_principal:/opt/oracle/backups .\respaldo_para_standby
   ```

3. Le pasa la carpeta `respaldo_para_standby` (~700 MB) por una **carpeta compartida de
   Windows**, una **memoria USB** o Google Drive.

## 🟢 Paso 11. Recibir el respaldo y preparar la standby

1. Copie la carpeta recibida a su PC, por ejemplo en `C:\respaldo_para_standby`, y pásela al contenedor:

   ```powershell
   docker exec -u root ora_standby bash -c "mkdir -p /opt/oracle/standby_backups /opt/oracle/standby_archive /opt/oracle/logs"
   docker cp C:\respaldo_para_standby\. ora_standby:/opt/oracle/standby_backups/
   docker exec -u root ora_standby bash -c "chown -R oracle:oinstall /opt/oracle/standby_backups /opt/oracle/standby_archive /opt/oracle/logs"
   ```

2. Copie el proyecto dentro del contenedor (lo necesitan los scripts):

   ```powershell
   docker cp . ora_standby:/opt/oracle/proyecto
   docker exec -u root ora_standby chown -R oracle:oinstall /opt/oracle/proyecto
   ```

   > **Cada vez que actualice el repositorio** (`git pull`), repita estos dos comandos: los scripts que usan los jobs y el orquestador son la copia que está **dentro** del contenedor. Con una copia vieja, un respaldo nivel 0 puede saltarse archivos (`BACKUP OPTIMIZATION ON`) y la reconstrucción de la standby falla con `RMAN-06023`.

3. Entre al contenedor:

   ```powershell
   docker exec -it -u oracle ora_standby bash
   ```

   **Desde aquí los comandos se escriben dentro del contenedor** (el símbolo cambia a algo como `bash-4.4$`).

4. Ajuste el archivo de parámetros para que esta base sea la *standby*:

   ```bash
   cd /opt/oracle/standby_backups
   sed -i "/^CADENA\.__/d; /^\*\.db_unique_name/d; /^\*\.fal_server/d; /^\*\.log_archive_dest_2/d" initCADENA_STBY.ora
   cat >> initCADENA_STBY.ora <<'EOF'
   *.db_unique_name='CADENA_STBY'
   *.fal_server='PRIMARIA_TNS'
   *.log_archive_dest_2='SERVICE=PRIMARIA_TNS ASYNC NOAFFIRM VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=CADENA'
   EOF
   ```

5. Borre la base inicial de **su** contenedor y arranque la instancia con esos parámetros.
   ⚠️ Esto se hace **solo en `ora_standby`**, nunca en la PC de Keylor.

   ```bash
   sqlplus -s / as sysdba <<< "SHUTDOWN ABORT"
   rm -rf /opt/oracle/oradata/CADENA/*
   mkdir -p /opt/oracle/oradata/CADENA/archive_logs
   cp /opt/oracle/standby_backups/orapwCADENA /opt/oracle/oradata/dbconfig/CADENA/orapwCADENA
   sqlplus -s / as sysdba <<'EOF'
   STARTUP NOMOUNT PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   CREATE SPFILE='/opt/oracle/oradata/dbconfig/CADENA/spfileCADENA.ora' FROM PFILE='/opt/oracle/standby_backups/initCADENA_STBY.ora';
   SHUTDOWN IMMEDIATE;
   STARTUP NOMOUNT;
   SHOW PARAMETER db_unique_name
   EOF
   ```

   Debe mostrar `db_unique_name ... CADENA_STBY`. (El mensaje `ORA-01507: database not mounted` es normal.)

   > **Si el contenedor se detiene al hacer `SHUTDOWN ABORT`** (pasa con la imagen `enterprise:21.3.0.0` en Docker Desktop de Windows) y el bloque no termina: haga `docker stop ora_standby`, vacíe su volumen con `docker run --rm -u root -v ora_standby_data:/opt/oracle/oradata --entrypoint bash container-registry.oracle.com/database/enterprise:21.3.0.0 -c "rm -rf /opt/oracle/oradata/CADENA/*; mkdir -p /opt/oracle/oradata/CADENA/archive_logs; chown -R oracle:oinstall /opt/oracle/oradata/CADENA"` y luego `docker start ora_standby`. La instancia queda en `NOMOUNT`: espere cerca de 1 minuto (hasta ver `ORA-01507` en `docker logs ora_standby`) antes del paso 12 y compruebe `SELECT status FROM v$instance;` (`STARTED`). Si `SHOW PARAMETER log_archive_config` sale vacío: `ALTER SYSTEM SET log_archive_config='DG_CONFIG=(CADENA,CADENA_STBY)' SCOPE=BOTH;` y `ALTER SYSTEM SET standby_file_management=AUTO SCOPE=BOTH;`.

   > Desde ahora la clave de `SYS` en su base es **la de Keylor** (se copió su archivo de claves).

## 🟢 Paso 12. Crear la standby (≈ 4 minutos)

Sigue dentro del contenedor:

```bash
cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh crearstandby x /opt/oracle/standby_archive x /opt/oracle/standby_backups 3 CADENA $ORACLE_HOME 10
```

Debe terminar con `[OK] RMAN finalizo correctamente`. Compruebe:

```bash
sqlplus -s / as sysdba <<< "SELECT database_role, open_mode, db_unique_name FROM v\$database;"
```

Resultado esperado: `PHYSICAL STANDBY   MOUNTED   CADENA_STBY`.

## 🟢 Paso 13. Encender la sincronización automática (Data Guard)

```bash
sqlplus -s / as sysdba <<< "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;"
```

🔵 Keylor fuerza un cambio de log en la principal (dentro de su contenedor: `docker exec -it -u oracle ora_principal bash`):

```bash
sqlplus -s / as sysdba <<'EOF'
ALTER SYSTEM ARCHIVE LOG CURRENT;
SELECT dest_id, status, error, gap_status FROM v$archive_dest_status WHERE dest_id = 2;
EOF
```

Debe decir `VALID` y `NO GAP`.

🟢 Usted comprueba que recibe y aplica:

```bash
sqlplus -s / as sysdba <<'EOF'
SELECT process, status, sequence# FROM v$managed_standby WHERE process IN ('MRP0','RFS');
SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';
EOF
```

Resultado esperado: `MRP0 APPLYING_LOG` (o `WAIT_FOR_LOG`) y `transport lag` / `apply lag` en `+00 00:00:00`.

**¡Listo! Su PC ya es la standby.** Escriba `exit` para salir del contenedor.

## 🟢🔵 Paso 14. Dejar todo automático (respaldo diario incluido)

El enunciado pide que el respaldo diario llegue **solo** a la standby. Desde aquí ya no se usan
USB ni carpetas: el respaldo viaja por la misma conexión de Oracle (puerto 1521).

1. 🟢 Usted deja su standby **abierta en solo lectura** (así puede recibir los archivos):
   `powershell -ExecutionPolicy Bypass -File .\menu.ps1` → opción **2**. Debe decir `READ ONLY WITH APPLY`.
2. 🟢🔵 Los dos le ponen clave al usuario `oracle` de su contenedor (la misma clave en las dos PC):

   ```powershell
   docker exec -it -u root ora_standby passwd oracle      # usted
   docker exec -it -u root ora_principal passwd oracle    # Keylor
   ```

3. 🔵 Keylor registra esa clave y crea el enlace (sección 7 de `GUIA_PASO_A_PASO.md`,
   "Respaldo diario trasladado solo a la standby").

Desde entonces, cada noche a la 01:00 la principal saca el respaldo y lo deja en su carpeta
`/opt/oracle/standby_backups`, sin que nadie haga nada. Para verlo:
`docker exec ora_standby ls -la /opt/oracle/standby_backups`.

> El paso 10 (pasar el respaldo a mano) solo se hace **una vez**, para crear la standby.

---

## Uso diario

> **Atajo:** todo lo de esta sección y de la defensa también se hace con el menú:
> `powershell -ExecutionPolicy Bypass -File .\menu.ps1` (opción 2 = arrancar la standby,
> 1 = estado, 5 = mostrar datos, 7 = abrir como principal, 8 = failover). Ver el README.
> Para ensayar la defensa juntos, sigan [docs/PRUEBAS_STANDBY.md](PRUEBAS_STANDBY.md).
> Las opciones 11 (correos de destino) y 12 (clave de Gmail) se usan en la principal; si después
> de un failover su PC queda como principal, también puede usarlas usted.

**Cada vez que encienda la PC o reinicie Docker**, la imagen de Oracle **no** levanta sola una
standby. Haga esto:

```powershell
docker start ora_standby
docker exec -it -u oracle ora_standby bash
```

y dentro del contenedor:

```bash
sqlplus -s / as sysdba <<'EOF'
STARTUP MOUNT;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
SELECT database_role, open_mode FROM v$database;
EOF
```

Si `STARTUP MOUNT` responde `ORA-01081: cannot start already-running ORACLE`, la base ya estaba
arriba: no pasa nada, los otros dos comandos igual se aplican.

**Ver el estado** (dentro del contenedor):

```bash
sqlplus -s / as sysdba <<'EOF'
SELECT database_role, open_mode FROM v$database;
SELECT name, value FROM v$dataguard_stats WHERE name LIKE '%lag';
EOF
```

---

## En la defensa: qué le toca a usted

Guion completo: `docs/manuales/Manual_Administracion_Standby.md`, sección 12, y `docs/GUIA_DEFENSA.md`.

### Mostrar que los datos llegan (sincronización)

1. 🔵 Keylor crea un dato en la principal (por ejemplo una factura) y hace `ALTER SYSTEM ARCHIVE LOG CURRENT;`.
2. 🟢 Usted abre la standby en modo lectura **sin dejar de aplicar cambios**:

   ```bash
   sqlplus -s / as sysdba <<'EOF'
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
   ALTER DATABASE OPEN READ ONLY;
   ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
   SELECT database_role, open_mode FROM v$database;
   ALTER SESSION SET CONTAINER = PDBCADENA;
   SELECT COUNT(*) FROM CADENA_NEG.VEN_FACTURA;
   EOF
   ```

   Debe decir `READ ONLY WITH APPLY` y verse el dato nuevo.

### Switchover (cambio planificado de roles)

1. 🔵 Keylor: `ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;` y luego `ALTER DATABASE SWITCHOVER TO CADENA_STBY;`
   (su contenedor se apaga; es normal).
2. 🟢 Usted, que ahora es la principal:

   ```bash
   sqlplus -s / as sysdba <<'EOF'
   ALTER DATABASE OPEN;
   ALTER PLUGGABLE DATABASE ALL OPEN;
   SELECT database_role, open_mode FROM v$database;
   EOF
   ```

   Debe decir `PRIMARY  READ WRITE`.
3. 🔵 Keylor: `docker start ora_principal`, luego `STARTUP MOUNT` y el `RECOVER MANAGED ... DISCONNECT`.
4. Para volver a los roles originales, **usted** ejecuta `ALTER DATABASE SWITCHOVER TO CADENA;`
   y Keylor abre su base (`ALTER DATABASE OPEN; ALTER PLUGGABLE DATABASE ALL OPEN;`).
   Usted reinicia su contenedor y hace los 3 comandos de [Uso diario](#uso-diario).

### Failover (la principal "se destruye")

1. 🔵 Keylor apaga de golpe su servidor: `docker kill ora_principal`.
2. 🟢 Usted toma el control:

   ```bash
   sqlplus -s / as sysdba <<'EOF'
   ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
   ALTER DATABASE FAILOVER TO CADENA_STBY;
   ALTER DATABASE OPEN;
   ALTER PLUGGABLE DATABASE ALL OPEN;
   ALTER PLUGGABLE DATABASE ALL SAVE STATE;
   SELECT database_role, open_mode FROM v$database;
   EOF
   ```

   Ahora su base es la principal (`PRIMARY / READ WRITE`), con todos los datos.
3. Después del failover, la base de Keylor ya no sirve como está: se reconstruye como standby
   de la suya repitiendo los pasos 10-13 **con los roles al revés** (usted saca el respaldo,
   Keylor lo recibe). Ver `GUIA_PASO_A_PASO.md`, sección 7, paso 12.

---

## Problemas frecuentes

| Síntoma | Causa | Solución |
| :--- | :--- | :--- |
| `unauthorized: Auth failed` en `docker login` | Usó la contraseña normal o no aceptó la licencia | Use el **Auth Token** del paso 2 y acepte la licencia de *enterprise*. |
| El contenedor se cierra o `docker logs` muestra errores de memoria | Poca RAM para Docker | Cierre programas; en Docker Desktop → *Settings → Resources* asigne al menos 4 GB. |
| `tnsping PRIMARIA_TNS` → `TNS-12535` / `TNS-12541` | Firewall, IP equivocada o contenedor de Keylor apagado | Repita el paso 6 en **las dos** PC; `Test-NetConnection <IP> -Port 1521`; confirme las IP con `ipconfig`. |
| `TNS-12514` al conectar a `STANDBY_TNS` | Falta el registro estático del listener | Repita el paso 8. |
| `ORA-01017` / `ORA-16191` (clave) | El archivo de claves no es el de la principal | Repita la copia de `orapwCADENA` del paso 11.5. |
| En la principal `v$archive_dest_status` dice `ERROR` | La principal no alcanza la standby | Paso 9 desde el contenedor de Keylor: `tnsping STANDBY_TNS`. Luego Keylor: `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=DEFER;`, después `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=ENABLE;` y `ALTER SYSTEM ARCHIVE LOG CURRENT;` (solo `ENABLE` no siempre basta). Debe quedar `VALID` y `NO GAP`. Si sigue `ORA-16047`, revise `db_unique_name` y `log_archive_config` de su standby. |
| `ORA-01034: ORACLE not available` después de reiniciar | La imagen no levanta la standby sola | Comandos de [Uso diario](#uso-diario). |
| `apply lag` crece y no baja | La sincronización está detenida | Ejecute el `RECOVER MANAGED ... DISCONNECT` de nuevo. |
| Cambió la IP de alguna PC | Wi-Fi/DHCP | Vuelva a editar las entradas del paso 7 (en `/opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora`) en las dos PC. |
