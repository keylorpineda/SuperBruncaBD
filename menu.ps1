<#
================================================================================
PROYECTO: Sistema Integral de Cadena de Supermercados (Super Brunca)
ARCHIVO:  menu.ps1
CURSO:    Administracion de Bases de Datos
DESCRIPCION:
  Menu para operar el proyecto sin escribir comandos de Oracle a mano.
  Funciona en las dos PC: detecta si en esta PC esta el contenedor
  ora_principal o ora_standby y si la base es la principal o la standby.

  Cada orden SQL se guarda en un archivo temporal, se copia al contenedor y
  ahi se ejecuta con sqlplus: asi se evitan los problemas de PowerShell con
  las comillas y con el simbolo $.

USO (PowerShell, en la carpeta del proyecto):
  powershell -ExecutionPolicy Bypass -File .\menu.ps1
  powershell -ExecutionPolicy Bypass -File .\menu.ps1 -Contenedor ora_standby
  powershell -ExecutionPolicy Bypass -File .\menu.ps1 -Opcion 1     (una sola opcion y sale)
================================================================================
#>
[CmdletBinding()]
param (
    [string]$Contenedor = "",
    [string]$Pdb = "PDBCADENA",
    [string]$Opcion = "",
    # Para pruebas automaticas: no pide escribir SI en las opciones peligrosas
    [switch]$SinConfirmar
)

$ErrorActionPreference = "Continue"
$ScriptsStandby = "/opt/oracle/proyecto/sql/07_Standby_y_RMAN"

