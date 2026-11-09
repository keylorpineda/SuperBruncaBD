# Guía del padrón del TSE (el "dataset" del proyecto)

## 1. Qué es

El padrón nacional electoral es la lista oficial de personas con cédula que publica el **Tribunal Supremo de Elecciones (TSE)**. El TSE lo actualiza **cada mes** en:

https://www.tse.go.cr/descarga_padron.html

Se descarga un solo archivo, `padron_completo.zip` (unos **74 MB**), que trae:

| Archivo | Contenido |
| :--- | :--- |
| `PADRON_COMPLETO.txt` | Una línea por persona: **3.762.240 personas** en el padrón del 30/09/2026. |
| `DISTELEC.txt` | Los **2.179 distritos electorales** (provincia, cantón y distrito de cada código electoral). |
| `LEAME.txt` | La descripción oficial del formato. |

El proyecto lo carga en la tabla `CADENA_NEG.CAT_PADRON` (y los distritos en `CAT_DISTRITO_ELECTORAL`), y la tabla de clientes se enlaza a ella para tomar el nombre de la persona a partir de su cédula.

---

## 2. Dónde va el archivo

**No va en el repositorio.** Descomprimido pesa unos 450 MB y cambia cada mes.

Va en la carpeta del directorio Oracle **`DIR_PADRON`** del servidor (la PC 1). El instalador crea ese directorio apuntando a la carpeta del tablespace `SYSTEM` del PDB. Para ver cuál es:

```sql
SELECT directory_path FROM all_directories WHERE directory_name = 'DIR_PADRON';
```

En el contenedor `ora_principal` (Oracle 21c EE) es `/opt/oracle/oradata/CADENA/PDBCADENA`.

Ahí deben quedar `PADRON_COMPLETO.txt` y `DISTELEC.txt`, **con esos nombres exactos** (las tablas externas los buscan así).

---

## 3. Cómo descargarlo

Los scripts de descarga están en `datos/padron/`. Bajan el ZIP, lo descomprimen y dejan los archivos con el nombre correcto en la carpeta que usted indique.

**Windows** (PowerShell):

```powershell
.\datos\padron\Descargar_Padron_TSE.ps1 -Destino <carpeta de DIR_PADRON>
```

**Linux o Docker** (el `.sh` recibe la URL y la carpeta):

```bash
./Descargar_Padron_TSE.sh <url> <carpeta>
```

En Docker, con el repositorio ya copiado en `/opt/oracle/proyecto`:

```powershell
docker exec -it -u oracle ora_principal bash /opt/oracle/proyecto/datos/padron/Descargar_Padron_TSE.sh https://www.tse.go.cr/zip/padron/padron_completo.zip /opt/oracle/oradata/CADENA/PDBCADENA
```

El `.sh` necesita `curl` o `wget`, y `unzip` o `python3`. Si la descarga automática falla, baje el ZIP a mano desde la página del TSE, descomprímalo y cópielo al contenedor:

```powershell
docker cp PADRON_COMPLETO.txt ora_principal:/opt/oracle/oradata/CADENA/PDBCADENA/
docker cp DISTELEC.txt        ora_principal:/opt/oracle/oradata/CADENA/PDBCADENA/
docker exec -u root ora_principal chown oracle:oinstall /opt/oracle/oradata/CADENA/PDBCADENA/PADRON_COMPLETO.txt /opt/oracle/oradata/CADENA/PDBCADENA/DISTELEC.txt
```

---

## 4. Cómo cargarlo

Conectado como SYSDBA en el PDB `PDBCADENA` (o como `CADENA_NEG`). En Docker: `docker exec -it -u oracle ora_principal sqlplus / as sysdba` y luego `ALTER SESSION SET CONTAINER = PDBCADENA;`.

```sql
SET SERVEROUTPUT ON
EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;
```

Qué hace:

1. Lee los dos archivos con las **tablas externas** `EXT_PADRON_TSE` y `EXT_DISTELEC_TSE` (juego de caracteres Latin-1, que es el del TSE). No copia los archivos: Oracle los lee directamente.
2. Carga los distritos y luego hace un **`MERGE` por provincia** en `CAT_PADRON`. En las cargas mensuales siguientes solo reescribe a las personas que cambiaron.

Primera prueba (Oracle 26ai Free en Docker, sin Data Guard, padrón del 30/09/2026): **3.762.240 personas, 0 rechazos**, unos **39 minutos**.

> **Verificado en Oracle 21c EE con Data Guard activo:** padrón del 30/09/2026, 3.762.240 personas, 0 rechazos, 2.179 distritos electorales, ~52 minutos (más lento que sin Data Guard porque cada cambio viaja también a la standby). Al terminar, la standby seguía sincronizada: `transport lag` y `apply lag` en 0 y `GAP_STATUS = NO GAP`.

Con Data Guard activo, la carga se replica sola a la standby (la tabla `CAT_PADRON` viaja en el redo); los archivos `.txt` no (ver la sección 10 del Manual del Standby).

Las líneas rechazadas quedan en `padron_tse.bad` y el detalle en `padron_tse.log`, en la misma carpeta de `DIR_PADRON`.

---

## 5. Cómo consultarlo

