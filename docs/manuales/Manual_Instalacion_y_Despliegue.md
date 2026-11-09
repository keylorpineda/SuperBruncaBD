<div align="center">

# Sede Regional Brunca
## Campus Pérez Zeledón

### Manual de Instalación y Despliegue

**Curso: Administración de bases de datos**  
**Profesor: Hairol Romero Sandi**  
**II Ciclo - Grupo 84**  

**Estudiantes:**  
Diego Bonilla Mora  
Pineda Alvarez Keylor Steven  

Octubre del 2026

</div>

---

# 1. Alcance y Requisitos Previos del Entorno

El presente manual describe paso a paso el procedimiento oficial para la instalación, compilación, aprovisionamiento y verificación integral del **Avance #2** del proyecto de curso.

### 1.1 Requisitos de Hardware y Software
* **Sistema Operativo:** Microsoft Windows 10/11 Pro/Enterprise o GNU/Linux (Ubuntu 22.04 LTS+, Oracle Linux 8/9).
* **Motor de Base de Datos:** **Oracle Database 21c Enterprise Edition** (la versión que pide el enunciado; incluye Data Guard para el Standby), con arquitectura multitenant: CDB `CADENA` y PDB `PDBCADENA` en modo `READ WRITE`. La instalación también funciona en XE o Free, pero el Standby queda en modo manual.
* **Virtualización / Contenedores:** Docker Desktop 4.x+ con motor Linux y la imagen oficial `container-registry.oracle.com/database/enterprise:21.3.0.0` (contenedores `ora_principal` y `ora_standby`, ver `sql/07_Standby_y_RMAN/docker/README.md`), o bien instalación nativa / máquina virtual con Oracle 21c EE.
* **Herramientas de Conexión:**
  * Oracle SQL\*Plus (versión 21c+).
  * Oracle SQL Developer 23.x+ o DBeaver Community.
  * Oracle Recovery Manager (`rman`).
* **Intérprete de Comandos:** Windows PowerShell 5.1 / PowerShell 7+ o GNU Bash.
* **Memoria y almacenamiento:** cada contenedor usa hasta 2,5 GB de RAM (`--memory 2560m`, SGA 1024 MB, PGA 300 MB). Mínimo 15 GB libres en disco por base para datafiles, redo logs multiplexados, respaldos RMAN y archivado continuo.

### 1.2 Parámetros de Red y Correo
* **Puerto de Base de Datos:** 1521 TCP (Listener Oracle).
* **Puerto de Envío SMTP:** 465 TCP (SMTPS con SSL / `smtp.gmail.com`); 587 con STARTTLS como alternativa.
* **Destinatario Institucional de Pruebas:** `keylorpineda729@gmail.com` (configurado en `CADENA_NEG.SEG_PARAMETRO` para coordinadores, gerencia y DBA).

---

## 2. Catálogo de Archivos Entregables

La solución se entrega organizada en scripts modulares e independientes, gobernados por un instalador maestro automatizado. Las rutas son relativas a la raíz del repositorio:

