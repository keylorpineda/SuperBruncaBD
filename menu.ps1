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
  powershell -ExecutionPolicy Bypass -File .\menu.ps1 -SinComandos  (no muestra los comandos SQL)

  Cada opcion muestra en color los comandos SQL, RMAN y Docker reales que ejecuta.
================================================================================
#>
[CmdletBinding()]
param (
    [string]$Contenedor = "",
    [string]$Pdb = "PDBCADENA",
    [string]$Opcion = "",
    # Para pruebas automaticas: no pide escribir SI en las opciones peligrosas
    [switch]$SinConfirmar,
    # Oculta los comandos SQL / RMAN que se ejecutan (por defecto se muestran)
    [switch]$SinComandos
)

$ErrorActionPreference = "Continue"
$ScriptsStandby = "/opt/oracle/proyecto/sql/07_Standby_y_RMAN"

# ------------------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------------------
# Pantalla: solo caracteres ASCII en el codigo (PowerShell 5.1 lee el archivo como ANSI);
# las lineas se dibujan con [char] para que se vean bien en cualquier consola.
$script:Linea = [string][char]0x2500
$script:Punto = [string][char]0x2022

function Ancho {
    try { $w = $Host.UI.RawUI.WindowSize.Width } catch { $w = 0 }
    if (-not $w -or $w -lt 60) { $w = 100 }
    return [Math]::Min($w - 1, 110)
}

function Titulo([string]$t) {
    Write-Host ""
    Write-Host ("  " + $t.ToUpper()) -ForegroundColor Cyan
    Write-Host ("  " + ($script:Linea * ([Math]::Min($t.Length + 4, (Ancho) - 4)))) -ForegroundColor DarkCyan
}

# Mensajes de la operacion
function Paso([string]$t)  { Write-Host "  > $t" -ForegroundColor White }
function Aviso([string]$t) { Write-Host "  ! $t" -ForegroundColor Yellow }
function Exito([string]$t) { Write-Host "  OK $t" -ForegroundColor Green }
function Falla([string]$t) { Write-Host "  X $t" -ForegroundColor Red }

# Escribe la salida de sqlplus sangrada, sin tabuladores y con color:
# "=== Seccion ===" como subtitulo, verde lo correcto y rojo los errores
function Escribir-Salida([string]$texto) {
    foreach ($l in ($texto -split "`n")) {
        $l = ($l -replace "`t", "  ").TrimEnd()
        if (-not $l.Trim()) { continue }
        if ($l -match "^\s*===\s*(.+?)\s*===\s*$") {
            Write-Host ""
            Write-Host ("  " + $Matches[1]) -ForegroundColor Yellow
        } elseif ($l -cmatch "ORA-|SP2-|ERROR|FAILED|Fallo|RESOLVABLE GAP|UNRESOLVABLE") {
            Write-Host ("    " + $l) -ForegroundColor Red
        } elseif ($l -cmatch "VALID|SUCCEEDED|NO GAP|entregada|\[OK\]|READ WRITE|APPLYING_LOG") {
            Write-Host ("    " + $l) -ForegroundColor Green
        } elseif ($l -match "^\s*-{3,}[\s-]*$") {
            Write-Host ("    " + $l) -ForegroundColor DarkGray
        } else {
            Write-Host ("    " + $l)
        }
    }
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

# Muestra los comandos reales que se van a ejecutar, para que se vea que no es una simulacion.
# Una linea por instruccion, recortada al ancho de la ventana.
function Mostrar-Comandos([string]$sql) {
    if ($script:SinComandos) { return }
    $lineas = @(($sql -replace "`r`n", "`n") -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch "^\s*(SET |PROMPT|COLUMN |/\s*$)" })
    if ($lineas.Count -eq 0) { return }
    # Unir las instrucciones de varias lineas (terminan en ';'); un bloque BEGIN ... END; va completo en una linea
    $instrucciones = @(); $actual = ""; $bloque = $false
    foreach ($l in $lineas) {
        $t = ($l.Trim() -replace "\s+", " ")
        if ($t -match "^(BEGIN|DECLARE)$") { $bloque = $true }
        $actual = ($actual + " " + $t).Trim()
        if ((-not $bloque -and $t.EndsWith(";")) -or ($bloque -and $t -match "^END;?$")) { $instrucciones += $actual; $actual = ""; $bloque = $false }
    }
    if ($actual) { $instrucciones += $actual }
    $max = (Ancho) - 10
    Write-Host ("  " + $script:Contenedor + " | sqlplus / as sysdba") -ForegroundColor DarkGray
    foreach ($i in $instrucciones) {
        if ($i.Length -gt $max) { $i = $i.Substring(0, $max - 3) + "..." }
        Write-Host ("    SQL> " + $i) -ForegroundColor DarkCyan
    }
}

function Mostrar-Comando-SO([string]$cmd) {
    if ($script:SinComandos) { return }
    $max = (Ancho) - 8
    if ($cmd.Length -gt $max) { $cmd = $cmd.Substring(0, $max - 3) + "..." }
    Write-Host ("  " + $script:Contenedor + " | bash") -ForegroundColor DarkGray
    Write-Host ("    `$ " + $cmd) -ForegroundColor DarkCyan
}

