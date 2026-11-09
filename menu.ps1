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

# Muestra los comandos reales que se van a ejecutar, para que se vea que no es una simulacion
function Mostrar-Comandos([string]$sql) {
    if ($script:SinComandos) { return }
    $lineas = @(($sql -replace "`r`n", "`n") -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch "^\s*(SET |PROMPT|COLUMN |/\s*$)" })
    if ($lineas.Count -eq 0) { return }
    Write-Host "  [$($script:Contenedor)] sqlplus / as sysdba" -ForegroundColor DarkCyan
    $sigue = $false
    foreach ($l in $lineas) {
        $prefijo = if ($sigue) { "       " } else { "  SQL> " }
        Write-Host ($prefijo + $l.Trim()) -ForegroundColor DarkCyan
        $t = $l.TrimEnd()
        $sigue = -not ($t.EndsWith(";") -or $t -match "^(BEGIN|DECLARE)$")
        if ($t -match "^(BEGIN|DECLARE)$") { $sigue = $true }
    }
}

function Mostrar-Comando-SO([string]$cmd) {
    if ($script:SinComandos) { return }
    Write-Host "  [$($script:Contenedor)] `$ $cmd" -ForegroundColor DarkCyan
}

# Ejecuta SQL como SYSDBA dentro del contenedor y devuelve el texto de salida.
# -SinEco: no muestra el comando (consultas internas del menu o comandos con una clave)
function Invoke-Sql([string]$sql, [switch]$Silencioso, [switch]$SinEco) {
    if (-not $SinEco) { Mostrar-Comandos $sql }
    $tmp = Join-Path $env:TEMP "menu_cadena.sql"
    $texto = "SET LINESIZE 200 PAGESIZE 100 FEEDBACK OFF SERVEROUTPUT ON SIZE UNLIMITED`nWHENEVER SQLERROR CONTINUE`n" +
             ($sql -replace "`r`n", "`n") + "`nEXIT;`n"
    [IO.File]::WriteAllText($tmp, $texto, (New-Object Text.UTF8Encoding $false))
    docker cp $tmp "$($script:Contenedor):/tmp/menu_cadena.sql" 2>$null | Out-Null
    $salida = docker exec -u oracle $script:Contenedor sqlplus -s "/ as sysdba" "@/tmp/menu_cadena.sql" 2>&1
    docker exec -u root $script:Contenedor rm -f /tmp/menu_cadena.sql 2>$null | Out-Null   # puede contener una clave
    Remove-Item $tmp -ErrorAction SilentlyContinue
    $salida = ($salida | Where-Object { $_ -ne $null -and "$_".Trim() -ne "" }) -join "`n"
    if (-not $Silencioso) { Write-Host $salida }
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
    Write-Host $mensaje -ForegroundColor Yellow
    return ((Read-Host "Escriba SI para continuar") -eq "SI")
}

