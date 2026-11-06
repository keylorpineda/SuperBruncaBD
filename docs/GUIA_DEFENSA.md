# Guía de la defensa

Esta guía tiene dos partes:

1. Un **mapa** de cada requisito del enunciado (`docs/enunciado/`) al archivo, paquete, trigger o job que lo cumple, con el comando para demostrarlo.
2. Un **guion** de unos 15 minutos para la demostración en vivo.

Antes de empezar, en una sesión SQL*Plus como SYSDBA en la PC 1:

```sql
ALTER SESSION SET CONTAINER = ORCLPDB1;          -- su PDB
ALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
```

Los comandos de esta guía asumen esa sesión. Use números de factura y recibo nuevos cada vez que repita una demostración (son únicos).

---

## 1. Mapa requisito → solución → demostración

### 1.1 Funcionalidades de negocio

| Requisito del enunciado | Dónde está | Cómo demostrarlo |
| :--- | :--- | :--- |
| Factura de venta pendiente aumenta el saldo del cliente y crea la cuenta por cobrar | `TRG_VEN_FACTURA_CRED_AI` (`sql/04_Triggers_Negocio_y_Auditoria.sql`), `PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA` | Bloque A del guion; luego `SELECT * FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_VENTA = :fac;` |
| Factura de proveedor pendiente aumenta lo que se le debe (cuentas por pagar) | `TRG_COM_FACTURA_CRED_AI`, `PKG_COM_OPERACION.PR_CREAR_FACTURA_COMPRA` | Prueba 4 del instalador; `SELECT * FROM COM_CUENTA_PAGAR ORDER BY 1 DESC FETCH FIRST 5 ROWS ONLY;` |
| Factura pagada por completo pasa de pendiente a cancelada | `TRG_VEN_ABONO_SALDO_AI`, `TRG_COM_ABONO_SALDO_AI`, `PKG_VEN_OPERACION.PR_REGISTRAR_ABONO_COBRAR`, `PKG_COM_OPERACION.PR_REGISTRAR_ABONO_PAGAR` | Bloque B del guion (`ESTADO_FAVE` pasa de `P` a `C`) |
| Padrón nacional cargado, modelo adaptado y enlazado a clientes | `PKG_PER_PADRON` (`sql/03_Paquetes_Negocio_Monitoreo.sql`), tablas `CAT_PADRON`, `CAT_DISTRITO_ELECTORAL`, `EXT_PADRON_TSE`, vista `V_PADRON_DETALLE`, columna `PER_CLIENTE.ID_PADRON` | `SELECT COUNT(*) FROM CAT_PADRON;` y `SELECT * FROM V_PADRON_DETALLE WHERE cedula_padr = '<cédula>';` ([Guía del padrón](GUIA_PADRON_TSE.md)) |
| Procedimiento que carga el padrón automáticamente | `PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO`, `PR_ACTUALIZAR_PADRON_MENSUAL`, jobs `JOB_PADRON_MENSUAL` y `JOB_PADRON_DESCARGA` | `SELECT job_name, state, repeat_interval FROM user_scheduler_jobs WHERE job_name LIKE 'JOB_PADRON%';` |
| Facturas de venta y compra modifican el inventario | `TRG_VEN_FACTURA_DET_INV_AI`, `TRG_COM_FACTURA_DET_INV_AI`, `PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA` | Bloque A: `CANTIDAD_EXIS` baja 5 unidades |
| Devoluciones modifican el inventario | `TRG_VEN_DEVOLUCION_DET_INV_AI`, `TRG_COM_DEVOLUCION_DET_INV_AI` | Bloque C del guion (`CANTIDAD_EXIS` sube 1) |
| Cambio de precio de costo queda en el historial de precios | `TRG_PRO_HISTORIAL_PRECIO_AU` → `PRO_PRECIO_HIST` | Bloque D del guion |
| Límites al facturar a crédito (clientes y proveedores) | `TRG_VEN_FACTURA_CRED_BIU` (`ORA-20010`), `TRG_COM_FACTURA_CRED_BIU` (`ORA-20015`) | Bloque E del guion; también la prueba 10 del instalador |
| Reporte semanal a mercadeo: por vencer (1 semana) y más de 6 meses en bodega, notificado al coordinador | `PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO`, job `JOB_MERCADEO_SEMANAL` (lunes 05:00), parámetro `MESES_ANTIGUEDAD_BODEGA` | `EXEC PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO;` y revisar el correo del coordinador |
| Promociones con acciones según productos patrocinadores | `PKG_PRM_MERCADEO.FN_CALCULAR_ACCIONES_FACTURA` y `PR_OTORGAR_ACCIONES_LINEA` (llamado desde `TRG_VEN_FACTURA_DET_INV_AI`) | `SELECT PKG_PRM_MERCADEO.FN_CALCULAR_ACCIONES_FACTURA(:fac) FROM dual;` y `SELECT * FROM PRM_ACCION_CLIENTE ORDER BY 1 DESC FETCH FIRST 5 ROWS ONLY;` |
| Verificación semanal de descuentos planeados | `PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL` (en `JOB_MERCADEO_SEMANAL`), tabla `PRM_DESCUENTO_DET` | `EXEC PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL;` y `SELECT * FROM PRM_DESCUENTO_DET;` |
| Top 10 clientes con orden de ₡100 000 cada 6 meses (parametrizado) | `PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES`, `JOB_PREMIACION_SEMESTRAL`, parámetros `MONTO_ORDEN_PREMIACION` y `MESES_FRECUENCIA_PREMIACION`, `TRG_SEG_PARAM_PREMIACION_AU` | `EXEC PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES('2026-S2');` y `SELECT * FROM PRM_ORDEN_PREMIACION;` |
| Bitácoras de facturación, precios, inventario, clientes, proveedores, promociones y descuentos | `TRG_AUD_VEN_FACTURA`, `TRG_AUD_COM_FACTURA`, `TRG_AUD_PRO_PRODUCTO`, `TRG_AUD_INV_MOVIMIENTO`, `TRG_AUD_PER_CLIENTE`, `TRG_AUD_PER_PROVEEDOR`, `TRG_AUD_PRM_PROMOCION`, `TRG_AUD_PRM_DESCUENTO`, `TRG_AUD_PRM_DESCUENTO_DET` → `AUD_REGISTRO_CAMBIO` | Bloque D: consulta a `AUD_REGISTRO_CAMBIO` |
| Notificaciones parametrizadas (correo, clave, destinatarios) | `SEG_PARAMETRO`: `SMTP_HOST`, `SMTP_PORT`, `CORREO_EMISOR`, `CLAVE_CORREO_EMISOR`, `CORREO_COORDINADOR`, `CORREO_GERENTE`, `CORREO_DBA` | `SELECT codigo_para, es_cifrado_para, valor_texto_para FROM SEG_PARAMETRO WHERE modulo_para = 'CORREO';` |
| Clave del correo cifrada | `PKG_SEG_SEGURIDAD.FN_CIFRAR_VALOR` / `FN_DESCIFRAR_VALOR` (AES-256, `DBMS_CRYPTO`), columna `VALOR_RAW_PARA` | `SELECT codigo_para, valor_texto_para, valor_raw_para FROM SEG_PARAMETRO WHERE codigo_para = 'CLAVE_CORREO_EMISOR';` (texto vacío, solo bytes cifrados) |
| Correo directo desde Oracle, sin VPN | `PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO` (`UTL_SMTP`, `sql/02_Paquetes_Seguridad_Auditoria_Notificaciones.sql`) | Cualquier notificación del bloque F |

