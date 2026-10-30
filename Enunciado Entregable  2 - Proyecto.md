UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

## **Enunciado Proyecto** 

## **Objetivos** 

- Aplicar de manera práctica los conocimientos adquiridos sobre el diseño y administración de las bases de datos, mediante la confección de soluciones reales para administrar funcionalidad, seguridad y el manejo de notificaciones. 

- Aplicar de manera práctica los conocimientos adquiridos sobre la administración de base de datos, mediante la implementación de un servidor de respaldo para una base de datos. 

## **Descripción del proyecto** 

El proyecto se dividirá en dos entregables los cuales se explicarán a continuación: 

# **_Segunda Parte: Entregable #2._** 

Se debe desarrollar un sistema que implemente funciones y seguridad, además de enviar notificaciones al administrador de base de datos cuando ocurran problemas en consistencia de datos, estructura o que simplemente la base de datos necesita mantenimiento. 

Se debe implementar una base de datos standby, previendo cualquier inconveniente con la base de datos principal, así como la administración de esta. 

## **Ambiente para desarrollar la aplicación** 

Para la realización de este proyecto es necesaria la base de datos corregida del primer avance del proyecto del curso. 

Segunda parte: **en parejas** . 

## **Funcionalidades por implementar:** 

- ✓ Cuando se ingrese una factura en estado pendiente de cancelar, aumentar automáticamente el saldo del cliente que debe el cliente y agregar esta factura al detalle, cuentas por cobrar. 

- ✓ La factura a los proveedores también debe aumentar automáticamente el saldo que se le debe en caso de ser una factura pendiente de pago, cuentas por pagar. 

UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

- ✓ Cuando una factura sea cancelada totalmente, deberá automáticamente cambiar el estado de pendiente a cancelada. 

- ✓ Para agregarle un mayor valor agregado a la aplicación, es necesario cargar el padrón nacional en la base de datos, se requiere adaptar el modelo y cargar el padrón con la información actual en la base de datos, esta tabla se enlazará a la de clientes, para obtener los datos básicos de las personas (se debe investigar para crear un procedimiento que cargue automáticamente el padrón). 

- ✓ Cada vez que se realice una factura se deberá modificar automáticamente el inventario, aplica para facturas de proveedores y facturas a clientes. 

- ✓ Cuando exista una devolución, se deberá modificar automáticamente el inventario también. 

- ✓ Cuando ingrese un producto con un precio de costo diferente al actual, es necesario incluir automáticamente este cambio de precio al historial de precios. 

- ✓ Deberán existir limitantes a la hora de facturar y dejar el estado pendiente de pago, en caso de superar los límites no debe permitir guardar la factura con ese estado, aplica tanto para proveedores como para clientes. 

- ✓ En miras de ayudar al departamento de mercadeo se solicita implementar un procedimiento que se ejecute cada semana, el cual me indique por separado cuales de los productos que están por vencerse (a una semana), cuales tienen más de 6 meses de estar en bodega. Se le debe notificar al coordinador 

- ✓ Deben existir tipos de promociones, por ejemplo, existe promociones que brindan acciones de acuerdo con la cantidad de productos patrocinadores, se requiere que automáticamente muestre cuántas acciones se le deben de otorgar, la cantidad de productos patrocinadores necesarios para una acción se define en la misma tabla de promociones. 

- ✓ Se requiere que una vez a la semana se verifique los descuentos planeados, si se define uno para productos cerca de vencer o bien para productos con mucha antigüedad, incluir los productos al detalle automáticamente. 

- ✓ Se requiere premiar a los mejores clientes de la empresa, por este motivo, se deben obtener los 10 clientes que más compren en la empresa y darles una orden de compra por 100 mil colones (parametrizado), este proceso se ejecutará una vez cada 6 meses (debe estar parametrizado), se le notificará al coordinador de los clientes seleccionados. 

- ✓ A la gerencia de la empresa le preocupa la integridad de la información, se solicita crear las bitácoras para las tablas principales: 

   - Facturación 

   - Cambio de precios 

UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

   - Movimientos en inventarios 

   - Clientes 

   - Proveedores 

   - Promociones 

   - Descuentos 

- ✓ Las notificaciones serán parametrizadas (correo, clave, correo(s) al cual notificar) 

- ✓ La clave de correo debe estar encriptado, para brindarle mayor seguridad al envío de notificaciones. 

- ✓ El envío de correo no podrá ser utilizado mediante un VPN, debe realizarse directamente desde Oracle. 

## **Seguridad por implementar** 

- ✓ Se requiere implementar seguridad a nivel de base de datos con: perfiles, roles y usuarios. 

   - Los roles deben de ser como mínimo: Gerente, Jefe Departamento, Jefe Proveeduría, Digitador. 

- ✓ Con respecto a los roles, es necesario crearle seguridad por medio de clave, esta clave debe de estar encriptada dentro de la base de datos en alguna tabla de parámetros. 

   - Al contar con seguridad por password en roles es necesario implementar procedimientos que asignen la clave a los roles para poder utilizar los permisos de forma correcta. 

## **Notificaciones por realizar** 

- ✓ Realizar un proceso que notifique a los clientes que cuenten con un 85% o más de su saldo permitido en las cuentas por cobrar, por ejemplo, si el límite del cliente es de 100 mil colones enviar la notificación cuando deba 85 mil o más. 

- ✓ Realizar un proceso que notifique al coordinador con todos los clientes que estén con un 85% o más del saldo permitido en las cuentas por pagar. 

- ✓ Realizar un proceso que notifique al gerente cuando este cerca de un 70% del límite permitido en las cuentas por pagar a proveedores, la notificación debe ser una sola y que incluya a todos los proveedores. 

- ✓ Notificar al gerente, coordinador cuando exista un cliente que tenga saldo pendiente y su último pago haya sido realizado con más de un mes de antigüedad. 

UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

- ✓ Notificar al coordinador una lista de productos vencidos, esta notificación deberá incluir también un total, para que el coordinador defina qué hacer con ellos. 

- ✓ Se deberá incluir un proceso para realizar los cierres diarios, este cierre se ejecutará automáticamente y el resultado se notificará al coordinador y gerente (un cierre es necesario, incluir los detalles básicos como fecha, cantidad vendida, devoluciones y total, en el detalle del cierre se incluirá el cajero y cantidad vendida y devoluciones) [Implica modificar la base de datos actual]. 

- ✓ Verificar el tamaño de los tablespace, el cual no debe de exceder en un 85% su tamaño. Este proceso se ejecutará todos los días, notificar en caso de que exista inconsistencia. 

- ✓ Verifica si existen objetos inválidos. Este proceso se ejecutará todos los días, notificar en caso de que exista inconsistencia. 

- ✓ En ocasiones los índices se dañan, verificar y notificar cuando esto sucede. Este proceso se ejecutará todos los días, notificar en caso de que exista inconsistencia. 

## **Funcionalidad del StandBy** 

- ✓ Deben ser dos servidores distintos, un servidor como principal y otro como standby. 

- ✓ Debe existir un archivo de actualización cada 5 minutos o bien cada 50 MB (parametrizado), sin necesidad de la intervención del DBA. 

- ✓ Se debe trasladar la información de un servidor al otro cada 10 minutos (parametrizado). Debe existir la forma de que al realizar las revisiones, se pueda generar en el momento que el académico lo decida. 

- ✓ Se utilizará base de datos Oracle 21c  y sistema operativo Linux o Windows. 

- ✓ Eliminar los archivos de información que están en el servidor principal que ya fueron pasados al standby, así como los archivos de información que ya fueron aplicados en el servidor standby con un rango de 3 días (parametrizado). 

- ✓ Es requerido que la base de datos realice automáticamente un respaldo diario de la base de datos principal, este respaldo también se debe trasladar al servidor de la base de datos standby. De igual manera, el proceso se ejecutará a petición del académico, al momento de la revisión. 

UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

