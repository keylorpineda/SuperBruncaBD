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
* **Motor de Base de Datos:** Oracle Database 21c Enterprise/XE, 23ai Free o 26ai Free con arquitectura multitenant y al menos un Pluggable Database (PDB) en modo `READ WRITE` (ej. `FREEPDB1`).
* **Virtualización / Contenedores:** Docker Desktop 4.x+ con motor Linux y contenedor Oracle activo (ej. `oracle_una`), o bien instalación bare-metal / máquina virtual.
* **Herramientas de Conexión:**
  * Oracle SQL\*Plus (versión 21c+).
  * Oracle SQL Developer 23.x+ o DBeaver Community.
  * Oracle Recovery Manager (`rman`).
* **Intérprete de Comandos:** Windows PowerShell 5.1 / PowerShell 7+ o GNU Bash.
* **Almacenamiento:** Mínimo 15 GB de espacio libre en disco para datafiles, redo logs multiplexados, respaldos RMAN y archivado continuo.

### 1.2 Parámetros de Red y Correo
* **Puerto de Base de Datos:** 1521 TCP (Listener Oracle).
* **Puerto de Envío SMTP:** 465 TCP (SMTPS con SSL / `smtp.gmail.com`); 587 con STARTTLS como alternativa.
* **Destinatario Institucional de Pruebas:** `keylorpineda729@gmail.com` (configurado en `CADENA_NEG.SEG_PARAMETRO` para coordinadores, gerencia y DBA).

---

## 2. Catálogo de Archivos Entregables

La solución se entrega organizada en scripts modulares e independientes, gobernados por un instalador maestro automatizado:

| ARCHIVO | TIPO | PROPÓSITO |
| :--- | :--- | :--- |
| `00_Master_Instalacion_Avance2.sql` | SQL Maestro | Orquestador de instalación integral en orden determinista. |
| `01_Estructuras_Avance2.sql` | DDL / DML | 11 tablas nuevas, secuencias, índices, 2 MV y datos semilla. |
| `02_Paquetes_Seguridad_Auditoria_Notificaciones.sql` | PL/SQL | Seguridad AES-256, auditoría autónoma y correo UTL_SMTP. |
| `03_Paquetes_Negocio_Monitoreo.sql` | PL/SQL | Padrón TSE, inventario, compras, ventas, mercadeo y salud. |
| `04_Triggers_Negocio_y_Auditoria.sql` | PL/SQL | 11 triggers de negocio y 7 triggers de bitácora profunda. |
| `05_Seguridad_Perfiles_Roles_Usuarios.sql` | SQL / DCL | Perfiles, 4 roles con clave cifrada, usuarios y pruebas de mínimos privilegios. |
| `06_Scheduler_Optimizacion_y_Pruebas.sql` | PL/SQL | 5 Jobs DBMS_SCHEDULER, EXPLAIN PLAN y 12 suites de prueba de extremo a extremo. |
| `padron_muestra.csv` | Datos externos | Archivo CSV muestra del padrón electoral para prueba de UTL_FILE. |
| `script_bd_v2.sql` | DDL Base | Línea base del Entregable #1 (tablas transaccionales y catálogos). |
| `07_Standby_y_RMAN/` | Directorio | Configuración de la principal (redo 50 MB / 5 min), creación y sincronización de la standby en la segunda PC, RMAN, purga, switchover y failover. |
| `07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql` | PL/SQL | Paquete `PKG_ADM_STANDBY` y 4 jobs DBMS_SCHEDULER: traslado cada 10 min, respaldo RMAN diario, purga de 3 días y monitoreo. |

---

## 3. Procedimiento Oficial de Instalación Automatizada

Todos los scripts han sido desarrollados con **idempotencia estricta**. Esto garantiza que el instalador maestro puede ejecutarse repetidamente sobre una base de datos limpia o en operación, detectando el PDB abierto, eliminando estructuras obsoletas de corridas previas y recreando el ambiente con **cero errores y cero objetos inválidos**.

### Opción A: Despliegue en Contenedor Docker (Recomendado)
Si la base de datos se ejecuta dentro de un contenedor Docker (ej. `oracle_una`):

