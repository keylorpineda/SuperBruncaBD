# Pruebas del standby (ensayo y defensa)

Hoja para probar el standby **con las dos computadoras reales** antes de la defensa y para
seguirla el día de la revisión. Cada prueba dice qué demuestra, qué opción del menú usar, el
comando equivalente (el menú lo muestra en pantalla antes de ejecutarlo) y qué debe salir.

- **PC 1 (Keylor):** principal, contenedor `ora_principal`, base `CADENA`.
- **PC 2 (Diego):** standby, contenedor `ora_standby`, base `CADENA_STBY`.
- **Menú** (en la carpeta del proyecto, en cada PC):

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\menu.ps1
  ```

Marque cada casilla cuando la prueba salga como dice "Debe salir". Si algo falla, busque el
síntoma en la sección 13.2 del [Manual del Standby](manuales/Manual_Administracion_Standby.md).

---

## Antes de empezar (5 minutos)

- [ ] **Las dos PC en la misma red.** Desde la PC 1: `ping <IP de la PC 2>`. Si el Wi-Fi de la
  universidad no deja que se vean, conecten las dos al punto de acceso de un celular.
- [ ] **Docker encendido en las dos** y los contenedores arriba: `docker ps` muestra `(healthy)`.
- [ ] **PC 2: opción 2** (arranca la standby y la deja en solo lectura aplicando cambios).
- [ ] **PC 1: opción 11** con el correo que indique el profesor (y correo de prueba).
- [ ] **Las dos: opción 14** (comprobar conexión): debe terminar en **CONECTADAS**.
- [ ] **Las dos: opción 1.** Debe salir en la PC 1 `Envio a la otra PC (destino 2): VALID huecos: NO GAP`
  y en la PC 2 `Retraso transport: +00 00:00:00` y `Retraso apply: +00 00:00:00` (o pocos segundos).

---

## 1. Son dos servidores distintos

**Demuestra:** la principal y la standby son dos bases en dos computadoras.

| Dónde | Menú | Debe salir |
| :--- | :-: | :--- |
| PC 1 | 1 | `Nombre: CADENA   Rol: PRIMARY   Modo: READ WRITE` |
| PC 2 | 1 | `Nombre: CADENA_STBY   Rol: PHYSICAL STANDBY   Modo: READ ONLY WITH APPLY` |

```sql
SELECT db_unique_name, database_role, open_mode FROM v$database;
```

- [ ] Hecho

## 2. Cambio de archivo cada 5 minutos o 50 MB

**Demuestra:** el redo de 50 MB y el cambio forzado cada 5 minutos (requisito parametrizado).
**PC 1, opción 10** (consola SYSDBA):

```sql
SELECT group#, members, bytes/1024/1024 AS mb, status FROM v$log;
SHOW PARAMETER archive_lag_target
SHOW PARAMETER log_archive_dest_2
```

**Debe salir:** grupos de `50` MB con 2 miembros, `archive_lag_target` = `300` (segundos) y el
destino 2 con `SERVICE=STANDBY_TNS ASYNC ... DB_UNIQUE_NAME=CADENA_STBY`.

- [ ] Hecho

## 3. Todo lo parametrizado está en una tabla

**PC 1, opción 9** (consola del proyecto):

```sql
SELECT codigo_para, valor_num_para, valor_texto_para
  FROM SEG_PARAMETRO WHERE codigo_para LIKE 'STANDBY%' ORDER BY 1;
```

**Debe salir:** `STANDBY_SWITCH_MIN` 5, `STANDBY_SWITCH_MB` 50, `STANDBY_SYNC_MIN` 10,
`STANDBY_PURGE_DIAS` 3, `STANDBY_HORA_BACKUP` 1 y las rutas.

- [ ] Hecho

## 4. Lo que se hace en la principal aparece en la standby

**Demuestra:** sincronización automática en tiempo real.

**PC 1, opción 9:**

```sql
-- Solo la primera vez:
CREATE TABLE CADENA_NEG.PRUEBA_STANDBY (id NUMBER, nota VARCHAR2(100), fecha DATE DEFAULT SYSDATE);

