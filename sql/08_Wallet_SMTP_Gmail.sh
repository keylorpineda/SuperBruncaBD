#!/bin/bash
# ==============================================================================
# PROYECTO: Sistema Integral de Cadena de Supermercados
# ARCHIVO:  sql/08_Wallet_SMTP_Gmail.sh
# CURSO:    Administracion de Bases de Datos
# DESCRIPCION:
#   Crea el Oracle Wallet que UTL_SMTP necesita para la conexion segura (SSL/TLS)
#   con smtp.gmail.com. Sin el, Oracle 21c responde
#   ORA-29024: Certificate validation failure.
#
#   Toma los certificados raiz de Google (GTS Root R1-R4) y GlobalSign del
#   almacen de certificados del propio Linux: no descarga nada de Internet.
#   El wallet es "auto-login" (cwallet.sso): Oracle lo abre sin clave.
#   Al final registra la ruta en SEG_PARAMETRO (SMTP_WALLET_PATH).
#
# EJECUCION (en el servidor Oracle, como usuario oracle):
#   bash 08_Wallet_SMTP_Gmail.sh [carpeta_del_wallet]
#   Docker: docker exec -u oracle <contenedor> bash /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh
#
# En Windows se hace igual con orapki (ver docs/GUIA_PASO_A_PASO.md).
# ==============================================================================
set -e
WALLET=${1:-$ORACLE_BASE/oradata/wallet_smtp}
BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
[ -f "$BUNDLE" ] || BUNDLE=/etc/ssl/certs/ca-certificates.crt
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "[INFO] Wallet: $WALLET"
mkdir -p "$WALLET"
# Clave solo para administrar el wallet (Oracle lo abre con auto-login)
CLAVE="Wallet$(date +%s)#Smtp"
orapki wallet create -wallet "$WALLET" -pwd "$CLAVE" -auto_login >/dev/null

agregados=0
for nombre in "GTS Root R1" "GTS Root R2" "GTS Root R3" "GTS Root R4" "GlobalSign Root CA"; do
    archivo="$TMP/$(echo "$nombre" | tr ' ' '_').pem"
    # Extrae el bloque PEM que sigue a la linea "# <nombre>" del bundle del sistema
    awk -v n="# $nombre" '$0==n{f=1;next} f&&/BEGIN CERTIFICATE/{p=1} p{print} p&&/END CERTIFICATE/{exit}' "$BUNDLE" > "$archivo"
    if [ -s "$archivo" ]; then
        orapki wallet add -wallet "$WALLET" -trusted_cert -cert "$archivo" -pwd "$CLAVE" >/dev/null 2>&1 \
            && { echo "[OK] Certificado agregado: $nombre"; agregados=$((agregados + 1)); } \
            || echo "[INFO] $nombre ya estaba en el wallet"
    else
        echo "[AVISO] No se encontro '$nombre' en $BUNDLE"
    fi
done
[ "$agregados" -gt 0 ] || { echo "[ERROR] No se agrego ningun certificado"; exit 1; }

# Registrar la ruta en el PDB del proyecto (el primero abierto en READ WRITE)
sqlplus -s / as sysdba <<EOF
SET SERVEROUTPUT ON
DECLARE
    v_pdb VARCHAR2(128);
BEGIN
    SELECT name INTO v_pdb FROM v\$pdbs WHERE open_mode = 'READ WRITE' AND name <> 'PDB\$SEED' AND ROWNUM = 1;
    EXECUTE IMMEDIATE 'ALTER SESSION SET CONTAINER = ' || v_pdb;
    -- Dinamico: el bloque se compila en CDB\$ROOT, donde CADENA_NEG no existe
    EXECUTE IMMEDIATE 'BEGIN CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO(:1, :2, :3, :4, :5, :6); END;'
        USING 'SMTP_WALLET_PATH', 'CORREO', 'Ruta del Oracle Wallet SMTP',
              'Wallet auto-login con los certificados raiz de Gmail para UTL_SMTP (SSL/TLS).', 'N', 'file:$WALLET';
    DBMS_OUTPUT.PUT_LINE('[OK] SMTP_WALLET_PATH = file:$WALLET registrado en ' || v_pdb);
END;
/
EOF
echo "[OK] Wallet listo. Pruebe: EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;"
