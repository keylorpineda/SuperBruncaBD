#!/bin/bash
# ==============================================================================
# PROYECTO: Sistema Integral de Cadena de Supermercados
# MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c EE (compatible con 26ai Free) (Linux)
# ARCHIVO:  sql/07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.sh
# CURSO:    Administracion de Bases de Datos
# DESCRIPCION:
#   Version Linux del orquestador de tareas del Standby (equivalente al .ps1).
#   La invocan los jobs DBMS_SCHEDULER (EXECUTABLE) de CADENA_NEG.PKG_ADM_STANDBY,
#   que le pasan los valores de SEG_PARAMETRO como argumentos posicionales:
#
#   $1 MODO           principal: ondemand | archivelogs | backup | purga | continuo
#                     PC standby: crearstandby | aplicarstandby | purgastandby
#                     (en la PC standby se programan con cron, p.ej.:
#                      */10 * * * * /opt/oracle/proyecto/sql/07_Standby_y_RMAN/02_...sh aplicarstandby x /opt/oracle/standby_archive x /opt/oracle/standby_backups
#                      30 3 * * *   /opt/oracle/proyecto/sql/07_Standby_y_RMAN/02_...sh purgastandby  x /opt/oracle/standby_archive x x 3)
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

# RMAN-06054 (pide un archivelog que aun no llega) solo es un exito si la unica falla
# de RMAN es la del RECOVER y no hay ningun error ORA-. Se busca al INICIO de linea porque la bitacora de RMAN
# tambien repite los comentarios del .rman (que mencionan RMAN-06054) y asi un
# RESTORE fallido seguido de un RECOVER no se puede confundir con exito.
sincronizado_ok() {
    local b="$1"
    grep -q "^RMAN-06054:" "$b" || return 1
    grep -q "^RMAN-03002:" "$b" || return 1
    grep "^RMAN-03002:" "$b" | grep -v "failure of recover command" | grep -q . && return 1
    # Cualquier ORA- al inicio de linea (ORA-01153, ORA-01155, ORA-19505...) es una falla real
    grep -q -E "^(RMAN-06026|RMAN-06023|RMAN-03009|ORA-)|failure of restore command" "$b" && return 1
    return 0
}

ejecutar_rman() {
    local archivo="$1"; shift
    local bitacora="$LOG_DIR/rman_${archivo%.rman}_$(date '+%Y%m%d_%H%M%S').log"
    log "RMAN: $archivo USING $*"
    if rman target / cmdfile="$SCRIPT_DIR/$archivo" log="$bitacora" using "$@" >/dev/null; then
        log "[OK] RMAN finalizo correctamente. Bitacora: $bitacora"
    elif [ "$APLICA_REDO" = "1" ] && sincronizado_ok "$bitacora"; then
        # RMAN-06054 = pide un archivelog que aun no llega: todo lo recibido ya se aplico
        log "[OK] Standby sincronizado (RMAN-06054 esperado). Bitacora: $bitacora"
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

# Traslado por la red de Oracle (Data Guard / 21c EE): DBMS_FILE_TRANSFER.PUT_FILE
# por el database link indicado ("oracle:LNK_STANDBY"). No necesita carpetas
# compartidas ni ssh: usa la misma conexion 1521 que Data Guard.
# Requiere los directorios DIR_RESPALDOS / DIR_RESPALDOS_STBY y el enlace, creados
# una vez con 10_Enlace_Respaldos_DataGuard.sql. La standby debe estar abierta
# en solo lectura (READ ONLY WITH APPLY) para aceptar la conexion del enlace.
transferir_oracle() {
    local origen="$1" enlace="${2#oracle:}" descripcion="$3"; shift 3
    local total=0 copiados=0 f nombre salida expr=()
    for p in "$@"; do [ ${#expr[@]} -gt 0 ] && expr+=(-o); expr+=(-name "$p"); done
    while IFS= read -r f; do
        total=$((total + 1)); nombre=$(basename "$f")
        salida=$(sqlplus -s / as sysdba <<EOF 2>&1
WHENEVER SQLERROR EXIT 1
EXEC DBMS_FILE_TRANSFER.PUT_FILE('DIR_RESPALDOS', '$nombre', 'DIR_RESPALDOS_STBY', '$nombre', '$enlace');
EXIT
EOF
)
        if [ $? -eq 0 ]; then copiados=$((copiados + 1)); log "  -> $nombre (por $enlace)"
        elif echo "$salida" | grep -q "ORA-27038"; then :   # ya estaba en la standby
        else HUBO_ERROR=1; log "[ERROR] $nombre: $(echo "$salida" | grep -m1 ORA-)"; fi
    done < <(find "$origen/" -maxdepth 1 -type f \( "${expr[@]}" \))
    log "[OK] $descripcion: $copiados nuevo(s) de $total enviado(s) a la standby por $enlace"
}

# Copia incremental: solo archivos nuevos o con tamano distinto.
# Destino local (cp), remoto "usuario@host:/ruta" (scp; se recuerda lo enviado),
# "oracle:<enlace>" (por la red de Oracle) o "dataguard" (no copia: Data Guard ya
# envia los archivelogs por LOG_ARCHIVE_DEST_2).
# Uso: copiar_nuevos <origen> <destino> <descripcion> <patron> [patron...]
copiar_nuevos() {
    local origen="$1" destino="$2" descripcion="$3"; shift 3
    local enviados="$LOG_DIR/enviados_standby.lst" total=0 copiados=0 f nombre expr=()
    if [ ! -d "$origen" ]; then log "[AVISO] No existe $origen"; return; fi
    case "$destino" in
        dataguard) log "[OK] $descripcion: los envia Data Guard automaticamente (LOG_ARCHIVE_DEST_2)"; return ;;
        oracle:*)  transferir_oracle "$origen" "$destino" "$descripcion" "$@"; return ;;
    esac
    case "$destino" in *:*) ;; *) mkdir -p "$destino" ;; esac
    touch "$enviados"
    for p in "$@"; do [ ${#expr[@]} -gt 0 ] && expr+=(-o); expr+=(-name "$p"); done
    while IFS= read -r f; do
        total=$((total + 1)); nombre=$(basename "$f")
        case "$destino" in
            *:*) grep -qxF "$destino/$nombre" "$enviados" && continue
                 if scp -q -o BatchMode=yes "$f" "$destino/"; then echo "$destino/$nombre" >> "$enviados"
                 else HUBO_ERROR=1; log "[ERROR] scp fallo: $nombre"; continue; fi ;;
            *)   [ -f "$destino/$nombre" ] && [ "$(stat -c %s "$f")" = "$(stat -c %s "$destino/$nombre")" ] && continue
                 cp -f "$f" "$destino/" || { HUBO_ERROR=1; log "[ERROR] cp fallo: $nombre"; continue; } ;;
        esac
        copiados=$((copiados + 1)); log "  -> $nombre"
    done < <(find "$origen/" -type f \( "${expr[@]}" \))   # "/" final: sigue el enlace dbs de Docker
    log "[OK] $descripcion: $copiados nuevo(s) de $total trasladado(s) a $destino"
}

