#!/bin/bash
# ==============================================================================
# PROYECTO: Sistema Integral de Cadena de Supermercados
# MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai (Linux)
# ARCHIVO:  07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh
# CURSO:    Administracion de Bases de Datos
# DESCRIPCION:
#   Version Linux del orquestador de tareas del Standby (equivalente al .ps1).
#   La invocan los jobs DBMS_SCHEDULER (EXECUTABLE) de CADENA_NEG.PKG_ADM_STANDBY,
#   que le pasan los valores de SEG_PARAMETRO como argumentos posicionales:
#
#   $1 MODO           ondemand | archivelogs | backup | purga | purgastandby | continuo
#   $2 RUTA_ORIGEN    archivelogs de la principal       (STANDBY_RUTA_ARCHIVE_ORIGEN)
#   $3 RUTA_DESTINO   destino en el standby             (STANDBY_RUTA_ARCHIVE_DESTINO)
#                     admite ruta remota rsync: oracle@pc-standby:/opt/oracle/standby_archive
#   $4 RUTA_BACKUPS   respaldos RMAN de la principal    (STANDBY_RUTA_BACKUP_ORIGEN)
#   $5 RUTA_BK_STBY   destino de respaldos en standby   (STANDBY_RUTA_BACKUP_DESTINO)
#   $6 DIAS           dias de retencion                 (STANDBY_PURGE_DIAS)
#   $7 ORACLE_SID     $8 ORACLE_HOME                    $9 INTERVALO_MIN (STANDBY_SYNC_MIN)
#
# EJEMPLOS:
#   ./02_Traslado_Archivelogs_10min_y_Ondemand.sh ondemand
#   ./02_Traslado_Archivelogs_10min_y_Ondemand.sh backup
# ==============================================================================

MODO=${1:-ondemand}
RUTA_ORIGEN=${2:-/opt/oracle/fast_recovery_area/CADENA/archivelog}
RUTA_DESTINO=${3:-oracle@pc-standby:/opt/oracle/standby_archive}
RUTA_BACKUPS=${4:-/opt/oracle/backups}
RUTA_BK_STBY=${5:-oracle@pc-standby:/opt/oracle/standby_backups}
DIAS=${6:-3}
[ -n "${7// /}" ] && export ORACLE_SID="$7"
[ -n "${8// /}" ] && export ORACLE_HOME="$8" && export PATH="$ORACLE_HOME/bin:$PATH"
INTERVALO_MIN=${9:-10}
NIVEL_BACKUP=${NIVEL_BACKUP:--1}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR=/opt/oracle/logs
LOG_FILE="$LOG_DIR/standby_orquestador.log"
mkdir -p "$LOG_DIR"
HUBO_ERROR=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$MODO] $1" | tee -a "$LOG_FILE"; }

ejecutar_rman() {
    local archivo="$1"; shift
    local bitacora="$LOG_DIR/rman_${archivo%.rman}_$(date '+%Y%m%d_%H%M%S').log"
    log "RMAN: $archivo USING $*"
    if rman target / cmdfile="$SCRIPT_DIR/$archivo" log="$bitacora" using "$@" >/dev/null; then
        log "[OK] RMAN finalizo correctamente. Bitacora: $bitacora"
    else
        HUBO_ERROR=1; log "[ERROR] RMAN fallo. Revise $bitacora"
    fi
}

forzar_archive_log() {
    if command -v sqlplus >/dev/null 2>&1; then
        sqlplus -S / as sysdba <<EOF >/dev/null 2>&1 && log "[OK] ARCHIVE LOG CURRENT ejecutado." || log "[AVISO] No se pudo forzar el archive log."
WHENEVER SQLERROR EXIT 1;
ALTER SYSTEM ARCHIVE LOG CURRENT;
EXIT;
EOF
    else
        log "[AVISO] sqlplus no esta en el PATH."
    fi
}

# Copia incremental (rsync solo envia archivos nuevos o modificados)
copiar_nuevos() {
    local origen="$1" destino="$2" descripcion="$3"; shift 3
    if [ ! -d "$origen" ]; then log "[AVISO] No existe $origen"; return; fi
    case "$destino" in *:*) ;; *) mkdir -p "$destino" ;; esac
    if rsync -a "$@" "$origen/" "$destino/" >>"$LOG_FILE" 2>&1; then
        log "[OK] $descripcion trasladados a $destino"
    else
        HUBO_ERROR=1; log "[ERROR] Fallo el traslado de $descripcion hacia $destino"
    fi
}

tarea_traslado() {
    log ">>> TRASLADO HACIA EL STANDBY"
    forzar_archive_log
    copiar_nuevos "$RUTA_ORIGEN"  "$RUTA_DESTINO" "Archivelogs"
    copiar_nuevos "$RUTA_BACKUPS" "$RUTA_BK_STBY" "Respaldos RMAN" --include='*.bkp' --exclude='*'
}

tarea_backup() {
    local nivel="$NIVEL_BACKUP"
    if [ "$nivel" -lt 0 ]; then [ "$(date +%u)" -eq 7 ] && nivel=0 || nivel=1; fi
    log ">>> RESPALDO RMAN NIVEL $nivel"
    mkdir -p "$RUTA_BACKUPS"
    ejecutar_rman 04_RMAN_Backup_Full_Incremental.rman "'$RUTA_BACKUPS'" "$nivel"
    copiar_nuevos "$RUTA_BACKUPS" "$RUTA_BK_STBY" "Respaldos RMAN" --include='*.bkp' --exclude='*'
}

log "========== INICIO (SID=$ORACLE_SID) =========="
case "$MODO" in
    ondemand|archivelogs|cron) tarea_traslado ;;
    backup)       tarea_backup ;;
    purga)        log ">>> PURGA EN LA PRINCIPAL (> $DIAS dias)"
                  ejecutar_rman 03_Purga_Archivelogs_3Dias.rman "$DIAS" ;;
    purgastandby) log ">>> PURGA EN EL STANDBY (> $DIAS dias)"
                  ejecutar_rman 03_Purga_Archivelogs_Standby.rman "$DIAS" "'$RUTA_DESTINO'" ;;
    continuo)     while true; do tarea_traslado; log "Esperando $INTERVALO_MIN min..."; sleep $((INTERVALO_MIN * 60)); done ;;
    *)            log "[ERROR] Modo desconocido: $MODO"; HUBO_ERROR=1 ;;
esac
log "========== FIN =========="
exit $HUBO_ERROR