### 1.2 Seguridad

| Requisito | Dónde está | Cómo demostrarlo |
| :--- | :--- | :--- |
| Perfiles, roles y usuarios (Gerente, Jefe Departamento, Jefe Proveeduría, Digitador) | `sql/05_Seguridad_Perfiles_Roles_Usuarios.sql`: perfiles `PERFIL_CADENA_ADMIN`, `PERFIL_CADENA_OPER`; roles `ROL_GERENTE`, `ROL_JEFE_DEPARTAMENTO`, `ROL_JEFE_PROVEEDURIA`, `ROL_DIGITADOR`; usuarios `USR_GERENTE`, `USR_JEFE_DEPTO`, `USR_JEFE_PROV`, `USR_DIGITADOR` | `SELECT username, profile, account_status FROM dba_users WHERE username LIKE 'USR_%';` |
| Password profile (expiración, intentos, bloqueo, reutilización) | `PERFIL_CADENA_ADMIN` / `PERFIL_CADENA_OPER` (3 intentos, vida 60/45 días, reutilización) | `SELECT profile, resource_name, limit FROM dba_profiles WHERE profile LIKE 'PERFIL_CADENA%' AND resource_type = 'PASSWORD';` |
| Roles con clave cifrada en una tabla de parámetros | Parámetros `CLAVE_ROL_*` cifrados; `PKG_SEG_SEGURIDAD.PR_ASIGNAR_CLAVE_ROL` | `SELECT codigo_para, es_cifrado_para FROM SEG_PARAMETRO WHERE codigo_para LIKE 'CLAVE_ROL%';` |
| Procedimiento que asigna la clave al rol para usarlo | `PRC_ACTIVAR_ROL_SESION` (descifra y ejecuta `DBMS_SESSION.SET_ROLE`) | Bloque G del guion |
| Permisos mínimos, sin `DBA`, `CONNECT` ni `RESOURCE`; privilegios de sistema vs. de objeto | Matriz de privilegios en `sql/05_...sql` | `SELECT * FROM dba_role_privs WHERE grantee LIKE 'ROL_%' OR grantee LIKE 'USR_%';` `SELECT * FROM dba_sys_privs WHERE grantee LIKE 'ROL_%';` `SELECT grantee, table_name, privilege FROM dba_tab_privs WHERE grantee LIKE 'ROL_%';` |