function Esperar-Contenedor {
    if (-not (Contenedor-Encendido)) {
        Write-Host "Encendiendo el contenedor $($script:Contenedor)..."
        if (-not $script:SinComandos) { Write-Host "  `$ docker start $($script:Contenedor)" -ForegroundColor DarkCyan }
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
    Mostrar-Comando-SO "cd $ScriptsStandby && $cmd   (RMAN: 04_RMAN_Backup_Full_Incremental.rman)"
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
    Titulo "CORREOS DE DESTINO DE LAS NOTIFICACIONES"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY" -or $r.Modo -ne "READ WRITE") { Write-Host "Esta opcion se usa en la PRINCIPAL (abierta). Esta base es $($r.Rol) / $($r.Modo)." -ForegroundColor Yellow; return }
    Invoke-Sql @"
SET HEADING OFF
ALTER SESSION SET CONTAINER = $Pdb;
PROMPT Valores actuales:
SELECT '  ' || RPAD(codigo_para, 20) || valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO
 WHERE codigo_para IN ('CORREO_EMISOR', 'CORREO_COORDINADOR', 'CORREO_GERENTE', 'CORREO_DBA') ORDER BY codigo_para;
"@ | Out-Null
    Write-Host ""
    Write-Host "Puede escribir varios correos separados por coma."
    $todos = Read-Host "Correo para TODAS las alertas (Enter = configurar uno por uno)"
    $valores = @{}
    if ($todos.Trim()) {
        $v = Validar-Correos $todos; if (-not $v) { return }
        foreach ($k in "CORREO_COORDINADOR", "CORREO_GERENTE", "CORREO_DBA") { $valores[$k] = $v }
    } else {
        foreach ($k in "CORREO_COORDINADOR", "CORREO_GERENTE", "CORREO_DBA") {
            $t = Read-Host "  $k (Enter = no cambiar)"
            if ($t.Trim()) { $v = Validar-Correos $t; if (-not $v) { return }; $valores[$k] = $v }
        }
    }
    if ($valores.Count -eq 0) { Write-Host "No se cambio nada."; return }

    $desc = @{
        "CORREO_COORDINADOR" = @("Correo del coordinador", "Destinatario de alertas de mercadeo, clientes 85%, vencidos y cierres.")
        "CORREO_GERENTE"     = @("Correo del gerente", "Destinatario de alertas de proveedores 70%, morosidad y cierres diarios.")
        "CORREO_DBA"         = @("Correo del administrador BD", "Destinatario de alertas de tablespaces, objetos invalidos e indices danados.")
    }
    $sql = "ALTER SESSION SET CONTAINER = $Pdb;`n"
    foreach ($k in $valores.Keys) {
        $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('$k', 'CORREO', '$($desc[$k][0])', '$($desc[$k][1])', 'N', '$($valores[$k])');`n"
    }
    # Los avisos individuales de "credito al 85%" van al correo de cada cliente (PER_CONTACTO)
    $cli = Read-Host "Enviar tambien los avisos a CLIENTES a ese correo (demostracion)? (s/N)"
    if ($cli -match "^[sS]") {
        $correoCli = (@($valores.Values) | Select-Object -First 1).Split(",")[0].Trim()
        $sql += "UPDATE CADENA_NEG.PER_CONTACTO SET VALOR_CONT = '$correoCli' WHERE TIPO_CONT = 'E';`nCOMMIT;`n"
    }
    Invoke-Sql $sql -Silencioso | Out-Null
    Write-Host "[OK] Correos guardados en SEG_PARAMETRO." -ForegroundColor Green

    if ((Read-Host "Enviar un correo de prueba ahora? (S/n)") -notmatch "^[nN]") {
        $dest = (@($valores.Values) | Select-Object -Unique) -join ", "
        Invoke-Sql @"
ALTER SESSION SET CONTAINER = $Pdb;
SET SERVEROUTPUT ON SIZE UNLIMITED
EXEC CADENA_NEG.PKG_ADM_NOTIFICACION.PR_ENVIAR_CORREO('$dest', 'Prueba de notificaciones - Super Brunca', 'PRUEBA DE CORREO DESDE ORACLE' || CHR(10) || 'Este es un correo de prueba enviado directamente desde la base de datos.' || CHR(10) || 'Destinatarios : $dest');
"@ -Silencioso | Where-Object { $_ } | ForEach-Object { $_ -split "`n" } | Where-Object { $_ -match "Estado SMTP" } | ForEach-Object { Write-Host $_ }
    }
}

function Op-ClaveGmail {
    Titulo "CLAVE DE APLICACION DE GMAIL (correo que envia)"
    $r = Get-Rol
    if ($r.Rol -ne "PRIMARY" -or $r.Modo -ne "READ WRITE") { Write-Host "Esta opcion se usa en la PRINCIPAL (abierta). Esta base es $($r.Rol) / $($r.Modo)." -ForegroundColor Yellow; return }
    Write-Host "Se usa una 'contrasena de aplicacion' de 16 letras (https://myaccount.google.com/apppasswords),"
    Write-Host "no la contrasena normal de Gmail. Se guarda CIFRADA con AES-256 en SEG_PARAMETRO."
    $emisor = Read-Host "Correo de Gmail que envia (Enter = no cambiar)"
    $segura = Read-Host "Clave de aplicacion (no se muestra)" -AsSecureString
    $clave = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($segura))
    $clave = ($clave -replace "\s", "")
    if ($clave -notmatch "^[A-Za-z]{16}$") { Write-Host "La clave de aplicacion de Gmail son 16 letras. No se guardo nada." -ForegroundColor Red; return }
    $sql = "ALTER SESSION SET CONTAINER = $Pdb;`n"
    if ($emisor.Trim()) {
        $v = Validar-Correos $emisor; if (-not $v) { return }
        $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CORREO_EMISOR', 'CORREO', 'Correo emisor del sistema', 'Cuenta remitente de las notificaciones automaticas (Gmail autenticado).', 'N', '$v');`n"
    }
    $sql += "EXEC CADENA_NEG.PKG_SEG_SEGURIDAD.PR_GUARDAR_PARAMETRO('CLAVE_CORREO_EMISOR', 'CORREO', 'Clave cifrada del correo emisor', 'Contrasena de aplicacion SMTP cifrada con DBMS_CRYPTO AES-256.', 'S', '$clave');`n"
    Invoke-Sql $sql -Silencioso -SinEco | Out-Null   # lleva la clave: nunca se muestra
    $clave = $null
    Write-Host "[OK] Clave guardada cifrada." -ForegroundColor Green
    # El wallet con los certificados de Gmail (se pierde el parametro al reinstalar el esquema)
    docker exec -u oracle $script:Contenedor bash -c "test -f /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh && bash /opt/oracle/proyecto/sql/08_Wallet_SMTP_Gmail.sh | tail -1" 2>$null | ForEach-Object { Write-Host $_ }
    Write-Host "Pruebe el envio con la opcion 11 (correo de prueba)."
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
    foreach ($k in $opciones.Keys) { Write-Host ("  {0,2}. {1}" -f $k, $opciones[$k][0]) }
    Write-Host "   0. Volver"
    Write-Host ""
    Write-Host "Destino actual:" -ForegroundColor DarkGray
    Invoke-Sql @"
SET HEADING OFF
ALTER SESSION SET CONTAINER = $Pdb;
SELECT '  ' || RPAD(codigo_para, 20) || valor_texto_para FROM CADENA_NEG.SEG_PARAMETRO
 WHERE codigo_para IN ('CORREO_COORDINADOR', 'CORREO_GERENTE', 'CORREO_DBA') ORDER BY codigo_para;
"@ | Out-Null
    $o = Read-Host "`nCual notificacion"
    if (-not $opciones.Contains($o)) { return }
    if ($o -eq "1" -or $o -eq "5") {
        Write-Host "Nota: el aviso individual va al correo de cada cliente (PER_CONTACTO). Para recibirlos usted, use la opcion 11 y responda 's' a 'avisos a CLIENTES'." -ForegroundColor DarkGray
    }
    if ($o -eq "10" -and -not (Confirmar "La premiacion guarda las ordenes de compra del periodo actual en PRM_ORDEN_PREMIACION.")) { return }
    Write-Host "Ejecutando: $($opciones[$o][0])..."
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
    if (-not $lineas) { Write-Host "Termino sin nada que avisar (no se envio correo)." -ForegroundColor Yellow; return }
    foreach ($l in $lineas) {
        $l = $l.Trim()
        $l = $l -replace "\s+:", " :"
        if ($l -match "Asunto") { Write-Host ""; Write-Host "  $l" -ForegroundColor Cyan }
        elseif ($l -match "entregada|\[OK\]") { Write-Host "  $l" -ForegroundColor Green }
        elseif ($l -match "Fallo|ORA-") { Write-Host "  $l" -ForegroundColor Red }
        else { Write-Host "  $l" }
    }
    $n = @($lineas | Where-Object { $_ -match "entregada" }).Count
    Write-Host ""
    Write-Host "Correos enviados: $n" -ForegroundColor Green
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
    Write-Host " 11. Correos de destino de las notificaciones    (en la principal)"
    Write-Host " 12. Clave de Gmail que envia los correos        (en la principal)"
    Write-Host " 13. Enviar una notificacion ahora (correo)      (en la principal)"
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
        "11" { Op-ConfigurarCorreos }
        "12" { Op-ClaveGmail }
        "13" { Op-EnviarNotificacion }
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