tarea_traslado() {
    log ">>> TRASLADO HACIA EL STANDBY"
    forzar_archive_log
    copiar_nuevos "$RUTA_ORIGEN"  "$RUTA_DESTINO" "Archivelogs" '*.arc' 'arch*.dbf'
    copiar_nuevos "$RUTA_BACKUPS" "$RUTA_BK_STBY" "Respaldos RMAN" '*.bkp'
}

tarea_backup() {
    local nivel="$NIVEL_BACKUP"
    if [ "$nivel" -lt 0 ]; then [ "$(date +%u)" -eq 7 ] && nivel=0 || nivel=1; fi
    log ">>> RESPALDO RMAN NIVEL $nivel"
    mkdir -p "$RUTA_BACKUPS"
    ejecutar_rman 04_RMAN_Backup_Full_Incremental.rman "'$RUTA_BACKUPS'" "$nivel"
    copiar_nuevos "$RUTA_BACKUPS" "$RUTA_BK_STBY" "Respaldos RMAN" '*.bkp'
}

log "========== INICIO (SID=$ORACLE_SID) =========="
case "$MODO" in
    ondemand|archivelogs|cron) tarea_traslado ;;
    backup)       tarea_backup ;;
    purga)        log ">>> PURGA EN LA PRINCIPAL (> $DIAS dias)"
                  ejecutar_rman 03_Purga_Archivelogs_3Dias.rman "$DIAS" ;;
    crearstandby) CTRL=$(ls -t "$RUTA_BK_STBY"/bkp_ctrl_stby_*.bkp 2>/dev/null | head -1)
                  if [ -z "$CTRL" ]; then log "[ERROR] No hay bkp_ctrl_stby_*.bkp en $RUTA_BK_STBY"; HUBO_ERROR=1
                  else log ">>> CREACION DEL STANDBY desde $CTRL"; APLICA_REDO=1
                       ejecutar_rman 08_Creacion_Standby_Segunda_PC.rman "'$CTRL'" "'$RUTA_BK_STBY'"; fi ;;
    aplicarstandby) log ">>> SINCRONIZACION: aplicando archivelogs de $RUTA_DESTINO"; APLICA_REDO=1
                  ejecutar_rman 09_Aplicar_Archivelogs_Standby.rman "'$RUTA_DESTINO'" ;;
    purgastandby) log ">>> PURGA EN EL STANDBY (> $DIAS dias)"
                  ejecutar_rman 03_Purga_Archivelogs_Standby.rman "$DIAS" "'$RUTA_DESTINO'" ;;
    continuo)     while true; do tarea_traslado; log "Esperando $INTERVALO_MIN min..."; sleep $((INTERVALO_MIN * 60)); done ;;
    *)            log "[ERROR] Modo desconocido: $MODO"; HUBO_ERROR=1 ;;
esac
log "========== FIN =========="
exit $HUBO_ERROR