| ARCHIVO | TIPO | PROPÓSITO |
| :--- | :--- | :--- |
| `sql/script_bd_v2.sql` | DDL Base | Línea base del Entregable #1 (tablespaces, usuario `CADENA_NEG`, tablas transaccionales y catálogos). Se ejecuta antes del maestro. |
| `sql/00_Master_Instalacion_Avance2.sql` | SQL Maestro | Orquestador de instalación integral en orden determinista. |
| `sql/01_Estructuras_Avance2.sql` | DDL / DML | 11 tablas nuevas, secuencias, índices, 2 MV y datos semilla. |
| `sql/02_Paquetes_Seguridad_Auditoria_Notificaciones.sql` | PL/SQL | Seguridad AES-256, auditoría autónoma y correo UTL_SMTP. |
| `sql/03_Paquetes_Negocio_Monitoreo.sql` | PL/SQL | Padrón TSE, inventario, compras, ventas, mercadeo y salud. |
| `sql/04_Triggers_Negocio_y_Auditoria.sql` | PL/SQL | 11 triggers de negocio y 7 triggers de bitácora profunda. |
| `sql/05_Seguridad_Perfiles_Roles_Usuarios.sql` | SQL / DCL | Perfiles, 4 roles con clave cifrada, usuarios y pruebas de mínimos privilegios. |
| `sql/06_Scheduler_Optimizacion_y_Pruebas.sql` | PL/SQL | 5 Jobs DBMS_SCHEDULER, EXPLAIN PLAN y 12 suites de prueba de extremo a extremo. |
| `sql/07_Standby_y_RMAN/` | Directorio | Configuración de la principal (redo 50 MB / 5 min), creación y sincronización de la standby en la segunda PC, RMAN, purga, switchover y failover. |
| `sql/07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql` | PL/SQL | Paquete `PKG_ADM_STANDBY` y 4 jobs DBMS_SCHEDULER: traslado cada 10 min, respaldo RMAN diario, purga de 3 días y monitoreo. |
| `sql/07_Standby_y_RMAN/docker/` | Configuración | `README.md` para levantar los contenedores `ora_principal` y `ora_standby`, y los archivos de red de Data Guard `tnsnames_dataguard.ora` y `listener_standby.ora`. El archivo local `oracle_ee.env` (clave) no se versiona. |
| `sql/08_Wallet_SMTP_Gmail.sh` | Script SO | Crea el Oracle Wallet auto-login con los certificados raíz de Gmail para `UTL_SMTP` y registra `SMTP_WALLET_PATH` (Paso 8). |
| `datos/padron/Descargar_Padron_TSE.ps1` / `.sh` | Script SO | Descarga `padron_completo.zip` del TSE y deja `PADRON_COMPLETO.txt` y `DISTELEC.txt` en `DIR_PADRON`. |
| `datos/padron/padron_muestra.csv` | Datos externos | Archivo CSV muestra del padrón electoral para prueba de UTL_FILE. |
| `docs/manuales/` | Documentación | Los 3 manuales oficiales (`.md` y `.pdf`) y `generar_manuales_pdf.py`, que regenera los PDF. |
| `docs/entregable1/` | Documentación | Diccionario de datos, documentación técnica y modelo relacional del Entregable #1. |
| `docs/` (guías) | Documentación | `GUIA_PASO_A_PASO.md`, `GUIA_PADRON_TSE.md` y `GUIA_DEFENSA.md`. |

---

## 3. Procedimiento Oficial de Instalación Automatizada

Los scripts están pensados para poder ejecutarse más de una vez. El instalador maestro detecta el PDB abierto, elimina las estructuras de corridas previas y recrea el ambiente; al terminar, la validación final debe mostrar **0 objetos inválidos** y todos los puntos en `[OK]`.

### Opción A: Despliegue en Contenedor Docker (Recomendado)
Si la base de datos se ejecuta en el contenedor Docker de la principal, `ora_principal` (cómo crearlo: `sql/07_Standby_y_RMAN/docker/README.md`):

1. **Copiar los archivos al contenedor y darle los permisos al usuario `oracle`** (desde la raíz del repositorio):
   ```powershell
   docker cp . ora_principal:/opt/oracle/proyecto
   docker exec -u root ora_principal chown -R oracle:oinstall /opt/oracle/proyecto
   ```

2. **Crear la base del Entregable #1 y ejecutar el instalador maestro como SYSDBA** (desde la carpeta `sql`):
   ```powershell
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql ora_principal sqlplus -s / as sysdba '@script_bd_v2.sql'
   docker exec -i -u oracle -w /opt/oracle/proyecto/sql ora_principal sqlplus -s / as sysdba '@00_Master_Instalacion_Avance2.sql'
   ```

   Verificado en Oracle 21c EE: 0 objetos inválidos y el mensaje `LAS 12 PRUEBAS ... 100% DE EXITO`.

### Opción B: Despliegue desde SQL\*Plus Local o SQL Developer
Si se conecta vía red o mediante cliente local, ubíquese en la carpeta `sql` del repositorio:

```bash
cd sql
sqlplus sys/TuPassword@localhost:1531/PDBCADENA as sysdba @script_bd_v2.sql
sqlplus sys/TuPassword@localhost:1531/PDBCADENA as sysdba @00_Master_Instalacion_Avance2.sql
```