### 1.3 Notificaciones y monitoreo

| Requisito | Dónde está | Cómo demostrarlo |
| :--- | :--- | :--- |
| Clientes con 85 % o más de su límite (a cada cliente y resumen al coordinador) | `PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO`, parámetro `PORC_ALERTA_CREDITO_CLI` | `EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO;` |
| Proveedores cerca del 70 %, en un solo correo al gerente | `PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO`, parámetro `PORC_ALERTA_CREDITO_PROV` | `EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO;` |
| Clientes morosos (último pago hace más de un mes) al gerente y coordinador | `PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS`, parámetro `MESES_MOROSIDAD_CLIENTE` | `EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS;` |
| Productos vencidos con total, al coordinador | `PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS` | `EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;` |
| Cierre diario automático (encabezado y detalle por cajero), notificado | `PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO`, `JOB_CIERRE_DIARIO_AUTO` (23:00), tablas `VEN_CIERRE_DIARIO` y `VEN_CIERRE_DIARIO_DET` | `EXEC PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO;` y `SELECT * FROM VEN_CIERRE_DIARIO_DET ORDER BY 1 DESC FETCH FIRST 5 ROWS ONLY;` |
| Tablespaces sin pasar del 85 %, diario | `PKG_ADM_MONITOREO.PR_VERIFICAR_TABLESPACES`, `JOB_MONITOREO_SALUD_DIARIO` (06:00), parámetro `PORC_MAX_TABLESPACE` | Bloque H del guion |
| Objetos inválidos, diario | `PKG_ADM_MONITOREO.PR_VERIFICAR_OBJETOS_INVALIDOS` | Bloque H del guion |
| Índices dañados, diario | `PKG_ADM_MONITOREO.PR_VERIFICAR_INDICES_DANADOS` | Bloque H del guion |
| Paquete de monitoreo: crecimiento, sesiones y errores | `PKG_ADM_MONITOREO.PR_MONITOREAR_SESIONES_Y_CRECIMIENTO`, `PR_VERIFICAR_ERRORES_SISTEMA`, `PR_EJECUTAR_MONITOREO_DIARIO` → `AUD_MONITOREO_BD` | `EXEC PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO;` y `SELECT * FROM AUD_MONITOREO_BD ORDER BY 1 DESC FETCH FIRST 10 ROWS ONLY;` |