# Ejecuta SQL como SYSDBA dentro del contenedor y devuelve el texto de salida.
# -SinEco: no muestra el comando (consultas internas del menu o comandos con una clave)
function Invoke-Sql([string]$sql, [switch]$Silencioso, [switch]$SinEco) {
    if (-not $SinEco) { Mostrar-Comandos $sql }
    $tmp = Join-Path $env:TEMP "menu_cadena.sql"
    $texto = "SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF SERVEROUTPUT ON SIZE UNLIMITED`nSET TAB OFF`nWHENEVER SQLERROR CONTINUE`n" +
             ($sql -replace "`r`n", "`n") + "`nEXIT;`n"
    [IO.File]::WriteAllText($tmp, $texto, (New-Object Text.UTF8Encoding $false))
    docker cp $tmp "$($script:Contenedor):/tmp/menu_cadena.sql" 2>$null | Out-Null
    $salida = docker exec -u oracle $script:Contenedor sqlplus -s "/ as sysdba" "@/tmp/menu_cadena.sql" 2>&1
    docker exec -u root $script:Contenedor rm -f /tmp/menu_cadena.sql 2>$null | Out-Null   # puede contener una clave
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $salida = ($salida | Where-Object { $_ -ne $null -and "$_".Trim() -ne "" }) -join "`n"
    if (-not $Silencioso) { Escribir-Salida $salida }
    return $salida
}

# Valor de una sola consulta (sin encabezados)
function Get-Valor([string]$consulta) {
    $r = Invoke-Sql "SET HEADING OFF`n$consulta" -Silencioso -SinEco
    # Se descartan los mensajes de sqlplus ("ORA-...", "ERROR at line"), no un valor que sea la palabra ERROR
    $v = "$r" -split "`n" | Where-Object { $_ -notmatch "^(ORA-|SP2-|ERROR at line|\*)" } | Select-Object -First 1
    if ($null -eq $v) { return "" }
    return $v.Trim()
}

function Get-Rol {
    # Marcador ROL= para no confundir el resultado con el eco del SELECT que sqlplus
    # muestra cuando la instancia esta apagada (ORA-01034) o en NOMOUNT
    $salida = Invoke-Sql "SET HEADING OFF`nSELECT 'ROL=' || database_role || '|' || open_mode || '|' || db_unique_name FROM v`$database;" -Silencioso -SinEco
    $linea = "$salida" -split "`n" | Where-Object { $_ -match "^ROL=" } | Select-Object -First 1
    if (-not $linea) { return @{ Rol = "SIN BASE"; Modo = "APAGADA"; Nombre = "-" } }
    $p = $linea.Substring(4) -split "\|"
    return @{ Rol = $p[0].Trim(); Modo = $p[1].Trim(); Nombre = $p[2].Trim() }
}

function Confirmar([string]$mensaje) {
    if ($SinConfirmar) { return $true }
    Aviso $mensaje
    return ((Read-Host "  Escriba SI para continuar") -eq "SI")
}

function Esperar-Contenedor {
    if (-not (Contenedor-Encendido)) {
        Paso "Encendiendo el contenedor $($script:Contenedor)..."
        if (-not $script:SinComandos) { Write-Host "    `$ docker start $($script:Contenedor)" -ForegroundColor DarkCyan }
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
    if (-not (Contenedor-Encendido)) { Aviso "El contenedor esta APAGADO. Use la opcion 2 (standby) o: docker start $($script:Contenedor)"; return }
    if ((Get-Rol).Rol -eq "SIN BASE") {
        Aviso "La instancia de Oracle esta APAGADA (o en NOMOUNT)."
        Paso "Si esta PC es la standby use la opcion 2. Si es la principal: docker restart $($script:Contenedor)"
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
        Write-Host ""; Paso "Base en modo $($r.Modo): los datos del proyecto se ven en la principal o con la opcion 5."
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
    if ($r.Rol -eq "PRIMARY") { Aviso "Esta base es la PRINCIPAL ($($r.Modo)): no hace falta esta opcion."; return }
    if ($r.Rol -eq "SIN BASE") {
        Paso "La instancia esta apagada: STARTUP MOUNT..."
        Invoke-Sql "STARTUP MOUNT;" | Out-Null
        $r = Get-Rol
    }
    # Se deja abierta en solo lectura (Active Data Guard): asi el database link
    # LNK_STANDBY puede recibir el respaldo diario y se pueden consultar los datos.
    if ($r.Modo -eq "MOUNTED") {
        Paso "Abriendo la standby en solo lectura..."
        Invoke-Sql "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;`nALTER DATABASE OPEN READ ONLY;`nALTER PLUGGABLE DATABASE ALL OPEN READ ONLY;" -Silencioso | Out-Null
    }
    Paso "Activando la aplicacion automatica de cambios (Data Guard)..."
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
        Paso "Reintentando el envio y cerrando el redo actual..."
        # Si el destino quedo en ERROR (pasa tras un switchover, failover o reconstruccion),
        # un simple ENABLE no basta: hay que pasarlo por DEFER para que Oracle reconecte.
        $estadoDestino = Get-Valor "SELECT status FROM v`$archive_dest_status WHERE dest_id = 2;"
        if ($estadoDestino -eq "ERROR") {
            Invoke-Sql "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = DEFER SCOPE = BOTH;" -Silencioso | Out-Null
        }
        Invoke-Sql "ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2 = ENABLE SCOPE = BOTH;`nALTER SYSTEM ARCHIVE LOG CURRENT;" -Silencioso | Out-Null
        Start-Sleep -Seconds 10
        Invoke-Sql "SET HEADING OFF`nSELECT 'Destino 2: ' || status || NVL2(error, ' - ' || error, '') || '   huecos: ' || NVL(gap_status, '-') AS envio FROM v`$archive_dest_status WHERE dest_id = 2;" | Out-Null
        Paso "En la PC standby use la opcion 1 para ver el retraso (debe ser 0)."
    } else {
        Invoke-Sql "SET HEADING OFF`nSELECT 'Retraso ' || REPLACE(name, ' lag', '') || ': ' || NVL(value, '-') AS retraso FROM v`$dataguard_stats WHERE name IN ('transport lag', 'apply lag');" | Out-Null
        Invoke-Sql "SET HEADING OFF`nSELECT 'Proceso ' || process || ': ' || status || ' (secuencia ' || sequence# || ')' AS proceso FROM v`$managed_standby WHERE process IN ('MRP0', 'RFS') AND sequence# > 0;" | Out-Null
    }
}

function Op-Respaldo {
    Titulo "RESPALDO RMAN AHORA"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Aviso "El respaldo se saca en la PRINCIPAL. Esta base es $($r.Rol)."; return }
    $nivel = if ($SinConfirmar) { "1" } else { Read-Host "  Nivel (0 = completo, 1 = incremental) [1]" }
    if ($nivel -ne "0") { $nivel = "1" }
    $dest = Get-Valor "SELECT SUBSTR(name, 1, INSTR(name, '/', -1) - 1) FROM (SELECT name FROM v`$archived_log WHERE dest_id = 1 AND name IS NOT NULL ORDER BY completion_time DESC) WHERE ROWNUM = 1;"
    if (-not $dest) { $dest = "/opt/oracle/oradata/CADENA/archive_logs" }
    Paso "Respaldando (nivel $nivel). Tarda unos minutos..."
    docker exec -u root $script:Contenedor bash -c "mkdir -p /opt/oracle/backups /opt/oracle/logs && chown oracle:oinstall /opt/oracle/backups /opt/oracle/logs" | Out-Null
    $cmd = 'NIVEL_BACKUP=' + $nivel + ' bash 02_Traslado_Archivelogs_10min_y_Ondemand.sh backup ' + $dest + ' x /opt/oracle/backups /tmp/stby_bk 3 CADENA $ORACLE_HOME 10'
    Mostrar-Comando-SO "cd $ScriptsStandby && $cmd   (RMAN: 04_RMAN_Backup_Full_Incremental.rman)"
    docker exec -u oracle -w $ScriptsStandby $script:Contenedor bash -c $cmd 2>&1 | Where-Object { $_ -match "\[OK\]|\[ERROR\]|RMAN:" } | ForEach-Object { Escribir-Salida "$_" }
    Paso "Respaldos en el contenedor: /opt/oracle/backups"
}

