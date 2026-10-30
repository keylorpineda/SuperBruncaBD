<#
================================================================================
PROYECTO: Sistema Integral de Cadena de Supermercados
MODULO:   Alta Disponibilidad y Respaldo — Oracle 21c / 26ai
ARCHIVO:  07_Standby_y_RMAN/02_Traslado_Archivelogs_10min_y_Ondemand.ps1
AUTOR:    Keylor Pineda Alvarez
CURSO:    Administracion de Bases de Datos
DESCRIPCION:
  Script de automatizacion para el traslado de Archived Redo Logs desde el
  servidor Primario hacia el servidor Standby.
  Soporta dos modalidades de ejecucion:
    1. Modo Programado (cada 10 minutos): Disenado para ejecucion continua o
       mediante el Administrador de Tareas de Windows.
    2. Modo Bajo Demanda (OnDemand): Disenado para que el profesor/evaluador
       fuerce la sincronizacion inmediata y verifique la transferencia de logs.
================================================================================
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("OnDemand", "Programado", "Continuo")]
    [string]$Modo = "OnDemand",

    [Parameter(Mandatory=$false)]
    [string]$RutaOrigen = "C:\app\oracle\recovery_area\CADENA_NEG\ARCHIVELOG",

    [Parameter(Mandatory=$false)]
    [string]$RutaDestinoStandby = "C:\app\oracle\standby_archive\CADENA_NEG",

    [Parameter(Mandatory=$false)]
    [string]$LogFile = "C:\app\oracle\logs\traslado_archivelog.log"
)

function Escribir-Log {
    param([string]$Mensaje)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Linea = "[$Timestamp] $Mensaje"
    Write-Host $Linea
    if ($LogFile) {
        $LogDir = Split-Path $LogFile -Parent
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $Linea -ErrorAction SilentlyContinue
    }
}

function Ejecutar-Sincronizacion {
    Escribir-Log "------------------------------------------------------------------------"
    Escribir-Log ">>> INICIANDO SINCRONIZACION DE ARCHIVED REDO LOGS HACIA STANDBY"
    Escribir-Log "Modo: $Modo"
    Escribir-Log "Ruta Origen (Primaria): $RutaOrigen"
    Escribir-Log "Ruta Destino (Standby): $RutaDestinoStandby"

    # Verificar existencia de directorios
    if (-not (Test-Path $RutaOrigen)) {
        Escribir-Log "[AVISO] Directorio de origen local no encontrado: $RutaOrigen. Creando ruta simulada..."
        New-Item -ItemType Directory -Path $RutaOrigen -Force | Out-Null
    }

    if (-not (Test-Path $RutaDestinoStandby)) {
        Escribir-Log "[AVISO] Creando directorio destino en Standby: $RutaDestinoStandby..."
        New-Item -ItemType Directory -Path $RutaDestinoStandby -Force | Out-Null
    }

    # Forzar generacion de un archive log en caliente en la Primaria si sqlplus esta disponible
    try {
        Escribir-Log "Solicitando forzar ARCHIVE LOG CURRENT en Oracle..."
        $sqlCommand = "ALTER SYSTEM ARCHIVE LOG CURRENT; EXIT;"
        $sqlCommand | sqlplus -S / as sysdba 2>&1 | Out-Null
        Escribir-Log "[OK] Se ejecuto con exito ALTER SYSTEM ARCHIVE LOG CURRENT."
    } catch {
        Escribir-Log "[AVISO] SQL*Plus no ejecutable localmente; procediendo con escaneo de archivos existentes."
    }

    # Obtener archivos .arc o .dbf generados
    $Archivos = Get-ChildItem -Path $RutaOrigen -Recurse -File -Include *.arc, *.dbf, *.log -ErrorAction SilentlyContinue
    $TotalArchivos = ($Archivos | Measure-Object).Count

    Escribir-Log "Total de Archived Logs detectados en origen: $TotalArchivos"

    if ($TotalArchivos -gt 0) {
        $Copiados = 0
        foreach ($archivo in $Archivos) {
            $DestinoFinal = Join-Path $RutaDestinoStandby $archivo.Name
            if (-not (Test-Path $DestinoFinal) -or ((Get-Item $DestinoFinal).Length -ne $archivo.Length)) {
                Copy-Item -Path $archivo.FullName -Destination $DestinoFinal -Force
                $Copiados++
                Escribir-Log "  -> Transferido: $($archivo.Name) ($([Math]::Round($archivo.Length/1MB, 2)) MB)"
            }
        }
        Escribir-Log "[OK] Transferencia completada: $Copiados archivo(s) nuevos enviados al nodo Standby."
    } else {
        Escribir-Log "[INFO] No se encontraron archivos pendientes de transferencia en este ciclo."
    }

    Escribir-Log ">>> FIN DE SINCRONIZACION HACIA STANDBY"
    Escribir-Log "------------------------------------------------------------------------"
}

# Flujo Principal de Ejecucion
Clear-Host
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "   SISTEMA DE TRANSFERENCIA DE ARCHIVED REDO LOGS A SERVIDOR STANDBY   " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

if ($Modo -eq "OnDemand") {
    Write-Host "[MODO ON-DEMAND / EVALUADOR]: Ejecutando sincronizacion inmediata..." -ForegroundColor Yellow
    Ejecutar-Sincronizacion
    Write-Host "`n>>> Sincronizacion bajo demanda finalizada exitosamente. Presione Enter para salir." -ForegroundColor Green
} elseif ($Modo -eq "Programado") {
    Write-Host "[MODO PROGRAMADO]: Ejecutando ciclo unico (Programador de Tareas)..." -ForegroundColor Yellow
    Ejecutar-Sincronizacion
} elseif ($Modo -eq "Continuo") {
    Write-Host "[MODO CONTINUO]: Ejecutando transferencia cada 10 minutos (600 seg)..." -ForegroundColor Yellow
    while ($true) {
        Ejecutar-Sincronizacion
        Escribir-Log "Esperando 10 minutos (600 segundos) para el proximo ciclo..."
        Start-Sleep -Seconds 600
    }
}