### 1.4 Requerimientos de base de datos

| # | Requisito | Dónde está | Cómo demostrarlo |
| :--- | :--- | :--- | :--- |
| 1 | Arquitectura en paquetes | 10 paquetes: `PKG_AUD_CONTROL`, `PKG_SEG_SEGURIDAD`, `PKG_ADM_NOTIFICACION`, `PKG_PER_PADRON`, `PKG_INV_GESTION`, `PKG_PRM_MERCADEO`, `PKG_COM_OPERACION`, `PKG_VEN_OPERACION`, `PKG_ADM_MONITOREO`, `PKG_ADM_STANDBY` | `SELECT object_name, status FROM user_objects WHERE object_type = 'PACKAGE BODY';` |
| 2 | `COMMIT`, `ROLLBACK`, `SAVEPOINT` | `PKG_VEN_OPERACION.PR_FACTURAR_VENTA_ATOMICA`, `PKG_COM_OPERACION.PR_FACTURAR_COMPRA_ATOMICA` | Prueba 10 del instalador: factura rechazada sin dejar filas huérfanas |
| 3 | Manejo de excepciones | Todos los procedimientos; errores en `AUD_ERROR_SISTEMA` vía `PKG_AUD_CONTROL.PR_REGISTRAR_ERROR` | `SELECT * FROM AUD_ERROR_SISTEMA ORDER BY 1 DESC FETCH FIRST 5 ROWS ONLY;` |
| 4 | Auditoría con triggers | `TRG_AUD_*` → `AUD_REGISTRO_CAMBIO`; operaciones críticas en `AUD_BITACORA` (`PKG_AUD_CONTROL.PR_REGISTRAR_OPERACION`, transacción autónoma) | `SELECT * FROM AUD_BITACORA ORDER BY 1 DESC FETCH FIRST 5 ROWS ONLY;` |
| 5 | Todos los procesos automáticos con `DBMS_SCHEDULER` | 11 jobs: `JOB_CIERRE_DIARIO_AUTO`, `JOB_MONITOREO_SALUD_DIARIO`, `JOB_NOTIF_CREDITOS_DIARIO`, `JOB_MERCADEO_SEMANAL`, `JOB_PREMIACION_SEMESTRAL`, `JOB_PADRON_MENSUAL`, `JOB_PADRON_DESCARGA`, `JOB_STANDBY_TRASLADO_ARCHIVELOG`, `JOB_RMAN_BACKUP_DIARIO`, `JOB_STANDBY_PURGA_ARCHIVELOG`, `JOB_STANDBY_MONITOREO` | `SELECT job_name, job_type, state, repeat_interval FROM user_scheduler_jobs ORDER BY 1;` |
| 6 | Seguridad (password profile, roles mínimos, privilegios) | Sección 1.2 | Sección 1.2 |
| 7 | Cifrado con `DBMS_CRYPTO` | `PKG_SEG_SEGURIDAD` (AES-256 CBC PKCS5) | `SELECT codigo_para FROM SEG_PARAMETRO WHERE es_cifrado_para = 'S';` |
| 8 | Optimización con `EXPLAIN PLAN` | Sección 2 de `sql/06_Scheduler_Optimizacion_y_Pruebas.sql`, índice `IX_CUCO_ESTADO_VENCIM` | Bloque I del guion |
| 9 | Vistas materializadas de ventas mensuales e inventario consolidado | `MV_VENTAS_MENSUALES`, `MV_INVENTARIO_CONSOLIDADO` (`sql/01_Estructuras_Avance2.sql`) | `EXEC DBMS_MVIEW.REFRESH('MV_VENTAS_MENSUALES', 'C');` y `SELECT * FROM MV_VENTAS_MENSUALES;` |
| 10 | Todo lo "parametrizado" en tablas | `SEG_PARAMETRO` | `SELECT modulo_para, codigo_para, valor_texto_para, valor_num_para FROM SEG_PARAMETRO ORDER BY 1, 2;` |
| 11 | Concurrencia con `SELECT FOR UPDATE`, `NOWAIT`, `WAIT` | `PKG_INV_GESTION.PR_AFECTAR_EXISTENCIA` (`WAIT 5`), `PKG_COM_OPERACION` (`WAIT 5` y `NOWAIT`), `PKG_VEN_OPERACION` (`WAIT 5`) | Mostrar el código: `grep -n "FOR UPDATE" sql/03_Paquetes_Negocio_Monitoreo.sql` |
| 12 | Integridad con paquetes o triggers | Triggers `*_CRED_BIU` y `*_INV_AI`; prueba 11 (`ORA-20015`, venta sin existencias) | Bloque E del guion |
| 13 | Paquete de monitoreo | `PKG_ADM_MONITOREO` | Sección 1.3 |
| 14 | Standby con failover, switchover, recuperación y sincronización | `sql/07_Standby_y_RMAN/` y `PKG_ADM_STANDBY` | Sección 11 del Manual del Standby (bloque J del guion) |
| 15 | RMAN: backup full, incremental, restore y recovery | `04_RMAN_Backup_Full_Incremental.rman` (nivel 0 domingo / nivel 1), `05_RMAN_Restore_Recovery_PointInTime.rman`, `JOB_RMAN_BACKUP_DIARIO` | `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;` y en RMAN `LIST BACKUP SUMMARY;` |

