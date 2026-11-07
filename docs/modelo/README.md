# Modelo relacional (Avance 2)

`modelo_relacional_avance2.dbml` es el modelo completo del esquema `CADENA_NEG`, generado
desde la base real (Oracle 21c EE) con el diccionario de datos: 61 tablas, 104 relaciones
(9 de ellas compuestas), comentarios de cada tabla y columna, y las 12 tablas nuevas del
Avance 2 marcadas con `[AVANCE 2]` en su nota.

**Cómo abrirlo:** entre a https://dbdiagram.io, cree un diagrama nuevo, borre el ejemplo y
pegue el contenido del archivo (o *Import → DBML*). Las tablas quedan agrupadas por módulo
(`TableGroup`: AUD, CAT, COM, INV, PER, PRM, PRO, SEG, VEN).

Avisos normales del editor: "Mismatched optional ref constraints" en llaves foráneas que
permiten nulos (por ejemplo `CAT_PADRON.ID_DISTRITO`, que es opcional a propósito). No son errores.

No incluye las tablas externas `EXT_PADRON_TSE` / `EXT_DISTELEC_TSE` (leen archivos del TSE,
no guardan datos) ni las vistas.
