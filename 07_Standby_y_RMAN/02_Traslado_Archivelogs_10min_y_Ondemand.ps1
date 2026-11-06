<#
================================================================================
PROYECTO: Sistema Integral de Cadena de Supermercados
MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai (Windows)
ARCHIVO:  07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.ps1
CURSO:    Administracion de Bases de Datos
DESCRIPCION:
  Orquestador de las tareas de sistema operativo del Standby. Lo invocan los
  jobs DBMS_SCHEDULER de tipo EXECUTABLE creados por CADENA_NEG.PKG_ADM_STANDBY,
  que le pasan como argumentos los valores de SEG_PARAMETRO (rutas, dias, SID).
  Tambien se puede ejecutar a mano (a peticion del academico).

  Modos (-Modo):
    Archivelogs  : fuerza ARCHIVE LOG CURRENT y copia al Standby los archivelogs
                   y los respaldos RMAN nuevos. (Job cada STANDBY_SYNC_MIN min)
    OnDemand     : igual que Archivelogs, pensado para la revision en vivo.
    Backup       : respaldo RMAN diario (nivel 0 domingos / nivel 1 resto) con
                   04_RMAN_Backup_Full_Incremental.rman y copia al Standby.
    Purga        : purga en la PRINCIPAL los archivelogs > N dias ya aplicados
                   en el Standby (03_Purga_Archivelogs_3Dias.rman).
    PurgaStandby : se ejecuta EN LA PC STANDBY; purga los archivelogs ya
                   aplicados > N dias (03_Purga_Archivelogs_Standby.rman).
    Continuo     : ciclo Archivelogs cada -IntervaloMin minutos (alternativa
                   cuando no se usa DBMS_SCHEDULER).

  Arquitectura de dos computadoras:
    PC 1 (PRINCIPAL) : base CADENA (primary). Aqui corren los jobs.
    PC 2 (STANDBY)   : base CADENA_STBY. Comparte por red una carpeta para
                       archivelogs y otra para respaldos, p.ej.
                       \\PC-STANDBY\standby_archive y \\PC-STANDBY\standby_backups

EJEMPLOS:
  .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo OnDemand
  .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo Backup -NivelBackup 0
  .\02_Traslado_Archivelogs_10min_y_Ondemand.ps1 -Modo PurgaStandby -DiasRetencion 3
================================================================================
#>

[CmdletBinding()]
param (
    [ValidateSet("OnDemand", "Archivelogs", "Programado", "Backup", "Purga", "PurgaStandby", "Continuo")]
    [string]$Modo = "OnDemand",

    # Carpeta de archivelogs en la PRINCIPAL (STANDBY_RUTA_ARCHIVE_ORIGEN)
    [string]$RutaOrigen = "C:\app\oracle\recovery_area\CADENA\ARCHIVELOG",

    # Carpeta compartida en la PC STANDBY que recibe los archivelogs (STANDBY_RUTA_ARCHIVE_DESTINO)
    [string]$RutaDestinoStandby = "\\PC-STANDBY\standby_archive",

    # Carpeta de respaldos RMAN en la PRINCIPAL (STANDBY_RUTA_BACKUP_ORIGEN)
    [string]$RutaBackups = "C:\app\oracle\backups",

    # Carpeta compartida en la PC STANDBY que recibe los respaldos (STANDBY_RUTA_BACKUP_DESTINO)
    [string]$RutaBackupsStandby = "\\PC-STANDBY\standby_backups",

    # Dias de retencion de archivelogs (STANDBY_PURGE_DIAS)
    [int]$DiasRetencion = 3,

    # Minutos entre ciclos en modo Continuo (STANDBY_SYNC_MIN)
    [int]$IntervaloMin = 10,

    # -1 = automatico (0 los domingos, 1 el resto de dias)
    [ValidateSet(-1, 0, 1)]
    [int]$NivelBackup = -1,

    # Entorno Oracle (los jobs externos no heredan las variables del usuario)
    [string]$OracleSid = "",
    [string]$OracleHome = "",

    [string]$LogFile = "C:\app\oracle\logs\standby_orquestador.log"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:HuboError = $false

# ------------------------------------------------------------------------------
# Utilidades
# ------------------------------------------------------------------------------
function Escribir-Log {
    param([string]$Mensaje)
    $Linea = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Modo] $Mensaje"
    Write-Output $Linea
    try {
        $LogDir = Split-Path $LogFile -Parent
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $Linea
    } catch { }
}