### 1.5 Standby

Todos los archivos están en `sql/07_Standby_y_RMAN/`. Detalle en el [Manual de Administración del Standby](manuales/Manual_Administracion_Standby.md), sección 1.3.

| Requisito | Dónde está | Cómo demostrarlo |
| :--- | :--- | :--- |
| Dos servidores distintos | PC 1 (principal, `PRIMARY`) y PC 2 (standby, `db_unique_name = CADENA_STBY`) | En cada PC: `SELECT name, db_unique_name, database_role, open_mode FROM v$database;` |
| Archivo de actualización cada 5 min o 50 MB (parametrizado) | `01_Configuracion_Primaria_Redo_Archive.sql`: redo de 50 MB y `ARCHIVE_LAG_TARGET = 300`; parámetros `STANDBY_SWITCH_MIN`, `STANDBY_SWITCH_MB` | `SELECT group#, bytes/1024/1024 mb, status FROM v$log;` y `SHOW PARAMETER archive_lag_target` |
| Traslado cada 10 min (parametrizado) y a petición | `JOB_STANDBY_TRASLADO_ARCHIVELOG`, parámetro `STANDBY_SYNC_MIN`, `02_Traslado_Archivelogs_10min_y_Ondemand.ps1` / `.sh` | `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;` |
| Oracle 21c, Linux o Windows | Oracle 21c EE (Docker o VM) | `SELECT banner_full FROM v$version;` |
| Purga de lo trasladado y lo aplicado con más de 3 días (parametrizado) | `JOB_STANDBY_PURGA_ARCHIVELOG`, `03_Purga_Archivelogs_3Dias.rman` (PC 1), `03_Purga_Archivelogs_Standby.rman` (PC 2), parámetro `STANDBY_PURGE_DIAS` | `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;` |
| Respaldo diario automático, trasladado al standby y a petición | `JOB_RMAN_BACKUP_DIARIO`, parámetro `STANDBY_HORA_BACKUP` | `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;` |
| Monitoreo de la sincronización | `JOB_STANDBY_MONITOREO`, `PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION`, parámetro `STANDBY_MAX_LAG_MIN` | `EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;` |
| Failover, switchover, recuperación, sincronización | `06_Standby_Switchover_y_Failover.sql`, `09_Aplicar_Archivelogs_Standby.rman` | Bloque J del guion |
| Replicar todas las acciones y manual ante inconvenientes | `FORCE LOGGING`, `STANDBY_FILE_MANAGEMENT = AUTO` | Sección 10 del Manual del Standby; `SELECT force_logging FROM v$database;` |

### 1.6 Documentación