# ------------------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------------------
function Titulo([string]$t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Elegir-Contenedor {
    if ($script:Contenedor) { return }
    $existentes = @(docker ps -a --format "{{.Names}}" 2>$null | Where-Object { $_ -in @("ora_principal", "ora_standby") })
    if ($existentes.Count -eq 0) {
        Write-Host "[ERROR] No hay contenedor ora_principal ni ora_standby en esta PC (o Docker esta apagado)." -ForegroundColor Red
        Write-Host "        Revise docs/GUIA_PASO_A_PASO.md o docs/GUIA_COMPANERO_PC_STANDBY.md" -ForegroundColor Red
        exit 1
    }
    if ($existentes.Count -eq 1) { $script:Contenedor = $existentes[0]; return }
    Write-Host "En esta PC hay dos contenedores:"
    Write-Host "  1. ora_principal"
    Write-Host "  2. ora_standby"
    $r = Read-Host "Con cual quiere trabajar (1/2)"
    $script:Contenedor = if ($r -eq "2") { "ora_standby" } else { "ora_principal" }
}

function Contenedor-Encendido {
    return ((docker inspect -f "{{.State.Running}}" $script:Contenedor 2>$null) -eq "true")
}

# Ejecuta SQL como SYSDBA dentro del contenedor y devuelve el texto de salida
function Invoke-Sql([string]$sql, [switch]$Silencioso) {
    $tmp = Join-Path $env:TEMP "menu_cadena.sql"
    $texto = "SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF SERVEROUTPUT ON SIZE UNLIMITED`nWHENEVER SQLERROR CONTINUE`n" +
             ($sql -replace "`r`n", "`n") + "`nEXIT;`n"
    [IO.File]::WriteAllText($tmp, $texto, (New-Object Text.UTF8Encoding $false))
    docker cp $tmp "$($script:Contenedor):/tmp/menu_cadena.sql" 2>$null | Out-Null
    $salida = docker exec -u oracle $script:Contenedor sqlplus -s "/ as sysdba" "@/tmp/menu_cadena.sql" 2>&1
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $salida = ($salida | Where-Object { $_ -ne $null -and "$_".Trim() -ne "" }) -join "`n"
    if (-not $Silencioso) { Write-Host $salida }
    return $salida
}

# Valor de una sola consulta (sin encabezados)
function Get-Valor([string]$consulta) {
    $r = Invoke-Sql "SET HEADING OFF`n$consulta" -Silencioso
    return ("$r" -split "`n" | Where-Object { $_ -notmatch "^(ORA-|ERROR|\*)" } | Select-Object -First 1).Trim()
}

function Get-Rol {
    # Marcador ROL= para no confundir el resultado con el eco del SELECT que sqlplus
    # muestra cuando la instancia esta apagada (ORA-01034) o en NOMOUNT
    $salida = Invoke-Sql "SET HEADING OFF`nSELECT 'ROL=' || database_role || '|' || open_mode || '|' || db_unique_name FROM v`$database;" -Silencioso
    $linea = "$salida" -split "`n" | Where-Object { $_ -match "^ROL=" } | Select-Object -First 1
    if (-not $linea) { return @{ Rol = "SIN BASE"; Modo = "APAGADA"; Nombre = "-" } }
    $p = $linea.Substring(4) -split "\|"
    return @{ Rol = $p[0].Trim(); Modo = $p[1].Trim(); Nombre = $p[2].Trim() }
}

function Confirmar([string]$mensaje) {
    if ($SinConfirmar) { return $true }
    Write-Host $mensaje -ForegroundColor Yellow
    return ((Read-Host "Escriba SI para continuar") -eq "SI")
}

function Esperar-Contenedor {
    if (-not (Contenedor-Encendido)) {
        Write-Host "Encendiendo el contenedor $($script:Contenedor)..."
        docker start $script:Contenedor | Out-Null
    }
    # La imagen de Oracle tarda en terminar su propio arranque
    for ($i = 0; $i -lt 36; $i++) {
        $s = docker inspect -f "{{.State.Health.Status}}" $script:Contenedor 2>$null
        if ($s -and $s -ne "starting") { break }
        Start-Sleep -Seconds 5
    }
}

# ------------------------------------------------------------------------------
# Opciones
# ------------------------------------------------------------------------------
function Op-Estado {
    Titulo "ESTADO DE $($script:Contenedor)"
    if (-not (Contenedor-Encendido)) { Write-Host "El contenedor esta APAGADO. Use la opcion 2 (standby) o: docker start $($script:Contenedor)" -ForegroundColor Yellow; return }
    if ((Get-Rol).Rol -eq "SIN BASE") {
        Write-Host "La instancia de Oracle esta APAGADA (o en NOMOUNT)." -ForegroundColor Yellow
        Write-Host "Si esta PC es la standby use la opcion 2. Si es la principal: docker restart $($script:Contenedor)"
        return
    }
    Invoke-Sql @"
SET HEADING OFF
PROMPT === Base de datos ===
SELECT 'Nombre: ' || db_unique_name || '   Rol: ' || database_role || '   Modo: ' || open_mode FROM v`$database;
PROMPT
PROMPT === Data Guard ===
SELECT 'Envio a la otra PC (destino 2): ' || s.status || NVL2(s.error, ' - ' || s.error, '') || '   huecos: ' || NVL(s.gap_status, '-')
  FROM v`$archive_dest_status s, v`$database d
 WHERE s.dest_id = 2 AND s.status <> 'INACTIVE' AND d.database_role = 'PRIMARY';
SELECT 'Proceso ' || process || ': ' || status || ' (secuencia ' || sequence# || ')'
  FROM v`$managed_standby WHERE process IN ('MRP0', 'RFS') AND sequence# > 0;
SELECT 'Retraso ' || REPLACE(name, ' lag', '') || ': ' || NVL(value, '-')
  FROM v`$dataguard_stats WHERE name IN ('transport lag', 'apply lag');
"@ | Out-Null

    # Datos del proyecto: solo si la base esta abierta en escritura (la principal)
    $r = Get-Rol
    if ($r.Modo -ne "READ WRITE") {
        Write-Host "(Base en modo $($r.Modo): los datos del proyecto se ven en la principal o con la opcion 5.)"
        return
    }
    Invoke-Sql @"
SET HEADING OFF
ALTER SESSION SET CONTAINER = $Pdb;
PROMPT
PROMPT === Proyecto (esquema CADENA_NEG en $Pdb) ===
SELECT 'Objetos invalidos : ' || COUNT(*) FROM dba_objects WHERE owner = 'CADENA_NEG' AND status <> 'VALID';
SELECT 'Jobs habilitados  : ' || COUNT(*) FROM dba_scheduler_jobs WHERE owner = 'CADENA_NEG' AND enabled = 'TRUE';
SELECT 'Personas padron   : ' || COUNT(*) FROM CADENA_NEG.CAT_PADRON;
SELECT 'Facturas de venta : ' || COUNT(*) FROM CADENA_NEG.VEN_FACTURA;
"@ | Out-Null
}

function Op-ArrancarStandby {
    Titulo "ARRANCAR / REANUDAR LA STANDBY"
    Esperar-Contenedor
    $r = Get-Rol
    if ($r.Rol -eq "PRIMARY") { Write-Host "Esta base es la PRINCIPAL ($($r.Modo)): no hace falta esta opcion." -ForegroundColor Yellow; return }
    if ($r.Rol -eq "SIN BASE") {
        Write-Host "La instancia esta apagada: STARTUP MOUNT..."
        Invoke-Sql "STARTUP MOUNT;" | Out-Null
        $r = Get-Rol
    }
    # Se deja abierta en solo lectura (Active Data Guard): asi el database link
    # LNK_STANDBY puede recibir el respaldo diario y se pueden consultar los datos.
    if ($r.Modo -eq "MOUNTED") {
        Write-Host "Abriendo la standby en solo lectura..."
        Invoke-Sql "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;`nALTER DATABASE OPEN READ ONLY;`nALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;" -Silencioso | Out-Null
    }
    Write-Host "Activando la aplicacion automatica de cambios (Data Guard)..."
    Invoke-Sql "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;" -Silencioso | Out-Null
    Start-Sleep -Seconds 5
    Op-Estado
}

function Op-Sincronizar {
    Titulo "SINCRONIZAR AHORA"
    $r = Get-Rol
    if ($r.Rol -eq "PRIMARY") {
        # Reintenta el envio ya (si la standby estuvo apagada, Oracle esperaria 5 minutos)
        # y cierra el redo actual para mandarlo a la standby
        Write-Host "Reintentando el envio y cerrando el redo actual..."
        # Si el destino quedo en ERROR (pasa tras un switchover, failover o reconstruccion),
        # un simple ENABLE no basta: hay que pasarlo por DEFER para que Oracle reconecte.
        $estadoDestino = Get-Valor "SELECT status FROM v`$archive_dest_status WHERE dest_id = 2;"
        if ($estadoDestino -eq "ERROR") {
            Invoke-Sql "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = DEFER SCOPE = BOTH;" -Silencioso | Out-Null
        }
        Invoke-Sql "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = ENABLE SCOPE = BOTH;`nALTER SYSTEM ARCHIVE LOG CURRENT;" -Silencioso | Out-Null
        Start-Sleep -Seconds 10
        Invoke-Sql "SET HEADING OFF`nSELECT 'Destino 2: ' || status || NVL2(error, ' - ' || error, '') || '   huecos: ' || NVL(gap_status, '-') AS envio FROM v`$archive_dest_status WHERE dest_id = 2;" | Out-Null
        Write-Host "En la PC standby use la opcion 1 para ver el retraso (debe ser 0)."
    } else {
        Invoke-Sql "SET HEADING OFF`nSELECT 'Retraso ' || REPLACE(name, ' lag', '') || ': ' || NVL(value, '-') AS retraso FROM v`$dataguard_stats WHERE name IN ('transport lag', 'apply lag');" | Out-Null
        Invoke-Sql "SET HEADING OFF`nSELECT 'Proceso ' || process || ': ' || status || ' (secuencia ' || sequence# || ')' AS proceso FROM v`$managed_standby WHERE process IN ('MRP0', 'RFS') AND sequence# > 0;" | Out-Null
    }
}