```sql
SELECT * FROM CADENA_NEG.V_PADRON_DETALLE WHERE cedula_padr = '<cédula de 9 dígitos>';
SELECT COUNT(*) FROM CADENA_NEG.CAT_PADRON;
```

La vista `V_PADRON_DETALLE` junta a la persona con su provincia, cantón y distrito.

Para crear un cliente a partir del padrón: `CADENA_NEG.PKG_PER_PADRON.PR_CREAR_CLIENTE_DESDE_PADRON` (recibe la cédula y el código del cliente).

---

## 6. Formato oficial de `PADRON_COMPLETO.txt`

Campos separados por comas, en este orden (longitud según `LEAME.txt`):

| # | Campo | Longitud | Se guarda en |
| :--- | :--- | :--- | :--- |
| 1 | `CEDULA` | 9 | `CEDULA_PADR` |
| 2 | `CODELEC` (código electoral) | 6 | `COD_ELECTORAL_PADR` (se une con `DISTELEC.txt`) |
| 3 | `RELLENO` | 1 | (no se usa) |
| 4 | `FECHACADUC` (vencimiento de la cédula) | 8 | `FECHA_VENC_CED_PADR` |
| 5 | `JUNTA` | 5 | (no se usa) |
| 6 | `NOMBRE` | 30 | `NOMBRE_PADR` |
| 7 | `1.APELLIDO` | 26 | `APELLIDO1_PADR` |
| 8 | `2.APELLIDO` | 26 | `APELLIDO2_PADR` |

**Por qué el sexo queda en `N`:** el TSE no publica el sexo de las personas; el campo 3 es solo relleno. Por eso `SEXO_PADR` se guarda como `N` (no indicado).

---

## 7. Actualización automática cada mes

El job **`JOB_PADRON_MENSUAL`** se ejecuta el día `PADRON_DIA_CARGA` de cada mes (por defecto el **5**, a las **02:00**). Llama a `JOB_PADRON_DESCARGA`, que corre el script de descarga, y luego recarga el padrón.

- La descarga automática es un job del sistema operativo, así que necesita la **credencial del SO** (`PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS`, ver la Guía paso a paso, sección 6.2). Sin ella, el job mensual recarga lo que ya esté en `DIR_PADRON`.
- La ruta del script está en el parámetro `PADRON_SCRIPT_DESCARGA` (por defecto `/opt/oracle/proyecto/datos/padron/Descargar_Padron_TSE.sh` o `C:\app\oracle\proyecto\datos\padron\Descargar_Padron_TSE.ps1`).
- Para cambiar el día:

  ```sql
  EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('PADRON_DIA_CARGA', 'NEGOCIO', 'Dia del mes de la carga del padron', 'Dia (1-28) en que JOB_PADRON_MENSUAL descarga y carga el padron vigente.', 'N', NULL, 10);
  EXEC CADENA_NEG.PKG_PER_PADRON.PR_CONFIGURAR_JOBS_PADRON;
  ```

---

## 8. Archivos de prueba (no son el padrón real)

- `datos/padron/padron_muestra.csv`: unas pocas personas inventadas, para probar la lectura de archivos.
- `PADRON_PRUEBA.TXT`: lo genera la suite de pruebas del instalador (`PR_GENERAR_ARCHIVO_PADRON_TSE`) y lo carga con `PR_CARGAR_PADRON_TSE`. Sirve para que las 12 pruebas pasen sin el padrón completo.

Para la defensa hay que cargar el **padrón real** (el enunciado pide la información actual).

---

## 9. Errores frecuentes

| Error | Causa | Solución |
| :--- | :--- | :--- |
| `ORA-29913` + `KUP-04040: file PADRON_COMPLETO.txt in DIR_PADRON not found` | El archivo no está en la carpeta de `DIR_PADRON`, o tiene otro nombre. | Revise la carpeta con la consulta de la sección 2 y que el nombre sea exactamente `PADRON_COMPLETO.txt` (y `DISTELEC.txt`). |
| `KUP-04001` / `KUP-04063` (no se puede abrir o leer) | El usuario `oracle` del SO no tiene permiso sobre el archivo. | En Docker: `docker exec -u root ora_principal chown oracle:oinstall <carpeta>/PADRON_COMPLETO.txt <carpeta>/DISTELEC.txt`. |
| Nombres con caracteres raros (tildes, ñ) | El archivo se convirtió a otro juego de caracteres al copiarlo. | Use el archivo tal como viene del ZIP (Latin-1), sin abrirlo y guardarlo con otro editor. |
| Muchas líneas en `padron_tse.bad` | El archivo está incompleto o no es el oficial. | Vuelva a descargar el ZIP. |
| `[ERROR] Se necesita unzip o python3` | El contenedor no tiene con qué descomprimir. | Descomprima en su PC y copie los `.txt` con `docker cp` (sección 3). |
| `JOB_PADRON_DESCARGA` aparece deshabilitado con estado `SUCCEEDED` | Es normal: no tiene horario propio, se ejecutó una vez al habilitarse y `JOB_PADRON_MENSUAL` lo vuelve a lanzar con `RUN_JOB`. | Nada. |
| `JOB_PADRON_DESCARGA` sin credencial o `FAILED` | Falta la credencial del SO o no hay internet en el servidor. | Registre la credencial (Guía paso a paso, 6.2) o descargue a mano. |