| Requisito | Dónde está |
| :--- | :--- |
| Manual de instalación y despliegue | `docs/manuales/Manual_Instalacion_y_Despliegue.pdf` |
| Manual de administración del Standby | `docs/manuales/Manual_Administracion_Standby.pdf` |
| Manual técnico de administración y mantenimiento | `docs/manuales/Manual_Tecnico_de_Administracion_y_Mantenimiento.pdf` |
| Documentación interna del código | Encabezados y comentarios de cada script en `sql/` |
| Modelo relacional | `docs/entregable1/` |

---

## 2. Guion de demostración (unos 15 minutos)

Tenga abiertas dos ventanas: SQL*Plus en la PC 1 (con la sesión preparada al inicio de esta guía) y una terminal en la PC 2. Tenga abierto también el correo de destino.

### Minuto 0–1: estado general

```sql
SELECT object_type, status, COUNT(*) FROM user_objects GROUP BY object_type, status ORDER BY 1;
SELECT job_name, state, next_run_date FROM user_scheduler_jobs ORDER BY 1;
```

Muestra 0 objetos inválidos y los 11 jobs.

### Minuto 1–4: facturación, cuentas por cobrar, inventario (bloques A y B)

**Bloque A: venta a crédito.** Primero los valores de antes:

```sql
VARIABLE fac NUMBER
SELECT SALDO_ACTUAL_CLI FROM PER_CLIENTE WHERE ID_CLIENTE = 3;
SELECT CANTIDAD_EXIS FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;

BEGIN
    PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA(
        p_id_cliente => 3, p_id_sucursal => 1, p_id_usuario => 1,
        p_num_factura => 'FAC-DEMO-001', p_es_credito => 'S',
        p_subtotal => 20000, p_descuento => 0, p_impuesto => 2600,
        p_id_factura_out => :fac);
    PKG_VEN_OPERACION.PR_AGREGAR_DETALLE_VENTA(
        p_id_factura_venta => :fac, p_id_producto => 1, p_id_servicio => NULL,
        p_id_lote => NULL, p_linea => 1, p_cantidad => 5, p_precio_unitario => 4000);
END;
/

SELECT SALDO_ACTUAL_CLI FROM PER_CLIENTE WHERE ID_CLIENTE = 3;                          -- subió 22 600
SELECT CANTIDAD_EXIS FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;       -- bajó 5
SELECT ESTADO_FAVE FROM VEN_FACTURA WHERE ID_FACTURA_VENTA = :fac;                      -- P
SELECT SALDO_CUCO, ESTADO_CUCO FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_VENTA = :fac;    -- cuenta por cobrar creada
SELECT PKG_PRM_MERCADEO.FN_CALCULAR_ACCIONES_FACTURA(:fac) AS acciones FROM dual;
```

**Bloque B: pago total y cambio de estado.**

```sql
EXEC PKG_VEN_OPERACION.PR_REGISTRAR_ABONO_COBRAR(:fac, 1, 'EFECTIVO', 'REC-DEMO-001', 22600);
SELECT ESTADO_FAVE FROM VEN_FACTURA WHERE ID_FACTURA_VENTA = :fac;                      -- C
SELECT SALDO_CUCO FROM VEN_CUENTA_COBRAR WHERE ID_FACTURA_VENTA = :fac;                 -- 0
```

### Minuto 4–5: devolución, precios y bitácora (bloques C y D)

**Bloque C: devolución de 1 unidad.**

```sql
INSERT INTO VEN_DEVOLUCION (ID_FACTURA_VENTA, ID_BODEGA, ID_USUARIO, CONSECUTIVO_DEVV, MOTIVO_DEVV)
VALUES (:fac, 1, 1, 'DEV-DEMO-001', 'Demostracion');
INSERT INTO VEN_DEVOLUCION_DET (ID_DEVOLUCION_VENTA, ID_FACTURA_VENTA_DET, CANTIDAD_DVVD)
SELECT SEQ_VEN_DEVOLUCION.CURRVAL, ID_FACTURA_VENTA_DET, 1 FROM VEN_FACTURA_DET WHERE ID_FACTURA_VENTA = :fac;
COMMIT;
SELECT CANTIDAD_EXIS FROM INV_EXISTENCIA WHERE ID_PRODUCTO = 1 AND ID_BODEGA = 1;       -- subió 1
```