function Op-SoloLectura {
    Titulo "MOSTRAR DATOS EN LA STANDBY (solo lectura, sin parar la sincronizacion)"
    $r = Get-Rol
    if ($r.Rol -ne "PHYSICAL STANDBY") { Aviso "Esta opcion es para la STANDBY. Esta base es $($r.Rol)."; return }
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
SET HEADING OFF
SELECT 'Modo: ' || open_mode FROM v`$database;
ALTER SESSION SET CONTAINER = $Pdb;
PROMPT === Ultimas facturas de venta replicadas ===
SET HEADING ON
COLUMN factura FORMAT A16
COLUMN fecha FORMAT A10
COLUMN estado FORMAT A6
SELECT * FROM (SELECT id_factura_venta AS id, num_factura_fave AS factura, TO_CHAR(fecha_fave, 'YYYY-MM-DD') AS fecha,
                      estado_fave AS estado FROM CADENA_NEG.VEN_FACTURA ORDER BY id_factura_venta DESC) WHERE ROWNUM <= 5;
SET HEADING OFF
SELECT 'Personas en el padron: ' || COUNT(*) FROM CADENA_NEG.CAT_PADRON;
"@ | Out-Null
    Write-Host ""; Paso "Para una consulta propia use la opcion 9."
}

function Op-Switchover {
    Titulo "SWITCHOVER: PASAR EL ROL DE PRINCIPAL A LA OTRA PC"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Aviso "El switchover se inicia en la PRINCIPAL. Esta base es $($r.Rol)."; return }
    $destino = if ($r.Nombre -eq "CADENA") { "CADENA_STBY" } else { "CADENA" }
    Paso "Verificando que $destino este lista..."
    $v = Invoke-Sql "ALTER DATABASE SWITCHOVER TO $destino VERIFY;"
    if ($v -match "ORA-") { Falla "La verificacion fallo; no se hace el switchover."; return }
    if (-not (Confirmar "Esta base ($($r.Nombre)) pasara a ser STANDBY y $destino sera la PRINCIPAL.")) { return }
    $s = Invoke-Sql "ALTER DATABASE SWITCHOVER TO $destino;" -Silencioso
    if ($s -match "ORA-01034|Database altered") {
        Exito "Switchover hecho. (Si aparece ORA-01034 es normal: esta base se apaga para cambiar de rol.)"
    } else {
        Escribir-Salida $s
    }
    Write-Host ""
    Exito "Listo. Siga en este orden:"
    Paso "1. En la OTRA PC: opcion 7 (abrir como nueva principal)."
    Paso "2. En ESTA PC: opcion 2 (queda como standby; el contenedor se apaga y se vuelve a encender)."
}

function Op-AbrirPrincipal {
    Titulo "ABRIR COMO NUEVA PRINCIPAL"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY") { Aviso "Esta base es $($r.Rol): primero hay que hacer el switchover (opcion 6 en la otra PC) o el failover (opcion 8)."; return }
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
    if ($r.Rol -ne "PHYSICAL STANDBY") { Aviso "El failover se hace en la STANDBY. Esta base es $($r.Rol)."; return }
    if (-not (Confirmar "Use esto SOLO si la principal ya no funciona. Despues, la otra PC debe reconstruirse como standby (guia, seccion 7 paso 12).")) { return }
    # Detener la aplicacion de cambios; si ya estaba detenida (ORA-16136) no es un error
    Invoke-Sql "ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;" -Silencioso | Out-Null
    Invoke-Sql @"
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

# Valida una lista de correos separados por coma; devuelve la lista limpia o $null
function Validar-Correos([string]$texto) {
    $lista = @($texto -split "[,;]" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($lista.Count -eq 0) { return $null }
    foreach ($c in $lista) {
        if ($c -notmatch "^[^@\s'`"]+@[^@\s'`"]+\.[A-Za-z]{2,}$") { Write-Host "Correo no valido: $c" -ForegroundColor Red; return $null }
    }
    return ($lista -join ", ")
}