1. **Copiar los archivos al contenedor:**
   ```powershell
   docker cp . oracle_una:/opt/oracle/proyecto/
   ```

2. **Ejecutar el instalador maestro como SYSDBA:**
   ```powershell
   docker exec -i -w /opt/oracle/proyecto oracle_una sqlplus -s / as sysdba '@00_Master_Instalacion_Avance2.sql'
   ```

### Opción B: Despliegue desde SQL\*Plus Local o SQL Developer
Si se conecta vía red o mediante cliente local:

```bash
sqlplus sys/TuPassword@localhost:1521/FREEPDB1 as sysdba @00_Master_Instalacion_Avance2.sql
```

> **Nota para SQL Developer:** Abra el archivo `00_Master_Instalacion_Avance2.sql` y presione **F5** (*Run Script*), asegurando que la conexión apunte a `FREEPDB1`.

---

## 4. Desglose Técnico de los Pasos de Instalación

El script maestro ejecuta de forma consecutiva las siete fases del avance:

### Paso 1: Estructuras DDL, Tablas Nuevas y Vistas Materializadas (`01_Estructuras_Avance2.sql`)
1. Detecta automáticamente el PDB activo (`FREEPDB1`) y conmuta la sesión mediante `ALTER SESSION SET CONTAINER`.
2. Configura el directorio lógico `DIR_PADRON` apuntando a la ruta física de datos para carga de archivos con `UTL_FILE`.
3. Ejecuta limpieza idempotente de tablas, secuencias y vistas materializadas preexistentes.
4. Modifica tablas base del Entregable #1 adicionando columnas de enlace electoral (`ID_PADRON` en `PER_CLIENTE`).
5. Crea las **11 tablas nuevas**:
   * `CAT_PADRON`: Almacenamiento optimizado del padrón electoral nacional.
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
1. `PKG_PER_PADRON`: Carga masiva de datos electorales desde archivo de texto con `UTL_FILE` y procedimiento `PR_CREAR_CLIENTE_DESDE_PADRON`.
2. `PKG_INV_GESTION`: Control de inventario con bloqueo pesimista `SELECT FOR UPDATE WAIT 5`, actualización de stock, kardex inmutable y reporte de productos críticos a mercadeo.
3. `PKG_COM_OPERACION`: Facturación de compras a proveedores con registro automático de cuentas por pagar y abonos.
4. `PKG_VEN_OPERACION`: Facturación en punto de venta, control de crédito, abonos de clientes y cierre contable diario consolidado y por cajero (`PR_EJECUTAR_CIERRE_DIARIO`).
5. `PKG_PRM_MERCADEO`: Cálculo de acciones por compra de productos patrocinadores, aplicación de descuentos semanales (`PR_VERIFICAR_DESCUENTOS_SEMANAL`) y premiación semestral de Top 10 clientes con órdenes de ₡100,000 (`PR_PREMIAR_MEJORES_CLIENTES`).
6. `PKG_ADM_MONITOREO`: Inspección automatizada de tablespaces (>85%), detección de objetos inválidos, índices en estado corrupto y crecimiento de sesiones.

### Paso 4: Disparadores de Reglas de Negocio y Auditoría (`04_Triggers_Negocio_y_Auditoria.sql`)
Compila 18 disparadores en estado `ENABLED`:
* **11 Triggers de Negocio:**
  * `TRG_VEN_FACTURA_CRED_BIU`: Bloquea facturas de venta a crédito si superan el límite del cliente.
  * `TRG_COM_FACTURA_CRED_AI`: Genera la cuenta por pagar (`COM_CUENTA_PAGAR`) al ingresar una compra a crédito.
  * `TRG_VEN_FACTURA_CRED_AI`: Genera la cuenta por cobrar (`VEN_CUENTA_COBRAR`) al emitir venta a crédito.
  * `TRG_VEN_ABONO_SALDO_AI`: Actualiza saldos de CxC y cliente al abonar; si el saldo llega a ₡0, cambia automáticamente el estado de la factura de `P` (Pendiente) a `C` (Cancelada).
  * `TRG_COM_ABONO_SALDO_AI`: Actualiza saldos de CxP y proveedor al abonar; si llega a ₡0, pasa factura a `C`.
  * `TRG_COM_FACTURA_DET_INV_AI`: Aumenta el stock en bodega y registra entrada en el kardex tras compras.
  * `TRG_VEN_FACTURA_DET_INV_AI`: Valida existencia suficiente, descuenta stock y registra salida en kardex tras ventas.
  * `TRG_PRO_HISTORIAL_PRECIO_AU`: Bitácora automática en `PRO_PRECIO_HIST` ante cambios de costo o precio.
  * `TRG_PRM_ACCIONES_VENTA_AI`: Otorga acciones electrónicas al cliente al comprar productos patrocinadores.
  * `TRG_VEN_DEVOLUCION_DET_AI`: Reintegra existencias a bodega al aceptar una devolución de cliente.
  * `TRG_COM_DEVOLUCION_DET_AI`: Descuenta inventario al realizar una devolución a proveedor.