**Bloque D: cambio de costo, historial y bitácora.**

```sql
UPDATE PRO_PRODUCTO SET PRECIO_COSTO_PROD = PRECIO_COSTO_PROD + 100 WHERE ID_PRODUCTO = 1;
COMMIT;
SELECT * FROM PRO_PRECIO_HIST WHERE ID_PRODUCTO = 1 ORDER BY FECHA_CAMBIO_PRHI DESC FETCH FIRST 3 ROWS ONLY;
SELECT TABLA_RECA, OPERACION_RECA, CAMPO_MODIFICADO_RECA, VALOR_ANTERIOR_RECA, VALOR_NUEVO_RECA,
       USUARIO_CREA_RECA, TERMINAL_RECA, DIRECCION_IP_RECA
  FROM AUD_REGISTRO_CAMBIO ORDER BY ID_REGISTRO_CAMBIO DESC FETCH FIRST 10 ROWS ONLY;
```

### Minuto 5–6: límite de crédito (bloque E)

**Bloque E.** Una factura a crédito enorme se rechaza:

```sql
VARIABLE fac2 NUMBER
EXEC PKG_VEN_OPERACION.PR_CREAR_FACTURA_VENTA(4, 1, 1, 'FAC-DEMO-EXCESO', 'S', 50000000, 0, 6500000, :fac2);
-- Esperado: ORA-20010 Limite de credito excedido para el cliente ...
SELECT COUNT(*) FROM VEN_FACTURA WHERE NUM_FACTURA_FAVE = 'FAC-DEMO-EXCESO';            -- 0
```

### Minuto 6–8: procesos automáticos y correos (bloque F)

**Bloque F.** Ejecutar a mano lo que hacen los jobs y mostrar los correos que llegan:

```sql
EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO;
EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO;
EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS;
EXEC PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;
EXEC PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO;
EXEC PKG_PRM_MERCADEO.PR_VERIFICAR_DESCUENTOS_SEMANAL;
EXEC PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO;
SELECT * FROM VEN_CIERRE_DIARIO ORDER BY 1 DESC FETCH FIRST 1 ROWS ONLY;
EXEC PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES('2026-S2');
SELECT * FROM PRM_ORDEN_PREMIACION ORDER BY 1 DESC FETCH FIRST 10 ROWS ONLY;
```

Explique que los mismos procedimientos los ejecutan `JOB_NOTIF_CREDITOS_DIARIO`, `JOB_MERCADEO_SEMANAL`, `JOB_CIERRE_DIARIO_AUTO` y `JOB_PREMIACION_SEMESTRAL`.

### Minuto 8–9: seguridad (bloque G)

**Bloque G.** En otra terminal, entrar como digitador (la clave está en `sql/05_Seguridad_Perfiles_Roles_Usuarios.sql`):

```powershell
docker exec -it oracle_una sqlplus USR_DIGITADOR@localhost:1521/ORCLPDB1
```

```sql
SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO;            -- falla: el rol aún no está activo
EXEC CADENA_NEG.PRC_ACTIVAR_ROL_SESION('ROL_DIGITADOR');
SELECT * FROM SESSION_ROLES;                             -- ROL_DIGITADOR
SELECT COUNT(*) FROM CADENA_NEG.PRO_PRODUCTO;            -- autorizado
DELETE FROM CADENA_NEG.PRO_PRODUCTO;                     -- rechazado (privilegios insuficientes)
```

De vuelta en la sesión SYSDBA, mostrar que la clave del rol está cifrada:

```sql
SELECT codigo_para, es_cifrado_para, valor_texto_para, valor_raw_para FROM SEG_PARAMETRO WHERE codigo_para LIKE 'CLAVE_ROL%';
```

### Minuto 9–10: monitoreo (bloque H)

**Bloque H.** Provocar un objeto inválido y un índice dañado, y ver cómo se detectan:

```sql
CREATE OR REPLACE FORCE VIEW V_DEMO_INVALIDA AS SELECT * FROM TABLA_QUE_NO_EXISTE;
ALTER INDEX IX_CUCO_ESTADO_VENCIM UNUSABLE;

EXEC PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO;
SELECT * FROM AUD_MONITOREO_BD ORDER BY 1 DESC FETCH FIRST 10 ROWS ONLY;
-- Llega el correo de inconsistencia al DBA

DROP VIEW V_DEMO_INVALIDA;
ALTER INDEX IX_CUCO_ESTADO_VENCIM REBUILD;
```

### Minuto 10–11: optimización (bloque I)

**Bloque I.**

```sql
EXPLAIN PLAN FOR
SELECT c.ID_CUENTA_COBRAR, cl.CODIGO_CLI, c.FECHA_VENCIM_CUCO, c.SALDO_CUCO
  FROM VEN_CUENTA_COBRAR c JOIN PER_CLIENTE cl ON c.ID_CLIENTE = cl.ID_CLIENTE
 WHERE c.ESTADO_CUCO = 'P' AND c.FECHA_VENCIM_CUCO < SYSDATE;
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

Explique por qué con pocas filas el optimizador elige `FULL` y con muchas usaría `IX_CUCO_ESTADO_VENCIM` (sección 2 de `sql/06_Scheduler_Optimizacion_y_Pruebas.sql`).

### Minuto 11–15: Standby y RMAN (bloque J)

**Bloque J.** Es la sección 11 del [Manual de Administración del Standby](manuales/Manual_Administracion_Standby.md):

1. **PC 1:** estado de los jobs y la última sincronización.

   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_ESTADO_STANDBY;
   ```

2. **PC 1:** la factura `FAC-DEMO-001` del bloque A ya está guardada (con `COMMIT`).
3. **PC 1:** traslado inmediato; se ve el archivelog copiado.

   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_SINCRONIZAR_AHORA;
   SELECT MAX(sequence#) FROM v$archived_log WHERE dest_id = 1;
   ```

4. **PC 2:** aplicar lo recibido y comparar la secuencia (sección 9.1 del manual).

   ```bash
   cd /opt/oracle/proyecto/sql/07_Standby_y_RMAN
   ./02_Traslado_Archivelogs_10min_y_Ondemand.sh aplicarstandby x /opt/oracle/standby_archive x /opt/oracle/standby_backups
   ```

   En Windows: `.\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo AplicarStandby`.

   ```sql
   SELECT MAX(sequence#) FROM v$archived_log WHERE applied = 'YES';   -- igual a la de la PC 1
   SELECT database_role, open_mode FROM v$database;                   -- PHYSICAL STANDBY / MOUNTED
   ```

5. **PC 1:** respaldo RMAN a petición, que se copia a la PC 2.

   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_RESPALDAR_AHORA;
   ```

6. **PC 1:** purga a petición (archivelogs con más de `STANDBY_PURGE_DIAS` días).

   ```sql
   EXEC CADENA_NEG.PKG_ADM_STANDBY.PR_PURGAR_AHORA;
   ```

7. **PC 2:** failover (sección 9.3 del manual) y consultar la factura de prueba en la base activada.

   ```sql
   ALTER DATABASE ACTIVATE STANDBY DATABASE;
   ALTER DATABASE OPEN;
   ALTER PLUGGABLE DATABASE ALL OPEN;
   ALTER SESSION SET CONTAINER = ORCLPDB1;
   SELECT NUM_FACTURA_FAVE, ESTADO_FAVE FROM CADENA_NEG.VEN_FACTURA WHERE NUM_FACTURA_FAVE = 'FAC-DEMO-001';
   ```

> El failover convierte la PC 2 en principal y no tiene vuelta atrás: para volver a tener standby hay que recrearla (sección 4 del manual en sentido inverso). Hágalo al final. Si el académico pide switchover en lugar de failover, siga la sección 9.2 del manual.

Si sobra tiempo, explique la sección 10 del manual (acciones que pueden no replicarse) y la restauración a un punto en el tiempo (`05_RMAN_Restore_Recovery_PointInTime.rman`).