function Op-ConfigurarCorreos {
    Titulo "Correos que reciben los avisos"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY" -or $r.Modo -ne "READ WRITE") { Aviso "Esta opcion se usa en la PRINCIPAL (abierta). Esta base es $($r.Rol) / $($r.Modo)."; return }

    # Valores actuales en una sola consulta
    $salida = Invoke-Sql @"
SET HEADING OFF
ALTER SESSION SET CONTAINER = $Pdb;
SELECT 'P=' || codigo_para || '=' || valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO
 WHERE codigo_para IN ('CORREO_EMISOR', 'CORREO_COORDINADOR', 'CORREO_GERENTE', 'CORREO_DBA');
"@ -Silencioso -SinEco
    $actual = @{}
    foreach ($l in ("$salida" -split "`n" | Where-Object { $_ -match "^P=" })) { $x = $l.Substring(2) -split "=", 2; $actual[$x[0].Trim()] = $x[1].Trim() }

    $roles = [ordered]@{
        "CORREO_COORDINADOR" = @("Coordinador", "clientes al 85%, productos vencidos, mercadeo, premiacion y cierre diario")
        "CORREO_GERENTE"     = @("Gerente",     "proveedores al 70%, clientes morosos y cierre diario")
        "CORREO_DBA"         = @("DBA",         "alertas de la base de datos y del standby")
    }
    Write-Host ""
    Write-Host "  Hoy los avisos llegan asi:" -ForegroundColor Yellow
    # Correo en su propia linea y lo que recibe debajo: se lee bien aunque el correo sea largo
    foreach ($k in $roles.Keys) {
        Write-Host ("    {0,-12}" -f $roles[$k][0]) -ForegroundColor Cyan -NoNewline
        Write-Host $actual[$k]
        Write-Host ("    {0,-12}{1}" -f "", "recibe: " + $roles[$k][1]) -ForegroundColor DarkGray
    }
    Write-Host ("    {0,-12}" -f "Remitente") -ForegroundColor Cyan -NoNewline
    Write-Host $actual["CORREO_EMISOR"]
    Write-Host ("    {0,-12}{1}" -f "", "la cuenta de Gmail que envia (se cambia en la opcion 12)") -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "  Que desea hacer?" -ForegroundColor Yellow
    Write-Host "     1  Un solo correo para todos los avisos (recomendado para la defensa)"
    Write-Host "     2  Un correo distinto para cada responsable"
    Write-Host "     0  Volver sin cambiar nada" -ForegroundColor DarkGray
    $modo = Read-Host "`n  Opcion"
    $valores = [ordered]@{}
    if ($modo -eq "1") {
        $t = Read-Host "  Correo que recibira todo (puede poner varios separados por coma)"
        $v = Validar-Correos $t; if (-not $v) { return }
        foreach ($k in $roles.Keys) { $valores[$k] = $v }
    } elseif ($modo -eq "2") {
        Paso "Escriba el correo de cada uno (Enter = dejar el actual)."
        foreach ($k in $roles.Keys) {
            $t = Read-Host ("  {0} (hoy: {1})" -f $roles[$k][0], $actual[$k])
            if ($null -ne $t -and $t.Trim()) { $v = Validar-Correos $t; if (-not $v) { return }; $valores[$k] = $v }
        }
        if ($valores.Count -eq 0) { Aviso "No se cambio nada."; return }
    } else { return }

    # Avisos individuales a clientes (credito al 85%): normalmente van al correo de cada cliente
    $primero = (@($valores.Values) | Select-Object -First 1).Split(",")[0].Trim()
    Write-Host ""
    Paso "El aviso de 'credito al 85%' tambien se manda a cada CLIENTE, a su propio correo."
    $cli = Read-Host "  Quiere que esos avisos de clientes tambien le lleguen a $primero, para verlos en la defensa? (s/N)"

    Write-Host ""
    Write-Host "  Se va a guardar:" -ForegroundColor Yellow
    foreach ($k in $valores.Keys) { Write-Host ("    {0,-12}{1}" -f $roles[$k][0], $valores[$k]) }
    if ($cli -match "^[sS]") { Write-Host ("    {0,-12}{1}" -f "Clientes", $primero) }
    if ((Read-Host "`n  Guardar? (S/n)") -match "^[nN]") { Aviso "No se guardo nada."; return }

    $sql = "ALTER SESSION SET CONTAINER = $Pdb;`n"
    foreach ($k in $valores.Keys) {
        $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('$k', 'CORREO', 'Correo del $($roles[$k][0].ToLower())', 'Recibe: $($roles[$k][1]).', 'N', '$($valores[$k])');`n"
    }
    if ($cli -match "^[sS]") { $sql += "UPDATE CADENA_NEG.PER_CONTACTO SET VALOR_CONT = '$primero' WHERE TIPO_CONT = 'E';`nCOMMIT;`n" }
    Invoke-Sql $sql -Silencioso | Out-Null
    Exito "Correos guardados (tabla SEG_PARAMETRO)."

    $dest = (@($valores.Values) | Select-Object -Unique) -join ", "
    if ((Read-Host "`n  Mandar un correo de prueba a $dest ahora? (S/n)") -notmatch "^[nN]") {
        Invoke-Sql @"
ALTER SESSION SET CONTAINER = $Pdb;
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO('$dest', 'Prueba de notificaciones - Super Brunca', 'PRUEBA DE CORREO DESDE ORACLE' || CHR(10) || 'Este correo confirma que los avisos del sistema llegan a esta direccion.' || CHR(10) || 'Destinatarios: $dest');
"@ -Silencioso | Where-Object { $_ } | ForEach-Object { $_ -split "`n" } | Where-Object { $_ -match "Estado SMTP" } | ForEach-Object { Escribir-Salida $_ }
        Paso "Revise la bandeja de entrada (y la carpeta Spam) de $dest."
    }
}

function Op-ClaveGmail {
    Titulo "CLAVE DE APLICACION DE GMAIL (correo que envia)"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY" -or $r.Modo -ne "READ WRITE") { Write-Host "Esta opcion se usa en la PRINCIPAL (abierta). Esta base es $($r.Rol) / $($r.Modo)." -ForegroundColor Yellow; return }
    Paso "Se usa una 'contrasena de aplicacion' de 16 letras (https://myaccount.google.com/apppasswords),"
    Paso "no la contrasena normal de Gmail. Se guarda CIFRADA con AES-256 en SEG_PARAMETRO."
    $emisor = Read-Host "  Correo de Gmail que envia (Enter = no cambiar)"
    $segura = Read-Host "  Clave de aplicacion (no se muestra)" -AsSecureString
    $clave = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
    $clave = ($clave -replace "\s", "")
    if ($clave -notmatch "^[A-Za-z]{16}$") { Falla "La clave de aplicacion de Gmail son 16 letras. No se guardo nada."; return }
    $sql = "ALTER SESSION SET CONTAINER = $Pdb;`n"
    if ($emisor.Trim()) {
        $v = Validar-Correos $emisor; if (-not $v) { return }
        $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CORREO_EMISOR', 'CORREO', 'Correo emisor del sistema', 'Cuenta remitente de las notificaciones automaticas (Gmail autenticado).', 'N', '$v');`n"
    }
    $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '$clave');`n"
    Invoke-Sql $sql -Silencioso -SinEco | Out-Null   # lleva la clave: nunca se muestra
    $clave = $null
    Exito "Clave guardada cifrada."
    # El wallet con los certificados de Gmail (se pierde el parametro al reinstalar el esquema)
    docker exec -u oracle $script:Contenedor bash -c "test -f /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh && bash /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh | tail -1" 2>$null | ForEach-Object { Escribir-Salida "$_" }
    Paso "Pruebe el envio con la opcion 11 (correo de prueba)."
}

function Op-EnviarNotificacion {
    Titulo "ENVIAR UNA NOTIFICACION AHORA"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY" -or $r.Modo -ne "READ WRITE") { Write-Host "Esta opcion se usa en la PRINCIPAL (abierta). Esta base es $($r.Rol) / $($r.Modo)." -ForegroundColor Yellow; return }
    # Mismos procedimientos que ejecutan los jobs; el correo sale solo si hay algo que avisar
    $opciones = [ordered]@{
        "1"  = @("Clientes al 85% o mas de su credito (a cada cliente y al coordinador)", "CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO;")
        "2"  = @("Proveedores al 70% o mas del credito (un correo al gerente)",           "CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO;")
        "3"  = @("Clientes morosos (al gerente y al coordinador)",                       "CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS;")
        "4"  = @("Productos vencidos (al coordinador)",                                   "CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;")
        "5"  = @("Las 4 anteriores (lo que hace el job de las 07:00)",                   "CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_85_CREDITO; CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PROVEEDORES_70_CREDITO; CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_CLIENTES_MOROSOS; CADENA_NEG.PKG_ADM_NOTIFICACION.PR_NOTIF_PRODUCTOS_VENCIDOS;")
        "6"  = @("Cierre diario de hoy (al coordinador y al gerente)",                    "CADENA_NEG.PKG_VEN_OPERACION.PR_EJECUTAR_CIERRE_DIARIO(TRUNC(SYSDATE));")
        "7"  = @("Reporte semanal de mercadeo: por vencer y mas de 6 meses (coordinador)","CADENA_NEG.PKG_INV_GESTION.PR_REPORTE_SEMANAL_MERCADEO;")
        "8"  = @("Revision de salud de la base (al DBA, solo si hay problemas)",          "CADENA_NEG.PKG_ADM_MONITOREO.PR_EJECUTAR_MONITOREO_DIARIO;")
        "9"  = @("Revision del standby (al DBA, solo si hay problemas)",                  "CADENA_NEG.PKG_ADM_STANDBY.PR_VERIFICAR_SINCRONIZACION;")
        "10" = @("Premiacion semestral: Top de clientes (coordinador; genera las ordenes)","CADENA_NEG.PKG_PRM_MERCADEO.PR_PREMIAR_MEJORES_CLIENTES;")
    }
    foreach ($k in $opciones.Keys) { Write-Host ("   {0,2}  {1}" -f $k, $opciones[$k][0]) }
    Write-Host "    0  Volver" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Destino actual:" -ForegroundColor DarkGray
    Invoke-Sql @"
SET HEADING OFF
ALTER SESSION SET CONTAINER = $Pdb;
SELECT RPAD(codigo_para, 20) || valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO
 WHERE codigo_para IN ('CORREO_COORDINADOR', 'CORREO_GERENTE', 'CORREO_DBA') ORDER BY codigo_para;
"@ -SinEco | Out-Null
    $o = Read-Host "`n  Cual notificacion"
    if (-not $opciones.Contains($o)) { return }
    if ($o -eq "1" -or $o -eq "5") {
        Paso "El aviso individual va al correo de cada cliente (PER_CONTACTO). Para recibirlos usted: opcion 11, responder 's' a 'avisos a CLIENTES'."
    }
    if ($o -eq "10" -and -not (Confirmar "La premiacion guarda las ordenes de compra del periodo actual en PRM_ORDEN_PREMIACION.")) { return }
    Paso "Ejecutando: $($opciones[$o][0])..."
    $salida = Invoke-Sql @"
ALTER SESSION SET CONTAINER = $Pdb;
SET SERVEROUTPUT ON SIZE UNLIMITED
SET TAB OFF
BEGIN
    $($opciones[$o][1])
END;
/
"@ -Silencioso
    $lineas = "$salida" -split "`n" | Where-Object { $_ -match "Para\s+:|Asunto\s+:|Estado SMTP|^No |^Ningun|\[OK\]|\[AVISO\]|ORA-" }
    if (-not $lineas) { Aviso "Termino sin nada que avisar (no se envio correo)."; return }
    foreach ($l in $lineas) {
        $l = ($l.Trim() -replace "\s+:", ":")
        if ($l -match "^Asunto") { Write-Host ""; Write-Host ("    " + $l) -ForegroundColor Cyan }
        elseif ($l -match "entregada|\[OK\]") { Write-Host ("    " + $l) -ForegroundColor Green }
        elseif ($l -match "Fallo|ORA-") { Write-Host ("    " + $l) -ForegroundColor Red }
        else { Write-Host ("    " + $l) -ForegroundColor Gray }
    }
    $n = @($lineas | Where-Object { $_ -match "entregada" }).Count
    Write-Host ""
    if ($n -gt 0) { Exito "Correos enviados: $n" } else { Aviso "No se envio correo: no habia nada que avisar." }
}