INSERT INTO CADENA_NEG.PRUEBA_STANDBY (id, nota) VALUES (1, 'Dato escrito en vivo en la defensa');
COMMIT;
```

**PC 2, opción 9** (la standby está en solo lectura, así que solo se consulta):

```sql
SELECT * FROM CADENA_NEG.PRUEBA_STANDBY;
```

**Debe salir:** la fila, a los pocos segundos. Para mostrarlo con datos del negocio, haga una venta
con el bloque A de la [guía de la defensa](GUIA_DEFENSA.md) y en la PC 2 use la **opción 5**
(muestra las últimas facturas replicadas).

- [ ] Hecho

## 5. Sincronizar cuando el profesor lo pida

**Demuestra:** "debe existir la forma de generarlo en el momento que el académico lo decida".

| Dónde | Menú | Comandos que ejecuta |
| :--- | :-: | :--- |
| PC 1 | 3 | `ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = ENABLE`, `ALTER SYSTEM ARCHIVE LOG CURRENT` |

Equivalente con el paquete del proyecto (corre el job de traslado en ese momento):

```sql
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
```

**Debe salir:** `Destino 2: VALID   huecos: NO GAP`. En la PC 2, opción 1: retraso 0.

- [ ] Hecho

## 6. Se cae la standby y se recupera sola

**Demuestra:** monitoreo, aviso al DBA y que la principal no se detiene.

1. **PC 2:** `docker stop ora_standby`
2. **PC 1:** haga otra inserción (prueba 4) y `COMMIT`: la principal sigue trabajando.
3. **PC 1, opción 1** (espere 1 a 5 minutos): el destino 2 pasa a `ERROR` (por ejemplo `ORA-12541` o `ORA-03113`).
4. **PC 1, opción 13 → 9** (revisión del standby): llega al correo del DBA la alerta con la etiqueta roja.
5. **PC 2, opción 2:** la standby arranca y Data Guard le manda lo que le faltó.
6. **PC 1, opción 3** y luego **opción 1:** `VALID` y `NO GAP`. **PC 2, opción 9:** aparece la fila del paso 2.

- [ ] Hecho

## 7. Respaldo a petición, trasladado a la standby

**Demuestra:** respaldo RMAN diario automático que también se puede pedir en el momento.

```sql
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;
```

(o **opción 4** del menú, que corre el mismo RMAN y deja el respaldo en la principal).

**Debe salir:** el resultado del job de respaldo (`SUCCEEDED`) y la salida del script. En la PC 2:

```powershell
docker exec ora_standby ls -lh /opt/oracle/standby_backups
```

Deben aparecer las piezas `.bkp` con la fecha de hoy.

- [ ] Hecho

## 8. Restauración comprobada sin dañar nada

**Demuestra:** que el respaldo sirve para restaurar (restore / recovery) sin tener que romper la base.
**PC 1:**

```powershell
docker exec -it -u oracle ora_principal rman target /
```

```
RESTORE DATABASE VALIDATE;
EXIT
```

**Debe salir:** RMAN lee las piezas y termina sin errores. Los escenarios reales de restauración
(archivo dañado y volver a una hora anterior) están en
`sql/07_Standby_y_RMAN/05_RMAN_Restore_Recovery_PointInTime.rman` para explicarlos.

- [ ] Hecho

## 9. Purga de 3 días y jobs

```sql
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;
EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;
```

**Debe salir:** la purga termina; si un archivo no se borra aparece `RMAN-08120` (aún no aplicado
en la standby) o `RMAN-08138` (falta respaldo): es lo correcto. `PR_ESTADO_STANDBY` lista los 4
jobs del standby con su última ejecución `SUCCEEDED`.

- [ ] Hecho

## 10. Switchover (cambio de roles planeado) y regreso

| Paso | Dónde | Menú | Comando que ejecuta |
| :-: | :--- | :-: | :--- |
| 1 | PC 1 | 6 (escribir `SI`) | `ALTER DATABASE SWITCHOVER TO CADENA_STBY VERIFY;` y `ALTER DATABASE SWITCHOVER TO CADENA_STBY;` |
| 2 | PC 2 | 7 | `ALTER DATABASE OPEN;` `ALTER PLUGGABLE DATABASE ALL OPEN;` |
| 3 | PC 1 | 2 | `STARTUP MOUNT`, abre en solo lectura y `RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE` |
| 4 | Las dos | 1 | PC 2 = `PRIMARY / READ WRITE`; PC 1 = `PHYSICAL STANDBY` |

Pruebe al revés: inserte en la **PC 2** (prueba 4) y consulte en la **PC 1**.
Para volver: **PC 2 opción 6**, **PC 1 opción 7**, **PC 2 opción 2**.

- [ ] Ida
- [ ] Vuelta

## 11. Failover (la principal se perdió) — al final de todo

1. **PC 1:** inserte una fila (prueba 4) y `COMMIT`.
2. **Desastre:** `docker kill ora_principal`, o desconecte el cable o el Wi-Fi de la PC 1.
3. **PC 2, opción 8** (escribir `SI`): ejecuta `RECOVER MANAGED STANDBY DATABASE CANCEL`,
   `ALTER DATABASE FAILOVER TO CADENA_STBY` y abre la base.
4. **PC 2, opción 9:** la fila del paso 1 está ahí (0 pérdida de datos).

- [ ] Hecho

## 12. Recuperar la PC 1 como standby después del failover

Toma unos 10 minutos. Si no hay tiempo en la defensa, se explica.
Pasos exactos: sección 11.12 del [Manual del Standby](manuales/Manual_Administracion_Standby.md)
(respaldo nivel 0 en la nueva principal, borrar la base vieja, `crearstandby` y sincronizar).
Después, un switchover (prueba 10) devuelve los roles originales.

- [ ] Hecho

---

## Resultado del ensayo

| Fecha | Red usada (Wi-Fi, hotspot, cable) | Pruebas que fallaron | Qué se corrigió |
| :--- | :--- | :--- | :--- |
| | | | |
