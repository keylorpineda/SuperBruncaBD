# Contenedores Docker para Data Guard (Oracle 21c EE)

Esta carpeta tiene lo necesario para levantar la principal y la standby en Docker con la imagen `container-registry.oracle.com/database/enterprise:21.3.0.0`. El procedimiento completo de Data Guard está en la sección 11 de `docs/manuales/Manual_Administracion_Standby.md` y el resumen en la sección 7 de `docs/GUIA_PASO_A_PASO.md`.

| Archivo | Para qué |
| :--- | :--- |
| `oracle_ee.env` | Clave y datos de la base. **Lo crea usted** (no se sube: está en `.gitignore`). |
| `tnsnames_dataguard.ora` | Entradas `PRIMARIA_TNS` y `STANDBY_TNS`. Van en los **dos** contenedores. |
| `listener_standby.ora` | Servicio estático `CADENA_STBY`. Va **solo** en la standby. |

## 1. Crear `oracle_ee.env`

Cree `sql/07_Standby_y_RMAN/docker/oracle_ee.env` con este contenido (la misma clave para las dos bases):

```
ORACLE_PWD=<su clave>
ORACLE_SID=CADENA
ORACLE_PDB=PDBCADENA
INIT_SGA_SIZE=1024
INIT_PGA_SIZE=300
ENABLE_ARCHIVELOG=true
```

## 2. Levantar los dos contenedores

Desde la raíz del repositorio (antes: `docker login container-registry.oracle.com` y aceptar la licencia, ver la guía paso a paso):

1. Crear la red:

   ```powershell
   docker network create oranet
   ```

2. Crear la principal y la standby:

   ```powershell
   docker run -d --name ora_principal --hostname ora-principal --network oranet --memory 2560m --shm-size 1g --env-file sql/07_Standby_y_RMAN/docker/oracle_ee.env -v ora_principal_data:/opt/oracle/oradata -p 1531:1521 container-registry.oracle.com/database/enterprise:21.3.0.0
   docker run -d --name ora_standby --hostname ora-standby --network oranet --memory 2560m --shm-size 1g --env-file sql/07_Standby_y_RMAN/docker/oracle_ee.env -v ora_standby_data:/opt/oracle/oradata -p 1532:1521 container-registry.oracle.com/database/enterprise:21.3.0.0
   ```

3. Esperar `DATABASE IS READY TO USE!` en cada una (la primera vez, 15 a 20 minutos):

   ```powershell
   docker logs -f ora_principal
   docker logs -f ora_standby
   ```

En dos PC distintas: cree solo un contenedor en cada PC, sin `--network oranet` y con `-p 1521:1521`, y cambie `ora-principal` / `ora-standby` por las IP reales en `tnsnames_dataguard.ora`.

## 3. Aplicar los archivos de red

Los archivos de red de la imagen están en `/opt/oracle/oradata/dbconfig/CADENA/` (el `ORACLE_HOME` es de solo lectura). Se agregan al final con `cat >>` como `root`:

1. `tnsnames_dataguard.ora` en los **dos** contenedores:

   ```powershell
   docker cp sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora ora_principal:/tmp/
   docker exec -u root ora_principal bash -c "cat /tmp/tnsnames_dataguard.ora >> /opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora"
   docker cp sql/07_Standby_y_RMAN/docker/tnsnames_dataguard.ora ora_standby:/tmp/
   docker exec -u root ora_standby bash -c "cat /tmp/tnsnames_dataguard.ora >> /opt/oracle/oradata/dbconfig/CADENA/tnsnames.ora"
   ```

2. `listener_standby.ora` **solo** en la standby, y recargar el listener:

   ```powershell
   docker cp sql/07_Standby_y_RMAN/docker/listener_standby.ora ora_standby:/tmp/
   docker exec -u root ora_standby bash -c "cat /tmp/listener_standby.ora >> /opt/oracle/oradata/dbconfig/CADENA/listener.ora"
   docker exec -u oracle ora_standby lsnrctl reload
   ```

3. Comprobar (las dos deben terminar en `OK`):

   ```powershell
   docker exec -u oracle ora_principal tnsping STANDBY_TNS
   docker exec -u oracle ora_standby tnsping PRIMARIA_TNS
   ```

Haga cada `cat >>` **una sola vez**: si lo repite, las entradas quedan duplicadas y hay que limpiarlas a mano.