`1531` es el puerto publicado del contenedor `ora_principal`; en una instalación nativa use `1521`.

> **Nota para SQL Developer:** Abra el archivo `sql/00_Master_Instalacion_Avance2.sql` y presione **F5** (*Run Script*), asegurando que la conexión apunte a `PDBCADENA`. El maestro incluye `@@07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql`, que se resuelve respecto de la carpeta `sql`.

---

## 4. Desglose Técnico de los Pasos de Instalación

El script maestro ejecuta de forma consecutiva las siete fases del avance:

### Paso 1: Estructuras DDL, Tablas Nuevas y Vistas Materializadas (`01_Estructuras_Avance2.sql`)
1. Detecta automáticamente el PDB activo (`PDBCADENA`) y conmuta la sesión mediante `ALTER SESSION SET CONTAINER`.
2. Configura el directorio lógico `DIR_PADRON` apuntando a la ruta física de datos para carga de archivos con `UTL_FILE`.
3. Ejecuta limpieza idempotente de tablas, secuencias y vistas materializadas preexistentes.
4. Modifica tablas base del Entregable #1 adicionando columnas de enlace electoral (`ID_PADRON` en `PER_CLIENTE`).
5. Crea las **11 tablas nuevas**:
   * `CAT_PADRON`: Almacenamiento optimizado del padrón electoral nacional.
   * `CAT_DISTRITO_ELECTORAL`: Nombres oficiales de provincia, cantón y distrito electoral (`DISTELEC.txt`).
   * `EXT_PADRON_TSE` y `EXT_DISTELEC_TSE`: Tablas externas (Latin-1) que leen los archivos oficiales del TSE sin copiarlos; vista `V_PADRON_DETALLE`.
   * `SEG_PARAMETRO`: Configuración general del sistema con soporte para valores cifrados en `RAW(2000)`.
   * `COM_CUENTA_PAGAR`: Cuentas por pagar a proveedores derivadas de compras a crédito.
   * `VEN_CUENTA_COBRAR`: Cuentas por cobrar a clientes derivadas de ventas a crédito.
   * `VEN_CIERRE_DIARIO`: Encabezado de cierres contables y operativos diarios por sucursal.
   * `VEN_CIERRE_DIARIO_DET`: Desglose del cierre diario por cajero / usuario operativo.
   * `PRM_DESCUENTO_DET`: Detalle de lotes y productos incluidos en promociones automáticas.
   * `PRM_ORDEN_PREMIACION`: Órdenes de compra otorgadas semestralmente al Top 10 de clientes.
   * `AUD_REGISTRO_CAMBIO`: Bitácora inmutable de cambios (valor anterior vs nuevo, terminal, IP).
   * `AUD_ERROR_SISTEMA`: Registro de errores imprevistos capturados en bloques de excepción.
   * `AUD_MONITOREO_BD`: Registro histórico de salud de la base de datos (tablespaces, índices, objetos).
6. Crea las **2 Vistas Materializadas**:
   * `MV_VENTAS_MENSUALES`: Consolidado de facturas, unidades vendidas y montos netos mensuales.
   * `MV_INVENTARIO_CONSOLIDADO`: Existencias totales por producto, costo promedio y valor total en inventario.
7. Inserta la configuración inicial de parámetros cifrados con AES-256 (`DBMS_CRYPTO`) y los datos semilla (mínimo 5 filas por tabla).

### Paso 2: Paquetes de Seguridad, Auditoría y Notificaciones (`02_Paquetes_Seguridad_Auditoria_Notificaciones.sql`)
1. Compila el paquete `PKG_AUD_CONTROL`:
   * Implementa `PR_REGISTRAR_OPERACION` y `PR_REGISTRAR_ERROR` con `PRAGMA AUTONOMOUS_TRANSACTION`, garantizando que la bitácora persiste incluso si la transacción de negocio hace `ROLLBACK`.