## **Notas Generales** 

- ✓ Se debe generar un documento con el paso a paso de la implementación (manual de instalación) así como la solución dada para solucionar todos los requerimientos. 

   - Este manual debe contar con una explicación de los conceptos y la manera de utilizarlos. 

   - En caso de que la implementación sea defectuosa o tenga algún problema, el manual también será castigado, ya que no es un manual 100% funcional. 

- ✓ Se debe tomar en cuenta que es necesario replicar todas las acciones de la base de datos principal en la standby. En caso de que exista alguna acción que genere inconvenientes. Brindar una solución y un manual de cómo actuar ante tal situación. 

- ✓ Se debe presentar la implementación funcional. 

## **Requerimientos de Base de Datos** 

1. Arquitectura: toda la arquitectura del sistema deberá ser desarrollo en paquetes de bases de datos, pueden ser identificados por modulos si así lo desean. Cada paquete deberá contener procedimientos y/o funciones. 

2. Transacciones: todas las operaciones críticas deberán manejar: commit – rollback – savepoint. 

3. Excepciones: cada procedimiento y/o función de base de datos deberá implementar el manejo correcto de excepciones. 

4. Auditoría: manejo completo de un proceso de auditoría, incluir las tablas del primer avance más el manejo por medio de triggers, para su ejecución. 

5. Scheduler: todos los procesos automáticos (jobs) deberán ser implementados por medio de oracle scheduler (DBMS_SCHEDULER). Incluir la documentación necesaria en el manual ya indicado. 

6. Seguridad: 

   - a. Password: Con respecto a la implementación ya indicada del primer avance, debe ampliarse al implementar manejo de password profile (tiempos de expiración, intentos fallidos, bloqueo automático, reutilización de contraseñas). 

   - b. Roles: Con respecto a los roles, crear permisos mínimos requeridos, no utilizar los roles de DBA, CONNECT, RESOURCE. 

   - c. Privilegios: Con respecto a los privilegios el poder identificar y diferencias entre system privileges y object privileges. 

UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

7. Cifrado: utilizar el DBMS_CRYPTO para cifrar información sencible como claves, tokens, configuraciones. 

8. Optimización SQL: usar EXPLAIN_PLAN, para analizar costos, índices utilizados a las consultas definidas en los requerimientos funcionales. 

9. Vistas materializadas: implementar dos: 

   - a. Ventas mensuales 

   - b. Inventario consolidado 

10. Parametrización: todo lo indicado y etiquetado como “parametrizado” en los dos enunciados debe estar debidamente registrado en tablas para una mayor facilidad de ajuste de los parámetros. 

11. Concurrencia: implementar concurrencia mediante SELECT FOR UPDATE, NOWAIT, WAIT para evitar conflictos. 

12. Integridad: cuando una regla o funcionalidad no pueda implementarse mediante restricciones SQL, deberán definirse por medio de packages o triggers. 

13. Monitoreo: crear el paquete de monitoreo, donde se maneje crecimiento de la base de datos, uso de tablespace, sesiones y errores. 

14. Stanby: adicional a la implementación del stanby, incluir demostración de failover, switchover, recuperación, sincronización. 

15. RMAN: implementar backup full, backup incremental, restore, recovery. 

## **Notas Entregable #2** 

- ➢ El código del programa debe tener documentación interna. 

- ➢ El día de la entrega se presentará al académico el sistema en ejecución. 

- ➢ Se calificará nuevamente el modelo relacional de la base de datos. 

- ➢ Las notificaciones serán a un correo externo definido antes de la defensa. 

## **Calificación – Entregable #2** 

|**Rubro**|**Valor**||**Descripción**|**Valor**|
|---|---|---|---|---|
|**Arquitectura**<br>**e**||25%|Arquitectura|8%|
|**implementación**|||Proc/Func<br>Almacenadas|12%|
||||Manejo transaccional y<br>excepciones|2,5%|
||||Triggers|2,5%|
|**Administración**||20%|Seguridad<br>(usuarios,<br>roles, privilegios)|5%|
||||Automatizaciones<br>(scheduler)|5%|
||||Auditoría – bitácoras|5%|



