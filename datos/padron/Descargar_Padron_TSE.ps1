<#
================================================================================
PROYECTO: Sistema Integral de Cadena de Supermercados
ARCHIVO:  datos/padron/Descargar_Padron_TSE.ps1
CURSO:    Administracion de Bases de Datos
DESCRIPCION:
  Descarga el Padron Nacional Electoral vigente publicado por el TSE
  (https://www.tse.go.cr/descarga_padron.html, archivo padron_completo.zip,
  ~74 MB) y deja en la carpeta de DIR_PADRON los archivos que leen las tablas
  externas EXT_PADRON_TSE y EXT_DISTELEC_TSE:
      PADRON_COMPLETO.txt   (electores)
      DISTELEC.txt          (nombres de distritos electorales)
      LEAME.txt             (descripcion oficial del formato)

  Lo ejecuta el job CADENA_NEG.JOB_PADRON_DESCARGA (dentro de JOB_PADRON_MENSUAL),
  o se ejecuta a mano antes de: EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;

  Para saber la carpeta de DIR_PADRON:
      SELECT directory_path FROM all_directories WHERE directory_name = 'DIR_PADRON';

EJEMPLO:
  .\Descargar_Padron_TSE.ps1 -Destino C:\app\oracle\oradata\FREE\FREEPDB1
================================================================================
#>
[CmdletBinding()]
param (
    [string]$Url = "https://www.tse.go.cr/zip/padron/padron_completo.zip",
    [Parameter(Mandatory = $true)]
    [string]$Destino
)

$ErrorActionPreference = "Stop"
$temporal = Join-Path ([IO.Path]::GetTempPath()) ("padron_tse_" + (Get-Date -Format "yyyyMMddHHmmss"))

try {
    if (-not (Test-Path $Destino)) { throw "No existe la carpeta destino (DIR_PADRON): $Destino" }
    New-Item -ItemType Directory -Path $temporal -Force | Out-Null
    $zip = Join-Path $temporal "padron_completo.zip"

    Write-Output "[INFO] Descargando $Url ..."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = "SilentlyContinue"   # acelera Invoke-WebRequest en PowerShell 5.1
    Invoke-WebRequest -Uri $Url -OutFile $zip -UseBasicParsing
    Write-Output ("[OK] Descargado: {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

    Expand-Archive -Path $zip -DestinationPath $temporal -Force

    # Los nombres dentro del ZIP pueden variar en mayusculas/minusculas: se normalizan
    $archivos = @{
        "PADRON_COMPLETO.txt" = "*PADRON*.txt"
        "DISTELEC.txt"        = "*DISTELEC*.txt"
        "LEAME.txt"           = "*LEAME*.txt"
    }
    foreach ($nombre in $archivos.Keys) {
        $origen = Get-ChildItem -Path $temporal -Recurse -File -Filter $archivos[$nombre] |
                  Where-Object { $_.Name -notlike "*.zip" } | Sort-Object Length -Descending | Select-Object -First 1
        if ($origen) {
            Copy-Item -Path $origen.FullName -Destination (Join-Path $Destino $nombre) -Force
            Write-Output "[OK] $($origen.Name) -> $nombre"
        } elseif ($nombre -ne "LEAME.txt") {
            throw "El ZIP no contiene $($archivos[$nombre])"
        }
    }
    Write-Output "[OK] Padron listo en $Destino. Siguiente paso: EXEC CADENA_NEG.PKG_PER_PADRON.PR_CARGAR_PADRON_MASIVO;"
    exit 0
} catch {
    Write-Output "[ERROR] $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path $temporal) { Remove-Item -Recurse -Force $temporal -ErrorAction SilentlyContinue }
}