2. Compila el paquete `PKG_SEG_SEGURIDAD`:
   * Implementa cifrado simétrico AES-256 (`ENCRYPT_AES256 + CHAIN_CBC + PAD_PKCS5`) con llave maestra de 256 bits.
   * Gestiona el almacenamiento seguro y descifrado de parámetros sensibles y contraseñas de roles.
   * Proporciona la función `FN_OBTENER_CLAVE_ROL`.
3. Compila el procedimiento público `PRC_ACTIVAR_ROL_SESION` con `AUTHID CURRENT_USER`:
   * Permite a los usuarios autenticados activar sus roles protegidos desencriptando la clave en memoria y ejecutando `DBMS_SESSION.SET_ROLE`.
4. Compila el paquete `PKG_ADM_NOTIFICACION`:
   * Envío directo de correos sin requerir VPN mediante `UTL_SMTP` y comandos EHLO/STARTTLS/AUTH LOGIN.
   * Implementa `PR_NOTIF_CLIENTES_85_CREDITO`, `PR_NOTIF_PROVEEDORES_70_CREDITO`, `PR_NOTIF_CLIENTES_MOROSOS` y `PR_NOTIF_PRODUCTOS_VENCIDOS`.
5. Configura la lista de control de acceso de red (ACL) en el puerto 587 para permitir la salida SMTP desde Oracle.

### Paso 3: Paquetes de Negocio y Monitoreo (`03_Paquetes_Negocio_Monitoreo.sql`)
1. `PKG_PER_PADRON`: Carga masiva del padrón oficial del TSE (`PR_CARGAR_PADRON_MASIVO`, tablas externas y `MERGE` por provincia), carga fila por fila con validación para archivos pequeños (`PR_CARGAR_PADRON_TSE`), actualización mensual automática (`JOB_PADRON_MENSUAL`) y `PR_CREAR_CLIENTE_DESDE_PADRON`.
2. `PKG_INV_GESTION`: Control de inventario con bloqueo pesimista `SELECT FOR UPDATE WAIT 5`, actualización de stock, kardex inmutable y reporte de productos críticos a mercadeo.
3. `PKG_COM_OPERACION`: Facturación de compras a proveedores con registro automático de cuentas por pagar y abonos.
4. `PKG_VEN_OPERACION`: Facturación en punto de venta, control de crédito, abonos de clientes y cierre contable diario consolidado y por cajero (`PR_EJECUTAR_CIERRE_DIARIO`).
5. `PKG_PRM_MERCADEO`: Cálculo de acciones por compra de productos patrocinadores, aplicación de descuentos semanales (`PR_VERIFICAR_DESCUENTOS_SEMANAL`) y premiación semestral de Top 10 clientes con órdenes de ₡100,000 (`PR_PREMIAR_MEJORES_CLIENTES`).
6. `PKG_ADM_MONITOREO`: Inspección automatizada de tablespaces (>85%), detección de objetos inválidos, índices en estado corrupto y crecimiento de sesiones.

### Paso 4: Disparadores de Reglas de Negocio y Auditoría (`04_Triggers_Negocio_y_Auditoria.sql`)
Compila 21 disparadores en estado `ENABLED`:
* **11 Triggers de Negocio:**
  * `TRG_VEN_FACTURA_CRED_BIU`: Bloquea facturas de venta a crédito si superan el límite del cliente.
  * `TRG_COM_FACTURA_CRED_BIU`: Bloquea facturas de compra a crédito si superan el límite del proveedor.
  * `TRG_COM_FACTURA_CRED_AI`: Genera la cuenta por pagar (`COM_CUENTA_PAGAR`) al ingresar una compra a crédito.
  * `TRG_VEN_FACTURA_CRED_AI`: Genera la cuenta por cobrar (`VEN_CUENTA_COBRAR`) al emitir venta a crédito.
  * `TRG_VEN_ABONO_SALDO_AI`: Actualiza saldos de CxC y cliente al abonar; si el saldo llega a ₡0, cambia automáticamente el estado de la factura de `P` (Pendiente) a `C` (Cancelada).
  * `TRG_COM_ABONO_SALDO_AI`: Actualiza saldos de CxP y proveedor al abonar; si llega a ₡0, pasa factura a `C`.
  * `TRG_COM_FACTURA_DET_INV_AI`: Aumenta el stock en bodega y registra entrada en el kardex tras compras.
  * `TRG_VEN_FACTURA_DET_INV_AI`: Valida existencia suficiente, descuenta stock, registra salida en kardex tras ventas y otorga las acciones de productos patrocinadores (`PKG_PRM_MERCADEO.PR_OTORGAR_ACCIONES_LINEA`).
  * `TRG_PRO_HISTORIAL_PRECIO_AU`: Bitácora automática en `PRO_PRECIO_HIST` ante cambios del precio de costo.
  * `TRG_VEN_DEVOLUCION_DET_INV_AI`: Reintegra existencias a bodega al aceptar una devolución de cliente.
  * `TRG_COM_DEVOLUCION_DET_INV_AI`: Descuenta inventario al realizar una devolución a proveedor.