function Op-Respaldo {
    Titulo "RESPALDO RMAN AHORA"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Write-Host "El respaldo se saca en la PRINCIPAL. Esta base es $($r.Rol)." -ForegroundColor Yellow; return }
    $nivel = if ($SinConfirmar) { "1" } else { Read-Host "Nivel (0 = completo, 1 = incremental) [1]" }
    if ($nivel -ne "0") { $nivel = "1" }
    $dest = Get-Valor "SELECT SUBSTR(name, 1, INSTR(name, '/', -1) - 1) FROM (SELECT name FROM v`$archived_log WHERE dest_id = 1 AND name IS NOT NULL ORDER BY completion_time DESC) WHERE ROWNUM = 1;"
    if (-not $dest) { $dest = "/opt/oracle/oradata/CADENA/archive_logs" }
    Write-Host "Respaldando (nivel $nivel). Tarda unos minutos..."
    docker exec -u root $script:Contenedor bash -c "mkdir -p /opt/oracle/backups /opt/oracle/logs && chown oracle:oinstall /opt/oracle/backups /opt/oracle/logs" | Out-Null
    $cmd = 'NIVEL_BACKUP=' + $nivel + ' bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh backup ' + $dest + ' x /opt/oracle/backups /tmp/stby_bk 3 CADENA $ORACLE_HOME 10'
    docker exec -u oracle -w $ScriptsStandby $script:Contenedor bash -c $cmd 2>&1 | Where-Object { $_ -match "\[OK\]|\[ERROR\]|RMAN:" } | ForEach-Object { Write-Host $_ }
    Write-Host "Respaldos en el contenedor: /opt/oracle/backups"
}