# Prueba real de que las dos PC estan conectadas y termina con un veredicto claro
function Op-Conexion {
    Titulo "Comprobar que las dos PC esten conectadas"
    $r = Get-Rol
    $c = $script:Contenedor
    if ($r.Rol -eq "PRIMARY") {
        $tns = "STANDBY_TNS"; $otra = "la standby (CADENA_STBY)"
        if ($r.Nombre -eq "CADENA_STBY") { $tns = "PRIMARIA_TNS"; $otra = "la otra PC (CADENA)" }
    } elseif ($r.Rol -eq "PHYSICAL STANDBY") {
        $tns = "PRIMARIA_TNS"; $otra = "la principal (CADENA)"
        if ($r.Nombre -eq "CADENA") { $tns = "STANDBY_TNS"; $otra = "la otra PC (CADENA_STBY)" }
    } else { Aviso "La base de esta PC esta $($r.Modo). Enciendala primero (opcion 2 en la standby)."; return }
    $problemas = @()

    # 1) Red: Oracle Net llega a la otra base
    Write-Host ""
    Paso "1/3  Red: esta PC intenta llegar a $otra"
    Mostrar-Comando-SO "tnsping $tns"
    $ping = docker exec -u oracle $c bash -c "tnsping $tns 2>&1 | tail -1" 2>$null
    if ("$ping" -match "^OK") { Escribir-Salida ("Respuesta: " + "$ping".Trim()) }
    else { Escribir-Salida ("ERROR: " + "$ping".Trim()); $problemas += "La red no llega a la otra PC: revise que este encendida, la IP en tnsnames.ora, el ping y el puerto 1521 en el firewall." }

    if ($r.Rol -eq "PRIMARY") {
        # 2) Estado del envio
        Paso "2/3  Data Guard: estado del envio a la standby"
        $d = Invoke-Sql "SET HEADING OFF`nSELECT 'DST=' || status || '|' || NVL(gap_status, '-') || '|' || error FROM v`$archive_dest_status WHERE dest_id = 2;" -Silencioso
        $d = ("$d" -split "`n" | Where-Object { $_ -match "^DST=" } | Select-Object -First 1)
        if ($d) {
            $p = $d.Substring(4) -split "\|", 3
            Escribir-Salida ("Destino 2: " + $p[0] + "   huecos: " + $p[1] + $(if ($p[2]) { "   " + $p[2] } else { "" }))
            if ($p[0] -ne "VALID") { $problemas += "El envio esta en $($p[0]). Encienda la standby (opcion 2 en esa PC) y luego use la opcion 3 aqui." }
        }
        # 3) Prueba real: cerrar el archivo de cambios y esperar a que la standby lo reciba
        Paso "3/3  Prueba real: se cierra el archivo de cambios y se espera a que la standby lo reciba"
        $seq = Get-Valor "ALTER SYSTEM ARCHIVE LOG CURRENT;`nSELECT MAX(sequence#) FROM v`$archived_log WHERE dest_id = 1 AND resetlogs_change# = (SELECT resetlogs_change# FROM v`$database_incarnation WHERE status = 'CURRENT');"
        Mostrar-Comandos "ALTER SYSTEM ARCHIVE LOG CURRENT;"
        $recibido = $false
        for ($i = 0; $i -lt 15 -and $seq; $i++) {
            $n = Get-Valor "SELECT COUNT(*) FROM v`$archived_log WHERE dest_id = 2 AND sequence# = $seq AND resetlogs_change# = (SELECT resetlogs_change# FROM v`$database_incarnation WHERE status = 'CURRENT');"
            if ($n -match "^[1-9]") { $recibido = $true; break }
            Start-Sleep -Seconds 2
        }
        $tiempo = if ($i -eq 0) { "en menos de 2 segundos" } else { "en unos $($i * 2) segundos" }
        if ($recibido) { Escribir-Salida "La standby recibio el archivo $seq $tiempo [OK]" }
        else { Escribir-Salida "ERROR: la standby no confirmo el archivo $seq en 30 segundos"; $problemas += "La standby no recibio el cambio de prueba." }
    } else {
        # 2) Procesos que reciben (RFS) y aplican (MRP0) los cambios
        Paso "2/3  Data Guard: procesos que reciben (RFS) y aplican (MRP0) los cambios"
        $m = Invoke-Sql "SET HEADING OFF`nSELECT 'PRC=' || process || '|' || status || '|' || sequence# FROM v`$managed_standby WHERE process IN ('RFS', 'MRP0');" -Silencioso
        $prc = @("$m" -split "`n" | Where-Object { $_ -match "^PRC=" })
        $rfs = $prc | Where-Object { $_ -match "^PRC=RFS" -and $_ -notmatch "\|0$" }
        $mrp = $prc | Where-Object { $_ -match "^PRC=MRP0" }
        foreach ($x in ($prc | Where-Object { $_ -notmatch "\|0$" })) { $p = $x.Substring(4) -split "\|"; Escribir-Salida ("Proceso " + $p[0] + ": " + $p[1] + " (archivo " + $p[2] + ")") }
        if (-not $rfs) { $problemas += "No hay proceso RFS: la principal no le esta enviando cambios a esta PC. En la principal use la opcion 3." }
        if (-not $mrp) { $problemas += "No hay proceso MRP0: los cambios no se aplican. Use la opcion 2 en esta PC." }
        # 3) Retraso
        Paso "3/3  Retraso: cuanto le falta a esta PC para estar igual a la principal"
        $g = Invoke-Sql "SET HEADING OFF`nSELECT 'LAG=' || name || '|' || NVL(value, '-') FROM v`$dataguard_stats WHERE name IN ('transport lag', 'apply lag');" -Silencioso
        foreach ($x in @("$g" -split "`n" | Where-Object { $_ -match "^LAG=" })) {
            $p = $x.Substring(4) -split "\|"
            Escribir-Salida ("Retraso de " + $(if ($p[0] -match "transport") { "recepcion" } else { "aplicacion" }) + ": " + $p[1])
            if ($p[1] -match "^\+00 00:0[5-9]|^\+00 00:[1-5]|^\+00 0[1-9]|^\+0[1-9]") { $problemas += "El retraso de $($p[0]) es alto ($($p[1]))." }
        }
    }

    Write-Host ""
    if ($problemas.Count -eq 0) {
        Write-Host "  ======================================================" -ForegroundColor Green
        Write-Host "    CONECTADAS: las dos PC estan sincronizadas." -ForegroundColor Green
        Write-Host "  ======================================================" -ForegroundColor Green
    } else {
        Write-Host "  ======================================================" -ForegroundColor Red
        Write-Host "    NO CONECTADAS (o con problemas). Que revisar:" -ForegroundColor Red
        Write-Host "  ======================================================" -ForegroundColor Red
        foreach ($p in ($problemas | Select-Object -Unique)) { Falla $p }
    }
}