* **9 Triggers de Auditoría Profunda** (`TRG_AUD_*`): Registran usuario, IP, terminal y valores antes/después en `AUD_REGISTRO_CAMBIO` para `VEN_FACTURA`, `COM_FACTURA_COMPRA`, `PRO_PRODUCTO`, `INV_MOVIMIENTO`, `PER_CLIENTE`, `PER_PROVEEDOR`, `PRM_PROMOCION`, `PRM_DESCUENTO` y `PRM_DESCUENTO_DET`.
* **1 Trigger de parametrización:** `TRG_SEG_PARAM_PREMIACION_AU` reprograma `JOB_PREMIACION_SEMESTRAL` cuando cambia `MESES_FRECUENCIA_PREMIACION`.

### Paso 5: Seguridad, Perfiles, Roles con Clave y Mínimos Privilegios (`05_Seguridad_Perfiles_Roles_Usuarios.sql`)
1. Crea los perfiles de seguridad:
   * `PERFIL_CADENA_ADMIN`: Para gerencia y jefaturas (3 intentos fallidos, bloqueo 1 día, vigencia 60 días, inactividad 30 min).
   * `PERFIL_CADENA_OPER`: Para digitadores y cajeros (3 intentos, vigencia 45 días, inactividad 15 min).
2. Crea los **4 Roles Protegidos con Contraseña**:
   * `ROL_GERENTE` (Contraseña cifrada con AES-256 en base de datos).
   * `ROL_JEFE_DEPARTAMENTO`.
   * `ROL_JEFE_PROVEEDURIA`.
   * `ROL_DIGITADOR`.
3. Aplica la matriz de **mínimos privilegios de objeto** (únicamente privilegios estrictamente necesarios; ningún rol recibe `DELETE` sobre catálogos ni permisos `DDL`).
4. Crea los usuarios del sistema (`USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR`), asignándoles tablespace `TBS_DATOS`, cuota de 20 MB y `DEFAULT ROLE NONE`.
5. Ejecuta una **demostración en vivo en sesiones reales**:
   * Conexión como `USR_DIGITADOR`: Demuestra que antes de activar el rol no puede consultar tablas; activa el rol mediante `PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR')`; realiza consultas autorizadas; intenta un `DELETE` y un `DROP TABLE` y el motor los **rechaza con ORA-41900 / ORA-01031**.
   * Conexión como `USR_GERENTE`: Activa su rol; consulta las vistas materializadas ejecutivas; intenta un `INSERT` operativo y es **rechazado por mínimo privilegio**.

### Paso 6: Automatización DBMS_SCHEDULER, Optimización SQL y Pruebas (`06_Scheduler_Optimizacion_y_Pruebas.sql`)
1. Programa los **5 Jobs en Segundo Plano**:
   * `JOB_CIERRE_DIARIO_AUTO`: Diario a las 23:00 (cierre consolidado y por cajero).
   * `JOB_MONITOREO_SALUD_DIARIO`: Diario a las 06:00 (tablespaces, objetos, índices).
   * `JOB_NOTIF_CREDITOS_DIARIO`: Diario a las 07:00 (alertas de crédito, morosidad y vencidos).
   * `JOB_MERCADEO_SEMANAL`: Lunes a las 05:00 (reporte de inventario y descuentos).
   * `JOB_PREMIACION_SEMESTRAL`: 30 junio y 31 diciembre a las 23:30 (Top 10 clientes).