* **7 Triggers de Auditoría Profunda:** Registran usuario, IP, terminal y valores antes/después en `AUD_REGISTRO_CAMBIO` para `VEN_FACTURA`, `COM_FACTURA_COMPRA`, `PER_CLIENTE`, `PER_PROVEEDOR`, `PRO_PRODUCTO`, `INV_EXISTENCIA` y `SEG_PARAMETRO`.

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

### Paso 7: Jobs del Standby y RMAN (`07_Standby_y_RMAN/07_Paquete_Jobs_Standby_RMAN.sql`)
1. Otorga a `CADENA_NEG` los privilegios `CREATE EXTERNAL JOB` y `CREATE CREDENTIAL`.
2. Registra en `SEG_PARAMETRO` las rutas y horarios del standby (detecta SO, SID, `ORACLE_HOME` y la ruta de archivelogs).
3. Crea el paquete `PKG_ADM_STANDBY` y los jobs `JOB_STANDBY_TRASLADO_ARCHIVELOG`, `JOB_RMAN_BACKUP_DIARIO`, `JOB_STANDBY_PURGA_ARCHIVELOG` y `JOB_STANDBY_MONITOREO`.
4. **Acción manual única:** los tres jobs externos quedan deshabilitados hasta registrar el usuario del sistema operativo:
   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_REGISTRAR_CREDENCIAL_OS('usuario_windows', 'clave_windows');
   ```

La configuración de la segunda computadora (standby) se detalla en el **Manual de Administración del Standby**.

> **Antes de la defensa:** reemplazar la clave de aplicación de Gmail sembrada como ejemplo:
> `EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '<clave de aplicacion de 16 letras>');`

---

## 5. Verificación Posterior y Validación del Estado Final

Al concluir la ejecución de `00_Master_Instalacion_Avance2.sql`, el script imprime un resumen directo del diccionario de datos:

```sql
SELECT object_type, status, COUNT(*) AS cantidad
  FROM all_objects
 WHERE owner = 'CADENA_NEG'
 GROUP BY object_type, status
 ORDER BY object_type, status;
```

### 5.1 Cifras Oficiales Obtenidas en Verificación en Vivo
* **TABLE:** 62 (todas `VALID`).
* **INDEX:** 224 (todos `VALID`).
* **SEQUENCE:** 60 (todas `VALID`).
* **PACKAGE:** 10 (todos `VALID`, incluye `PKG_ADM_STANDBY`).
* **PACKAGE BODY:** 10 (todos `VALID`).
* **TRIGGER:** 18 (todos `VALID` y `ENABLED`).
* **JOB (Scheduler):** 9: los 5 de negocio y `JOB_STANDBY_MONITOREO` en `SCHEDULED`; los 3 jobs externos del standby pasan a `SCHEDULED` al registrar la credencial.
* **VIEW:** 6 (todas `VALID`).
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
     ALTER SESSION SET CONTAINER = FREEPDB1;
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

3. **Bloqueo de Cuenta por Intentos Fallidos (`ORA-28000: the account is locked`):**
   * *Causa:* Se superó el umbral de 3 intentos fallidos establecido en `PERFIL_CADENA_ADMIN` o `PERFIL_CADENA_OPER`.
   * *Solución:* Desbloquee el usuario desde SYSDBA:
     ```sql
     ALTER USER USR_DIGITADOR ACCOUNT UNLOCK;
     ```
