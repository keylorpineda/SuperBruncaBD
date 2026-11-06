#!/bin/bash
# ==============================================================================
# PROYECTO: Sistema Integral de Cadena de Supermercados
# ARCHIVO:  datos/padron/Descargar_Padron_TSE.sh   (version Linux de Descargar_Padron_TSE.ps1)
# CURSO:    Administracion de Bases de Datos
# DESCRIPCION:
#   Descarga padron_completo.zip del TSE y deja PADRON_COMPLETO.txt, DISTELEC.txt
#   y LEAME.txt en la carpeta de DIR_PADRON para PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO.
#   Lo ejecuta el job CADENA_NEG.JOB_PADRON_DESCARGA o se ejecuta a mano.
#
# USO: ./Descargar_Padron_TSE.sh [URL] DESTINO
#   ./Descargar_Padron_TSE.sh https://www.tse.go.cr/zip/padron/padron_completo.zip /opt/oracle/oradata/FREE/FREEPDB1
# ==============================================================================
set -e
URL=${1:-https://www.tse.go.cr/zip/padron/padron_completo.zip}
DESTINO=${2:?Indique la carpeta de DIR_PADRON}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -d "$DESTINO" ] || { echo "[ERROR] No existe $DESTINO"; exit 1; }

echo "[INFO] Descargando $URL ..."
if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$TMP/padron.zip" "$URL"
else wget -q -O "$TMP/padron.zip" "$URL"; fi
echo "[OK] Descargado: $(du -h "$TMP/padron.zip" | cut -f1)"

if command -v unzip >/dev/null 2>&1; then unzip -q -o "$TMP/padron.zip" -d "$TMP"
elif command -v python3 >/dev/null 2>&1; then python3 -m zipfile -e "$TMP/padron.zip" "$TMP"
else echo "[ERROR] Se necesita unzip o python3"; exit 1; fi

copiar() {   # copiar <patron> <nombre_final> <obligatorio>
    local f
    f=$(find "$TMP" -type f -iname "$1" ! -iname "*.zip" -printf '%s %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -n "$f" ]; then cp -f "$f" "$DESTINO/$2"; echo "[OK] $(basename "$f") -> $2"
    elif [ "$3" = "si" ]; then echo "[ERROR] El ZIP no contiene $1"; exit 1; fi
}
copiar "*PADRON*.txt"   PADRON_COMPLETO.txt si
copiar "*DISTELEC*.txt" DISTELEC.txt        si
copiar "*LEAME*.txt"    LEAME.txt           no
echo "[OK] Padron listo en $DESTINO. Siguiente paso: EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;"