function Configurar-EntornoOracle {
    if ($OracleSid.Trim())  { $env:ORACLE_SID  = $OracleSid.Trim() }
    if ($OracleHome.Trim()) {
        $env:ORACLE_HOME = $OracleHome
        $env:PATH = (Join-Path $OracleHome "bin") + ";" + $env:PATH
    }
}

function Obtener-Ejecutable([string]$Nombre) {
    if ($env:ORACLE_HOME) {
        $ruta = Join-Path (Join-Path $env:ORACLE_HOME "bin") "$Nombre.exe"
        if (Test-Path $ruta) { return $ruta }
    }
    return $Nombre
}

# Ruta con "/" para RMAN (Oracle en Windows acepta ambas barras)
function Ruta-Rman([string]$Ruta) { return ($Ruta.TrimEnd('\', '/') -replace '\\', '/') }

function Ejecutar-Rman {
    param([string]$Archivo, [string[]]$Variables)
    $rman = Obtener-Ejecutable "rman"
    $cmd  = Join-Path $ScriptDir $Archivo
    $log  = Join-Path (Split-Path $LogFile -Parent) ("rman_" + [IO.Path]::GetFileNameWithoutExtension($Archivo) + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $usar = $Variables | ForEach-Object { "'" + $_ + "'" }
    Escribir-Log "RMAN: $Archivo  USING $($usar -join ' ')"
    & $rman target / "cmdfile=$cmd" "log=$log" using @usar | Out-Null
    if ($LASTEXITCODE -ne 0) {
        $script:HuboError = $true
        Escribir-Log "[ERROR] RMAN termino con codigo $LASTEXITCODE. Revise $log"
    } else {
        Escribir-Log "[OK] RMAN finalizo correctamente. Bitacora: $log"
    }
}

function Forzar-ArchiveLog {
    try {
        $sqlplus = Obtener-Ejecutable "sqlplus"
        "WHENEVER SQLERROR EXIT 1;`nALTER SYSTEM ARCHIVE LOG CURRENT;`nEXIT;" | & $sqlplus -S "/ as sysdba" | Out-Null
        if ($LASTEXITCODE -eq 0) { Escribir-Log "[OK] ALTER SYSTEM ARCHIVE LOG CURRENT ejecutado." }
        else { Escribir-Log "[AVISO] No se pudo forzar el archive log (codigo $LASTEXITCODE)." }
    } catch {
        Escribir-Log "[AVISO] SQL*Plus no disponible: $($_.Exception.Message)"
    }
}

# Copia incremental: solo archivos nuevos o con tamano distinto
function Copiar-Nuevos {
    param([string]$Origen, [string]$Destino, [string[]]$Patrones, [string]$Descripcion)
    if (-not (Test-Path $Origen)) {
        Escribir-Log "[AVISO] No existe la carpeta origen de $Descripcion : $Origen"
        return
    }
    try {
        if (-not (Test-Path $Destino)) { New-Item -ItemType Directory -Path $Destino -Force | Out-Null }
    } catch {
        $script:HuboError = $true
        Escribir-Log "[ERROR] No se puede acceder al destino Standby $Destino : $($_.Exception.Message)"
        return
    }
    $archivos = Get-ChildItem -Path $Origen -Recurse -File -Include $Patrones -ErrorAction SilentlyContinue
    $copiados = 0
    foreach ($a in $archivos) {
        $dest = Join-Path $Destino $a.Name
        if (-not (Test-Path $dest) -or ((Get-Item $dest).Length -ne $a.Length)) {
            try {
                Copy-Item -Path $a.FullName -Destination $dest -Force
                $copiados++
                Escribir-Log "  -> $($a.Name) ($([Math]::Round($a.Length / 1MB, 2)) MB)"
            } catch {
                $script:HuboError = $true
                Escribir-Log "[ERROR] Fallo la copia de $($a.Name): $($_.Exception.Message)"
            }
        }
    }
    Escribir-Log "[OK] $Descripcion : $copiados archivo(s) nuevo(s) de $(($archivos | Measure-Object).Count) trasladado(s) a $Destino"
}

# ------------------------------------------------------------------------------
# Tareas
# ------------------------------------------------------------------------------
function Tarea-Traslado {
    Escribir-Log ">>> TRASLADO HACIA EL STANDBY"
    Forzar-ArchiveLog
    Copiar-Nuevos -Origen $RutaOrigen  -Destino $RutaDestinoStandby -Patrones @("*.arc", "*.dbf", "*.log") -Descripcion "Archivelogs"
    Copiar-Nuevos -Origen $RutaBackups -Destino $RutaBackupsStandby -Patrones @("*.bkp")                -Descripcion "Respaldos RMAN"
}

function Tarea-Backup {
    $nivel = $NivelBackup
    if ($nivel -lt 0) { $nivel = if ((Get-Date).DayOfWeek -eq [DayOfWeek]::Sunday) { 0 } else { 1 } }
    Escribir-Log ">>> RESPALDO RMAN NIVEL $nivel"
    if (-not (Test-Path $RutaBackups)) { New-Item -ItemType Directory -Path $RutaBackups -Force | Out-Null }
    Ejecutar-Rman -Archivo "04_RMAN_Backup_Full_Incremental.rman" -Variables @((Ruta-Rman $RutaBackups), "$nivel")
    # El respaldo diario tambien se traslada al Standby
    Copiar-Nuevos -Origen $RutaBackups -Destino $RutaBackupsStandby -Patrones @("*.bkp") -Descripcion "Respaldos RMAN"
}

function Tarea-Purga {
    Escribir-Log ">>> PURGA EN LA PRINCIPAL (> $DiasRetencion dias, ya aplicados en Standby)"
    Ejecutar-Rman -Archivo "03_Purga_Archivelogs_3Dias.rman" -Variables @("$DiasRetencion")
}

function Tarea-PurgaStandby {
    # En la PC Standby, -RutaDestinoStandby es la carpeta LOCAL donde llegan los logs
    Escribir-Log ">>> PURGA EN EL STANDBY (> $DiasRetencion dias, ya aplicados)"
    Ejecutar-Rman -Archivo "03_Purga_Archivelogs_Standby.rman" -Variables @("$DiasRetencion", (Ruta-Rman $RutaDestinoStandby))
}

# ------------------------------------------------------------------------------
# Flujo principal
# ------------------------------------------------------------------------------
Configurar-EntornoOracle
Escribir-Log "========== INICIO (SID=$($env:ORACLE_SID)) =========="

try {
    switch ($Modo) {
        "OnDemand"     { Tarea-Traslado }
        "Archivelogs"  { Tarea-Traslado }
        "Programado"   { Tarea-Traslado }   # nombre anterior, se mantiene por compatibilidad
        "Backup"       { Tarea-Backup }
        "Purga"        { Tarea-Purga }
        "PurgaStandby" { Tarea-PurgaStandby }
        "Continuo" {
            while ($true) {
                Tarea-Traslado
                Escribir-Log "Esperando $IntervaloMin minuto(s) para el proximo ciclo..."
                Start-Sleep -Seconds ($IntervaloMin * 60)
            }
        }
    }
} catch {
    $script:HuboError = $true
    Escribir-Log "[ERROR] $($_.Exception.Message)"
}

Escribir-Log "========== FIN =========="
# Codigo de salida distinto de 0 => DBMS_SCHEDULER registra el job como FAILED
if ($script:HuboError) { exit 1 } else { exit 0 }