function Op-SoloLectura {
    Titulo "MOSTRAR DATOS EN LA STANDBY (solo lectura, sin parar la sincronizacion)"
    $r = Get-Rol
    if ($r.Rol -ne "PHYSICAL STANDBY") { Write-Host "Esta opcion es para la STANDBY. Esta base es $($r.Rol)." -ForegroundColor Yellow; return }
    if ($r.Modo -notlike "READ ONLY*") {
        Invoke-Sql @"
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE OPEN READ ONLY;
ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE USING CURRENT LOGFILE DISCONNECT FROM SESSION;
"@ -Silencioso | Out-Null
    }
    # Si el CDB ya estaba abierto pero el PDB quedo en MOUNTED (p.ej. tras reiniciar), abrirlo tambien
    Invoke-Sql "ALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;" -Silencioso | Out-Null
    Invoke-Sql @"
SELECT 'Modo: ' || open_mode AS modo FROM v`$database;
ALTER SESSION SET CONTAINER = $Pdb;
PROMPT === Ultimas facturas de venta replicadas ===
COLUMN num_factura_fave FORMAT A28
SELECT * FROM (SELECT id_factura_venta, num_factura_fave, fecha_fave, estado_fave FROM CADENA_NEG.VEN_FACTURA ORDER BY id_factura_venta DESC) WHERE ROWNUM <= 5;
SELECT 'Personas en el padron: ' || COUNT(*) AS padron FROM CADENA_NEG.CAT_PADRON;
"@ | Out-Null
    Write-Host "Para una consulta propia use la opcion 9."
}

function Op-Switchover {
    Titulo "SWITCHOVER: PASAR EL ROL DE PRINCIPAL A LA OTRA PC"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Write-Host "El switchover se inicia en la PRINCIPAL. Esta base es $($r.Rol)." -ForegroundColor Yellow; return }
    $destino = if ($r.Nombre -eq "CADENA") { "CADENA_STBY" } else { "CADENA" }
    Write-Host "Verificando que $destino este lista..."
    $v = Invoke-Sql "ALTER DATABASE SWITCHOVER TO $destino VERIFY;"
    if ($v -match "ORA-") { Write-Host "La verificacion fallo; no se hace el switchover." -ForegroundColor Red; return }
    if (-not (Confirmar "Esta base ($($r.Nombre)) pasara a ser STANDBY y $destino sera la PRINCIPAL.")) { return }
    $s = Invoke-Sql "ALTER DATABASE SWITCHOVER TO $destino;" -Silencioso
    if ($s -match "ORA-01034|Database altered") {
        Write-Host "Switchover hecho. (Si aparece ORA-01034 es normal: esta base se apaga para cambiar de rol.)" -ForegroundColor Green
    } else {
        Write-Host $s
    }
    Write-Host ""
    Write-Host "Listo. Siga en este orden:" -ForegroundColor Green
    Write-Host "  1. En la OTRA PC: opcion 7 (abrir como nueva principal)."
    Write-Host "  2. En ESTA PC: opcion 2 (queda como standby; el contenedor se apaga y se vuelve a encender)."
}

function Op-AbrirPrincipal {
    Titulo "ABRIR COMO NUEVA PRINCIPAL"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Write-Host "Esta base es $($r.Rol): primero hay que hacer el switchover (opcion 6 en la otra PC) o el failover (opcion 8)." -ForegroundColor Yellow; return }
    if ($r.Modo -ne "READ WRITE") {
        Invoke-Sql @"
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
"@ | Out-Null
    }
    Op-Estado
}

function Op-Failover {
    Titulo "FAILOVER: TOMAR EL CONTROL PORQUE LA PRINCIPAL SE CAYO"
    $r = Get-Rol
    if ($r.Rol -ne "PHYSICAL STANDBY") { Write-Host "El failover se hace en la STANDBY. Esta base es $($r.Rol)." -ForegroundColor Yellow; return }
    if (-not (Confirmar "Use esto SOLO si la principal ya no funciona. Despues, la otra PC debe reconstruirse como standby (guia, seccion 7 paso 12).")) { return }
    Invoke-Sql @"
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE FAILOVER TO $($r.Nombre);
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER PLUGGABLE DATABASE ALL SAVE STATE;
"@ | Out-Null
    Op-Estado
}

function Op-ConsolaProyecto {
    Titulo "CONSOLA SQL EN $Pdb (escriba EXIT para volver)"
    $tmp = Join-Path $env:TEMP "menu_pdb.sql"
    [IO.File]::WriteAllText($tmp, "ALTER SESSION SET CONTAINER = $Pdb;`nALTER SESSION SET CURRENT_SCHEMA = CADENA_NEG;`nSET SERVEROUTPUT ON SIZE UNLIMITED LINESIZE 200 PAGESIZE 100`n", (New-Object Text.UTF8Encoding $false))
    docker cp $tmp "$($script:Contenedor):/tmp/menu_pdb.sql" 2>$null | Out-Null
    Remove-Item $tmp -ErrorAction SilentlyContinue
    docker exec -it -u oracle $script:Contenedor sqlplus "/ as sysdba" "@/tmp/menu_pdb.sql"
}

