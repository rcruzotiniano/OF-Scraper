<#
.SYNOPSIS
    Convierte un CDM Widevine (.wvd) en los dos archivos que OF-Scraper necesita.

.DESCRIPTION
    OF-Scraper no lee .wvd: en modo "manual" necesita los dos archivos sueltos:
        device_private_key
        device_client_id_blob

    Este script usa pywidevine instalado dentro del propio venv aislado de
    OF-Scraper (via pipx), asi que NO hace falta el venv de VT-PR ni instalar nada.

.PARAMETER WvdPath
    Ruta al archivo .wvd (por ejemplo el que exporte KeyDive).

.PARAMETER OutDir
    Carpeta destino de los dos archivos. Por defecto C:\CDM\of

.EXAMPLE
    .\tools\export-wvd.ps1 -WvdPath C:\CDM\l3.wvd

.EXAMPLE
    .\tools\export-wvd.ps1 -WvdPath C:\CDM\l3.wvd -OutDir D:\cdm\of
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$WvdPath,

    [string]$OutDir = 'C:\CDM\of'
)

$ErrorActionPreference = 'Stop'

# --- Localizar pywidevine dentro del venv de pipx ---
$pipxVenv = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper'
$pywidevine = Join-Path $pipxVenv 'Scripts\pywidevine.exe'

if (-not (Test-Path $pywidevine)) {
    throw "No encuentro pywidevine en '$pywidevine'. Reinstala con: pipx install ofscraper --force"
}

# --- Validar el .wvd ---
if (-not (Test-Path -LiteralPath $WvdPath)) {
    throw "No existe el archivo .wvd: $WvdPath"
}
$WvdPath = (Resolve-Path -LiteralPath $WvdPath).Path
if ([IO.Path]::GetExtension($WvdPath) -ne '.wvd') {
    Write-Warning "El archivo no tiene extension .wvd ($WvdPath). Se intentara igualmente."
}

# --- Crear destino ---
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

Write-Host "WVD      : $WvdPath" -ForegroundColor Cyan
Write-Host "Destino  : $OutDir" -ForegroundColor Cyan

# --- Exportar ---
& $pywidevine export-device $WvdPath -o $OutDir
if ($LASTEXITCODE -ne 0) {
    throw "pywidevine export-device fallo con codigo $LASTEXITCODE. El .wvd puede estar revocado o corrupto."
}

# --- Verificar resultado ---
$key  = Join-Path $OutDir 'device_private_key'
$blob = Join-Path $OutDir 'device_client_id_blob'
$ok = $true
foreach ($f in @($key, $blob)) {
    if (Test-Path -LiteralPath $f) {
        Write-Host ("OK  {0}  ({1} bytes)" -f (Split-Path $f -Leaf), (Get-Item -LiteralPath $f).Length) -ForegroundColor Green
    } else {
        Write-Host "FALTA $f" -ForegroundColor Red
        $ok = $false
    }
}

if ($ok) {
    Write-Host ""
    Write-Host "Siguiente paso: OF-Scraper ya apunta a esas rutas (key-mode manual)." -ForegroundColor Green
    Write-Host "Comprueba la config con:  ofscraper -h  > Edit Config Settings > Edit Advanced Options"
} else {
    throw "La exportacion no genero los dos archivos esperados."
}