2. Caso de Estudio de **Afinamiento y Optimización SQL**:
   * Evalúa la consulta crítica de cobros en tres dimensiones con `EXPLAIN PLAN` + `DBMS_XPLAN.DISPLAY`:
     - Ruta Natural del Optimizador (sin hints): Demuestra por qué el CBO selecciona Full Table Scan en tablas semilla de un solo bloque (costo 3 I/Os FTS vs 4 I/Os Index Scan).
     - Escaneo Completo Forzado (`/*+ FULL */`): Simula la línea base no indexada.
     - Acceso Indexado Forzado (`/*+ INDEX */`): Utiliza el índice compuesto `IX_CUCO_ESTADO_VENCIM (ESTADO_CUCO, FECHA_VENCIM_CUCO)` alojado en `TBS_INDICES`, proyectando la reducción de I/O a escala empresarial de $\mathcal{O}(N)$ a $\mathcal{O}(\log N)$.
3. Ejecuta la **Suite Integral de 12 Pruebas de Extremo a Extremo**, validando cada requerimiento de negocio de forma completamente automatizada:
   * Pruebas positivas de monitoreo, notificaciones de crédito (85% y 70%), padrón electoral TSE con resolución distrital, compras atómicas, ventas atómicas, abonos con liquidación de estado (P $\to$ C), mercadeo/descuentos, cierre diario por cajero y refresco de vistas materializadas.
   * Pruebas negativas y de integridad: Rechazo controlado por límite de crédito (`ORA-20010`) con verificación estricta de atomicidad (cero facturas o CxC huérfanas tras `ROLLBACK TO SAVEPOINT`), rechazo por falta de inventario (`ORA-20015`), y reconfiguración dinámica en caliente del Scheduler (`DBMS_SCHEDULER.SET_ATTRIBUTE`).