# Estado para la barra superior: rol, modo y Data Guard en una sola consulta
function Get-EstadoMenu {
    $e = @{ Rol = "APAGADO"; Modo = "-"; Nombre = "-"; DG = "" }
    if (-not (Contenedor-Encendido)) { return $e }
    $salida = Invoke-Sql @"
SET HEADING OFF
SELECT 'ROL=' || database_role || '|' || open_mode || '|' || db_unique_name FROM v`$database;
SELECT 'DST=' || status || '|' || NVL(gap_status, '-') FROM v`$archive_dest_status d, v`$database b
 WHERE d.dest_id = 2 AND d.status <> 'INACTIVE' AND b.database_role = 'PRIMARY';
SELECT 'LAG=' || NVL(value, '-') FROM v`$dataguard_stats WHERE name = 'apply lag';
"@ -Silencioso -SinEco
    $lineas = "$salida" -split "`n"
    $rol = $lineas | Where-Object { $_ -match "^ROL=" } | Select-Object -First 1
    if (-not $rol) { $e.Rol = "SIN BASE"; $e.Modo = "APAGADA"; return $e }
    $p = $rol.Substring(4) -split "\|"
    $e.Rol = $p[0].Trim(); $e.Modo = $p[1].Trim(); $e.Nombre = $p[2].Trim()
    $dst = $lineas | Where-Object { $_ -match "^DST=" } | Select-Object -First 1
    $lag = $lineas | Where-Object { $_ -match "^LAG=" } | Select-Object -First 1
    if ($dst) { $d = $dst.Substring(4) -split "\|"; $e.DG = "envio a la standby " + $d[0].Trim() + ", huecos " + $d[1].Trim() }
    elseif ($lag) { $e.DG = "retraso de aplicacion " + $lag.Substring(4).Trim() }
    return $e
}

