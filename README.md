# Super Brunca: base de datos Oracle para una cadena de supermercados

Proyecto del curso **Administración de Bases de Datos** (Universidad Nacional, Sede Regional Brunca, II ciclo 2026), Entregable #2.
Estudiantes: Diego Bonilla Mora y Keylor Pineda Alvarez.

## Qué hace

Es una base de datos Oracle (esquema `CADENA_NEG`) para la cadena de supermercados "Super Brunca". Todo está hecho con paquetes PL/SQL, triggers y jobs:

- **Facturación**: ventas y compras. Una factura a crédito crea sola su cuenta por cobrar o por pagar, y cuando se paga completa pasa de pendiente a cancelada. No deja facturar a crédito si se supera el límite.
- **Inventario**: las facturas y devoluciones mueven el inventario solas, y un cambio de costo queda en el historial de precios.
- **Promociones**: acciones por productos patrocinadores, descuentos semanales y premio cada 6 meses a los 10 mejores clientes.
- **Padrón del TSE**: carga el padrón nacional oficial (3,7 millones de personas) y lo enlaza con los clientes. Se actualiza solo cada mes.
- **Seguridad**: perfiles de contraseña, 4 roles protegidos con clave (la clave se guarda cifrada con `DBMS_CRYPTO`) y usuarios con los privilegios mínimos.
- **Bitácoras**: auditoría de cambios, de errores y de operaciones críticas.
- **Notificaciones por correo** con `UTL_SMTP` (directo desde Oracle, sin VPN): créditos al 85 % y al 70 %, clientes morosos, productos vencidos, cierre diario y alertas al DBA.
- **Monitoreo**: tablespaces, objetos inválidos, índices dañados, sesiones y crecimiento.
- **Jobs con `DBMS_SCHEDULER`** para todo lo automático.
- **Servidor Standby** con **Oracle Data Guard** (Oracle 21c Enterprise Edition) en una segunda computadora: el redo viaja por la red y se aplica solo, respaldos RMAN diarios, purga a los 3 días, switchover y failover.

## Carpetas

```
README.md          esta portada
docs/              guías para instalar, cargar el padrón y defender el proyecto
docs/manuales/     los 3 manuales oficiales (.md y .pdf) y el script que genera los PDF
docs/entregable1/  diccionario de datos, documentación técnica y modelo relacional del Entregable #1
docs/modelo/       modelo relacional del Avance 2 en DBML (abrir en https://dbdiagram.io)
docs/enunciado/    enunciado del Entregable #2
sql/               scripts de instalación: script_bd_v2.sql (base) y 00 a 06
sql/08_Wallet_SMTP_Gmail.sh  wallet de certificados para el correo con Gmail (SSL/TLS)
sql/07_Standby_y_RMAN/  standby, RMAN, purga, switchover/failover y sus jobs
sql/07_Standby_y_RMAN/docker/  contenedores ora_principal / ora_standby y archivos de red de Data Guard
datos/padron/      scripts de descarga del padrón del TSE y archivo de muestra
```

## Entorno

Oracle Database 21c Enterprise Edition (imagen Docker `container-registry.oracle.com/database/enterprise:21.3.0.0`). Base `CADENA` con el PDB `PDBCADENA`; la principal corre en el contenedor `ora_principal` y la standby (`CADENA_STBY`) en `ora_standby`.


## Menú para operar el proyecto (recomendado)

En vez de escribir comandos de Oracle, cada uno abre el menú en su PC (PowerShell, en la carpeta del proyecto):

```powershell
powershell -ExecutionPolicy Bypass -File .\menu.ps1
```

El menú detecta solo si en esa PC está `ora_principal` u `ora_standby` y qué rol tiene la base:

| Opción | Para qué | Dónde |
| :---: | :--- | :--- |
| 1 | Ver estado: rol, Data Guard, retraso, objetos inválidos, jobs, padrón | Cualquiera |
| 2 | Arrancar / reanudar la standby después de reiniciar la PC | Standby |
| 3 | Sincronizar ahora (reintenta el envío y muestra el retraso) | Cualquiera |
| 4 | Respaldo RMAN ahora | Principal |
| 5 | Mostrar datos en la standby (solo lectura, sin parar la sincronización) | Standby |
| 6 | Switchover: pasar el rol de principal a la otra PC | Principal |
| 7 | Abrir como nueva principal (después del 6 o del 8) | La otra PC |
| 8 | Failover: la principal se cayó | Standby |
| 9 | Consola SQL ya conectada al proyecto (`PDBCADENA`) | Cualquiera |
| 10 | Consola SYSDBA | Cualquiera |

Las opciones 6 y 8 piden escribir `SI` y se niegan si se eligen en la PC equivocada.
**Switchover con el menú:** principal → 6; la otra PC → 7; la que era principal → 2.
Probado en Oracle 21c EE: estado, sincronización, respaldo, solo lectura y switchover de ida y vuelta.

## Empiece aquí

1. [Guía paso a paso](docs/GUIA_PASO_A_PASO.md): instalar todo desde cero en las dos computadoras.
   - **¿Usted pone la segunda PC (standby)?** Siga [la guía del compañero](docs/GUIA_COMPANERO_PC_STANDBY.md): desde instalar Docker hasta la defensa, paso a paso.
2. [Guía del padrón del TSE](docs/GUIA_PADRON_TSE.md): dónde va el archivo del padrón y cómo cargarlo.
3. [Resumen para la defensa](docs/RESUMEN_DEFENSA.md): cada requerimiento, cómo se hizo y las preguntas probables.
4. [Guía de la defensa](docs/GUIA_DEFENSA.md): qué archivo cumple cada requisito y qué ejecutar en vivo.

Manuales oficiales (los que se entregan):

- [Manual de Instalación y Despliegue](docs/manuales/Manual_Instalacion_y_Despliegue.md) ([PDF](docs/manuales/Manual_Instalacion_y_Despliegue.pdf))
- [Manual de Administración del Standby](docs/manuales/Manual_Administracion_Standby.md) ([PDF](docs/manuales/Manual_Administracion_Standby.pdf))
- [Manual Técnico de Administración y Mantenimiento](docs/manuales/Manual_Tecnico_de_Administracion_y_Mantenimiento.md) ([PDF](docs/manuales/Manual_Tecnico_de_Administracion_y_Mantenimiento.pdf))

Si cambia un manual `.md`, regenere los PDF con `python docs/manuales/generar_manuales_pdf.py` (necesita Microsoft Edge y los paquetes `markdown-it-py` y `pymupdf`).