### Paso 7: Jobs del Standby y RMAN (`sql/07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql`)
1. Otorga a `CADENA_NEG` los privilegios `CREATE EXTERNAL JOB` y `CREATE CREDENTIAL`.
2. Registra en `SEG_PARAMETRO` las rutas y horarios del standby (detecta SO, SID, `ORACLE_HOME` y la ruta de archivelogs).
3. Crea el paquete `PKG_ADM_STANDBY` y los jobs `JOB_STANDBY_TRASLADO_ARCHIVELOG`, `JOB_RMAN_BACKUP_DIARIO`, `JOB_STANDBY_PURGA_ARCHIVELOG` y `JOB_STANDBY_MONITOREO`.
4. **Acción manual única:** los tres jobs externos quedan deshabilitados hasta registrar el usuario del sistema operativo:
   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('usuario_windows', 'clave_windows');
   ```

En Docker el usuario es `oracle`, que en la imagen no tiene clave: asígnele una con `docker exec -it -u root ora_principal passwd oracle` antes de registrarla. Con la credencial registrada, los jobs externos se habilitan y se ejecutan solos (verificado en Docker). Si no se registra, los mismos trabajos se pueden ejecutar a mano con el orquestador `02_Traslado_Archivelogs_10min_y_Ondemand.sh`.

La configuración de la segunda computadora (standby con Data Guard) se detalla en la sección 11 del **Manual de Administración del Standby**.

### Paso 8: Oracle Wallet para el correo SSL/TLS (`sql/08_Wallet_SMTP_Gmail.sh`)
Gmail solo acepta conexiones cifradas. En Oracle 21c, sin un wallet con los certificados raíz de Google, el envío falla con `ORA-29024: Certificate validation failure`.

1. Ejecutar el script como usuario `oracle` en el servidor (en Docker, desde Windows):
   ```powershell
   docker exec -u oracle ora_principal bash /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh
   ```
2. El script toma del propio Linux los certificados raíz **GTS Root R1-R4** y **GlobalSign Root CA**, crea un wallet auto-login (`cwallet.sso`) en `/opt/oracle/oradata/wallet_smtp` y registra la ruta en `SEG_PARAMETRO` (`SMTP_WALLET_PATH = file:/opt/oracle/oradata/wallet_smtp`). Debe terminar con `[OK] Wallet listo.`
3. Verificado en Oracle 21c EE: después del wallet el `ORA-29024` desaparece y el siguiente error es `535` (*Username and Password not accepted*) hasta guardar la clave de aplicación real (Paso 9).

**Windows nativo (alternativa, no probada en este proyecto):** el mismo concepto con `orapki`. Se exportan desde `certmgr.msc` los certificados raíz GTS Root R1-R4 y GlobalSign Root CA en formato Base 64 (`.cer`) y luego:
```bat
orapki wallet create -wallet C:\app\oracle\wallet_smtp -pwd <clave del wallet> -auto_login
orapki wallet add -wallet C:\app\oracle\wallet_smtp -trusted_cert -cert C:\temp\GTS_Root_R1.cer -pwd <clave del wallet>
```
(un `wallet add` por certificado) y se registra la ruta:
```sql
EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('SMTP_WALLET_PATH', 'CORREO', 'Ruta del Oracle Wallet SMTP', 'Wallet auto-login con los certificados raiz de Gmail para UTL_SMTP (SSL/TLS).', 'N', 'file:C:\app\oracle\wallet_smtp');
```

### Paso 9: Clave de aplicación de Gmail
La clave sembrada por el instalador es solo de ejemplo. Antes de la defensa:

1. En la cuenta de Google del correo emisor: **Gestionar tu cuenta** → **Seguridad** → **Verificación en 2 pasos** → **Contraseñas de aplicaciones**. Crear una y copiar las 16 letras.
2. Guardarla cifrada con AES-256 (en `PDBCADENA`):
   ```sql
   EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '<clave de aplicacion de 16 letras>');
   ```
3. Probar: `EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;` y revisar `CADENA_NEG.AUD_ERROR_SISTEMA` si no llega.

### Paso 10: Carga del Padrón Nacional Electoral oficial (TSE)
El enunciado pide cargar el padrón **con la información actual**. Las pruebas del paso 6 usan un archivo pequeño (`PADRON_PRUEBA.TXT`); el padrón real se carga así:

1. Ver la carpeta del directorio `DIR_PADRON` (en Docker: `/opt/oracle/oradata/CADENA/PDBCADENA`):
   ```sql
   SELECT directory_path FROM all_directories WHERE directory_name = 'DIR_PADRON';
   ```
2. Descargar y descomprimir el padrón vigente (`padron_completo.zip`, ~74 MB, publicado cada mes en https://www.tse.go.cr/descarga_padron.html):
   ```powershell
   .\datos\padron\Descargar_Padron_TSE.ps1 -Destino <carpeta de DIR_PADRON>
   ```
   En Docker: `docker exec -it -u oracle ora_principal bash /opt/oracle/proyecto/datos/padron/Descargar_Padron_TSE.sh https://www.tse.go.cr/zip/padron/padron_completo.zip /opt/oracle/oradata/CADENA/PDBCADENA`
3. Cargarlo. Verificado en Oracle 26ai Free (Docker) con el padrón del 30/09/2026: 3.762.240 personas, 0 rechazos, 2.179 distritos electorales, unos 39 minutos y 553 MB. Las cargas mensuales siguientes solo reescriben a las personas que cambiaron. El padrón oficial no publica el sexo (su campo 3 es `RELLENO`), por eso se guarda `N` = no indicado.
   ```sql
   SET SERVEROUTPUT ON
   EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;
   SELECT * FROM CADENA_NEG.V_PADRON_DETALLE WHERE cedula_padr = '<una cedula real>';
   ```
4. Desde entonces `JOB_PADRON_MENSUAL` lo descarga y recarga solo el día `PADRON_DIA_CARGA` (5) de cada mes. La descarga automática usa la misma credencial del SO del paso 7.

Las líneas rechazadas quedan en `padron_tse.bad` y el detalle en `padron_tse.log`, dentro de la misma carpeta.

---

## 5. Verificación Posterior y Validación del Estado Final

Al concluir la ejecución de `sql/00_Master_Instalacion_Avance2.sql`, el script imprime un resumen directo del diccionario de datos:

```sql
SELECT object_type, status, COUNT(*) AS cantidad
  FROM all_objects
 WHERE owner = 'CADENA_NEG'
 GROUP BY object_type, status
 ORDER BY object_type, status;
```

### 5.1 Cifras Oficiales Obtenidas en Verificación en Vivo
* **TABLE:** 65 (todas `VALID`; incluye las tablas externas `EXT_PADRON_TSE` y `EXT_DISTELEC_TSE`).
* **INDEX:** 225 (todos `VALID`).
* **SEQUENCE:** 60 (todas `VALID`).
* **PACKAGE:** 10 (todos `VALID`, incluye `PKG_ADM_STANDBY`).
* **PACKAGE BODY:** 10 (todos `VALID`).
* **TRIGGER:** 21 (todos `VALID` y `ENABLED`).
* **JOB (Scheduler):** 11: los 5 de negocio, `JOB_PADRON_MENSUAL` y `JOB_STANDBY_MONITOREO` en `SCHEDULED`; los jobs externos (3 del standby y `JOB_PADRON_DESCARGA`) se habilitan al registrar la credencial.
* **VIEW:** 7 (todas `VALID`, incluye `V_PADRON_DETALLE`).
* **MATERIALIZED VIEW:** 2 (`MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO`, `VALID`).
* **PROCEDURE:** 1 (`PRC_ACTIVAR_ROL_SESION`, `VALID`).
* **TOTAL DE OBJETOS INVÁLIDOS:** **0**.

### 5.2 Comprobación de Parámetros de Notificación
Para constatar la parametrización del correo del evaluador:

```sql
SELECT codigo_para, valor_texto_para 
  FROM CADENA_NEG.SEG_PARAMETRO 
 WHERE codigo_para LIKE '%CORREO%';
```
* `CORREO_COORDINADOR`: `keylorpineda729@gmail.com`
* `CORREO_GERENTE`: `keylorpineda729@gmail.com`
* `CORREO_DBA`: `keylorpineda729@gmail.com`

---

## 6. Guía de Solución de Problemas (Troubleshooting)

1. **Error `ORA-65096: invalid common user or role name`:**
   * *Causa:* La sesión de SQL\*Plus se encuentra conectada en `CDB$ROOT` en lugar de un PDB.
   * *Solución:* Todos los scripts del proyecto incluyen detección dinámica de contenedor. Si ejecuta comandos manuales, ejecute primero:
     ```sql
     ALTER SESSION SET CONTAINER = PDBCADENA;
     ```

2. **Error `ORA-24247: network access denied by access control list (ACL)`:**
   * *Causa:* Restricción de seguridad en el puerto SMTP (465 o 587) para envíos con `UTL_SMTP`.
   * *Solución:* El paquete de notificaciones captura el error de forma segura en bitácora local (`AUD_ERROR_SISTEMA`) sin abortar la transacción de negocio. Para habilitar la salida real en entornos locales, ejecute como SYSDBA:
     ```sql
     BEGIN
         DBMS_NETWORK_ACL_ADMIN.APPEND_HOST_ACE(
             host => '*',
             lower_port => 465,
             upper_port => 465,
             ace => xs$ace_type(privilege_list => xs$name_list('connect'),
                                 principal_name => 'CADENA_NEG',
                                 principal_type => xs_acl.ptype_db));
     END;
     /
     ```

3. **Error `ORA-29024: Certificate validation failure` al enviar correo:**
   * *Causa:* Oracle no tiene un wallet con los certificados raíz de Gmail.
   * *Solución:* Paso 8 (`sql/08_Wallet_SMTP_Gmail.sh`). Si después aparece `535`, falta la clave de aplicación real (Paso 9).

4. **Bloqueo de Cuenta por Intentos Fallidos (`ORA-28000: the account is locked`):**
   * *Causa:* Se superó el umbral de 3 intentos fallidos establecido en `PERFIL_CADENA_ADMIN` o `PERFIL_CADENA_OPER`.
   * *Solución:* Desbloquee el usuario desde SYSDBA:
     ```sql
     ALTER USER USR_DIGITADOR ACCOUNT UNLOCK;
     ```