function Mostrar-Menu {
    Clear-Host
    $e = Get-EstadoMenu
    $w = Ancho
    Write-Host ""
    Write-Host "  SUPER BRUNCA" -ForegroundColor Green -NoNewline
    Write-Host "   administracion de la base de datos" -ForegroundColor DarkGray
    Write-Host ("  " + ($script:Linea * ($w - 4))) -ForegroundColor DarkGray
    $colorRol = switch -Regex ($e.Rol) { "^PRIMARY" { "Green" } "STANDBY" { "Cyan" } default { "Red" } }
    Write-Host ("  {0,-12}" -f "Contenedor") -ForegroundColor DarkGray -NoNewline; Write-Host ("{0,-22}" -f $script:Contenedor) -NoNewline
    Write-Host ("{0,-8}" -f "Base") -ForegroundColor DarkGray -NoNewline; Write-Host $e.Nombre
    Write-Host ("  {0,-12}" -f "Rol") -ForegroundColor DarkGray -NoNewline; Write-Host ("{0,-22}" -f $e.Rol) -ForegroundColor $colorRol -NoNewline
    Write-Host ("{0,-8}" -f "Modo") -ForegroundColor DarkGray -NoNewline; Write-Host $e.Modo
    if ($e.DG) {
        $colorDG = if ($e.DG -cmatch "ERROR|RESOLVABLE") { "Red" } else { "Green" }
        Write-Host ("  {0,-12}" -f "Data Guard") -ForegroundColor DarkGray -NoNewline; Write-Host $e.DG -ForegroundColor $colorDG
    }
    Write-Host ("  " + ($script:Linea * ($w - 4))) -ForegroundColor DarkGray

    # Opciones que aplican a esta base (las demas se muestran en gris)
    $principal = ($e.Rol -eq "PRIMARY" -and $e.Modo -eq "READ WRITE")
    $standby   = ($e.Rol -eq "PHYSICAL STANDBY")
    $abrir     = ($e.Rol -eq "PRIMARY" -and $e.Modo -ne "READ WRITE")
    $apagada   = ($e.Rol -in @("APAGADO", "SIN BASE"))
    $grupos = @(
        @("Consultar", @(
            @("1",  "Ver estado (base, Data Guard, proyecto)", (-not $apagada)),
            @("5",  "Ver los datos replicados en la standby",  $standby),
            @("9",  "Consola SQL del proyecto ($Pdb)",          (-not $apagada)),
            @("10", "Consola SYSDBA (CDB)",                    (-not $apagada)))),
        @("Standby (Data Guard)", @(
            @("14", "Comprobar que las dos PC esten conectadas", ($principal -or $standby)),
            @("2",  "Arrancar / reanudar la standby",          ($standby -or $apagada)),
            @("3",  "Sincronizar ahora y ver el retraso",      ($principal -or $standby)),
            @("6",  "Switchover: pasar el rol a la otra PC",   $principal),
            @("7",  "Abrir como nueva principal",              $abrir),
            @("8",  "Failover: la principal se cayo",          $standby))),
        @("Respaldo", @(
            , @("4",  "Respaldo RMAN ahora (nivel 0 o 1)",     $principal))),   # la coma evita que PowerShell aplane la lista de un elemento
        @("Correos", @(
            @("11", "A que correos llegan los avisos",         $principal),
            @("12", "Clave de Gmail que envia los correos",    $principal),
            @("13", "Enviar un aviso ahora",                   $principal)))
    )
    foreach ($g in $grupos) {
        Write-Host ""
        Write-Host ("  " + $g[0]) -ForegroundColor Yellow
        foreach ($op in $g[1]) {
            $color = if ($op[2]) { "White" } else { "DarkGray" }
            Write-Host ("   {0,3}  " -f $op[0]) -ForegroundColor Cyan -NoNewline
            Write-Host $op[1] -ForegroundColor $color
        }
    }
    Write-Host ""
    Write-Host "     0  Salir" -ForegroundColor DarkGray
    if ($script:SinComandos) { Write-Host "  (comandos ocultos: -SinComandos)" -ForegroundColor DarkGray }
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
        "11" { Op-ConfigurarCorreos }
        "12" { Op-ClaveGmail }
        "13" { Op-EnviarNotificacion }
        "14" { Op-Conexion }
        default { Aviso "Opcion no valida." }
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
    $o = Read-Host "`n  Elija una opcion"
    if ($null -eq $o -or $o -eq "0") { break }   # $null: se cerro la entrada del teclado
    if (-not $o.Trim()) { continue }
    Ejecutar $o.Trim()
    Write-Host ""
    Write-Host ("  " + ($script:Linea * ((Ancho) - 4))) -ForegroundColor DarkGray
    Read-Host "  Enter para volver al menu" | Out-Null
}
