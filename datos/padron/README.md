# datos/padron

Scripts para descargar el padrón nacional del TSE y un archivo de muestra:

| Archivo | Para qué sirve |
| :--- | :--- |
| `Descargar_Padron_TSE.ps1` | Windows: descarga `padron_completo.zip` y deja `PADRON_COMPLETO.txt` y `DISTELEC.txt` en la carpeta indicada (`-Destino`). |
| `Descargar_Padron_TSE.sh` | Linux / Docker: lo mismo (`./Descargar_Padron_TSE.sh <url> <carpeta>`). |
| `padron_muestra.csv` | Unas pocas personas inventadas, solo para pruebas. |

El padrón real **no se guarda en el repositorio** (pesa unos 450 MB). Va en la carpeta del directorio Oracle `DIR_PADRON` del servidor.

Todo el procedimiento (dónde va, cómo descargarlo, cargarlo y consultarlo) está en [docs/GUIA_PADRON_TSE.md](../../docs/GUIA_PADRON_TSE.md).