function Op-ConsolaCdb {
    Titulo "CONSOLA SYSDBA (CDB) (escriba EXIT para volver)"
    docker exec -it -u oracle $script:Contenedor sqlplus "/ as sysdba"
}

function Mostrar-Menu {
    $r = if (Contenedor-Encendido) { Get-Rol } else { @{ Rol = "APAGADO"; Modo = "-"; Nombre = "-" } }
    Titulo "PROYECTO SUPER BRUNCA  |  $($script:Contenedor)  |  $($r.Rol) / $($r.Modo)"
    Write-Host "  1. Ver estado (base, Data Guard, proyecto)"
    Write-Host "  2. Arrancar / reanudar la standby (despues de reiniciar)"
    Write-Host "  3. Sincronizar ahora y ver retraso"
    Write-Host "  4. Respaldo RMAN ahora                         (en la principal)"
    Write-Host "  5. Mostrar datos en la standby (solo lectura)  (en la standby)"
    Write-Host "  6. Switchover: pasar el rol a la otra PC       (en la principal)"
    Write-Host "  7. Abrir como nueva principal                  (despues del 6 o del 8)"
    Write-Host "  8. Failover: la principal se cayo              (en la standby)"
    Write-Host "  9. Consola SQL del proyecto ($Pdb)"
    Write-Host " 10. Consola SYSDBA (CDB)"
    Write-Host "  0. Salir"
}

function Ejecutar([string]$o) {
    switch ($o) {
        "1"  { Op-Estado }
        "2"  { Op-ArrancarStandby }
        "3"  { Op-Sincronizar }
        "4"  { Op-Respaldo }
        "5"  { Op-SoloLectura }
        "6"  { Op-Switchover }
        "7"  { Op-AbrirPrincipal }
        "8"  { Op-Failover }
        "9"  { Op-ConsolaProyecto }
        "10" { Op-ConsolaCdb }
        default { Write-Host "Opcion no valida." -ForegroundColor Yellow }
    }
}

# ------------------------------------------------------------------------------
# Programa principal
# ------------------------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Docker no esta instalado o no esta en el PATH." -ForegroundColor Red
    exit 1
}
Elegir-Contenedor

if ($Opcion) { Ejecutar $Opcion; exit 0 }

while ($true) {
    Mostrar-Menu
    $o = Read-Host "`nElija una opcion"
    if ($o -eq "0") { break }
    Ejecutar $o
    Read-Host "`nPresione Enter para volver al menu" | Out-Null
}
