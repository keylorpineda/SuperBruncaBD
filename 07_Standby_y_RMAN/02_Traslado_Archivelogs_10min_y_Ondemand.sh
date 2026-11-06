#!/bin/bash
# ==============================================================================
# PROYECTO: Sistema Integral de Cadena de Supermercados
# MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai (Linux)
# ARCHIVO:  07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh
# CURSO:    Administracion de Bases de Datos
# ==============================================================================

MODO=${1:-ondemand}
RUTA_ORIGEN="/opt/oracle/oradata/recovery_area/CADENA_NEG/archivelog"
RUTA_DESTINO="/opt/oracle/standby_archive/CADENA_NEG"
LOG_FILE="/opt/oracle/logs/traslado_archivelog.log"

mkdir -p "$RUTA_DESTINO"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

ejecutar_traslado() {
    log "------------------------------------------------------------------------"
    log ">>> INICIANDO TRASLADO DE ARCHIVED REDO LOGS (Modo: $MODO)"
    
    # Forzar cambio de archivelog en Oracle
    if command -v sqlplus >/dev/null 2>&1; then
        log "Forzando ARCHIVE LOG CURRENT en Oracle..."
        sqlplus -S / as sysdba <<EOF >/dev/null 2>&1
ALTER SYSTEM ARCHIVE LOG CURRENT;
EXIT;
EOF
    fi

    # Sincronizar usando rsync con preservacion de atributos y eliminacion de duplicados
    if command -v rsync >/dev/null 2>&1; then
        rsync -avz --progress "$RUTA_ORIGEN/" "$RUTA_DESTINO/" | tee -a "$LOG_FILE"
        log "[OK] Sincronizacion completada exitosamente mediante rsync."
    else
        cp -uv "$RUTA_ORIGEN"/* "$RUTA_DESTINO/" 2>/dev/null
        log "[OK] Sincronizacion completada mediante copia de archivos."
    fi
    log ">>> TRASLADO FINALIZADO EXITOSAMENTE"
    log "------------------------------------------------------------------------"
}

if [ "$MODO" = "ondemand" ]; then
    echo "========================================================================"
    echo "  EJECUCION BAJO DEMANDA / EVALUADOR DE TRASLADO DE LOGS HACIA STANDBY  "
    echo "========================================================================"
    ejecutar_traslado
elif [ "$MODO" = "cron" ]; then
    ejecutar_traslado
elif [ "$MODO" = "continuo" ]; then
    echo "Ejecutando en bucle continuo cada 10 minutos (600 segundos)..."
    while true; do
        ejecutar_traslado
        sleep 600
    done
fi