UNIVERSIDAD NACIONAL SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

|||Monitoreo<br>(tablespaces,<br>objetos<br>inválidos,<br>índices,<br>sesiones)|5%|
|---|---|---|---|
|**Disponibilidad**<br>**y**<br>**recuperación**<br>**(Standby)**|35%|Implementación<br>y<br>configuración<br>(Standby)|20%|
|||Administración,<br>sincronización<br>y|5%|
|||monitoreo<br>de<br>la<br>Standby||
|||Estrategia de respaldo<br>y recuperación (RMAN<br>y/o scripts)|5%|
|||Procedimientos<br>de<br>recuperación, failover y<br>switchover|5%|
|**Documentación**|10%|Documentación<br>del<br>código|3%|
|||Manual de instalación y<br>despliegue|3%|
|||Manual<br>de<br>administración<br>del<br>Standby|2%|
|||Manual<br>técnico<br>de<br>administración<br>y<br>mantenimiento|2%|
|**Defensa**|**10%**|**Defensa delproyecto**|**10%**|
|**Total **|**100%**||**100%**|



## **Escala Funcionamiento** 

|**Requerimiento**<br>|**Detalle**<br>**Valor **<br>||
|---|---|---|
|**Funcionalidad**<br>**del**<br>**negocio**<br>**(40%)**<br>|Actualización<br>automática<br>de<br>cuentas porcobrar<br>|4%<br>|
||Actualización<br>automática<br>de<br>cuentas porpagar<br>|4%<br><br>||
||Cambio automático del estado<br>delasfacturas|3%<br>||
||Integración del Padrón Nacional<br>y adaptacióndel modelo|6%<br>~~|~~|
||Actualización<br>automática<br>del<br>inventario (ventas, compras y<br>devoluciones)|5%<br>||
||Historialautomático de precios|3%|
||Validacióndelímites de crédito|4%|
||Administración automática de<br>promociones|4%|
||Administraciónautomática de|3%|



UNIVERSIDAD NACIONAL ) SEDE REGIONAL BRUNCA CAMPUS: PZ - COTO caterse 02S PROF. HAIROL ROMERO – JEREMY ELIZONDO CURSO: ADMINISTRACIÓN DE B.D.                                                                     II CICLO 2026 

||descuentos p|rogra|mados||
|---|---|---|---|---|
||Generación<br>clientes pre|auto<br>miados|mática<br>de|4%|
|**Seguridad (15%)**|Usuarios,<br>privilegios|roles|,<br>perfiles,|8%|
||Contraseñas|||4%|
||Admin.de pr|ivilegi|os|3%|
|**Automatización (15%)**|Productos pr|óximo|s a vencer|3%|
||Productos<br>mayora 6m|con<br>eses|antigüedad|3%|
||Cierre diario|autom|ático|4%|
||Procesos||programados|5%|
||funcionando|correc|tamente||
|**Auditorías – bitácoras (10%)**|Bitácora de c|ambio|s|4%|
||Bitácora de e|rrores||3%|
||Auditoría<br>críticas|de|operaciones|3%|
|**Notificaciones (10%)**|Clientes con|límite|de crédito|2%|
||Proveedores<br>crédito|<br>con|<br>límite<br>de|2%|
||Clientesmor|osos||2%|
||Productos ve|ncido|s|2%|
||Notificacione<br>correctamen|s<br>te|agrupadas|2%|
|**Monitoreo (10%)**|Verificación<br>Tablespaces|del|<br>uso<br>de|3%|
||Verificación|de obj|etosinválidos|2%|
||Verificación<br>índices|del|estado<br>de|2%|
||Monitoreo<br>recursos crít|de<br>icos|sesiones<br>o|3%|



### **Fechas Importantes:** 

### **Entrega Segundo Avance:** 

Lunes 09 noviembre 2026 (PZ) – Martes 10 noviembre 2026 (Coto) 

