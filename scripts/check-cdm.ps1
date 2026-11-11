<#
.SYNOPSIS
    Comprueba que los dos archivos del CDM son validos y que el CDM puede abrir sesion.

.DESCRIPTION
    Carga device_private_key y device_client_id_blob con pywidevine (el mismo
    camino que usa OF-Scraper en keyhelpers.key_helper_manual) y crea un Cdm.
    No contacta con OnlyFans ni descarga nada.

    Si esto pasa, el CDM sirve. Si falla, el problema es el CDM, no la config.

.EXAMPLE
    .\scripts\check-cdm.ps1
#>
[CmdletBinding()]
param(
    [string]$PrivateKey = 'C:\CDM\of\device_private_key',
    [string]$ClientId   = 'C:\CDM\of\device_client_id_blob'
)

$ErrorActionPreference = 'Stop'

$venvPy = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper\Scripts\python.exe'
if (-not (Test-Path $venvPy)) { throw "No encuentro el entorno de OF-Scraper en $venvPy" }

$missing = @($PrivateKey, $ClientId) | Where-Object { -not (Test-Path -LiteralPath $_) }
if ($missing) {
    Write-Host "FALTAN archivos del CDM:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Ejecuta antes: .\scripts\export-wvd.ps1 -WvdPath <tu.wvd>" -ForegroundColor Yellow
    exit 1
}

$py = @'
import pathlib, sys
from pywidevine.device import Device
from pywidevine.cdm import Cdm

pk = pathlib.Path(r"__PK__").read_bytes()
ci = pathlib.Path(r"__CI__").read_bytes()

try:
    device = Device(security_level=3, private_key=pk, client_id=ci, type_="ANDROID", flags=None)
    cdm = Cdm.from_device(device)
    sid = cdm.open()
    cdm.close(sid)
except Exception as e:
    print(f"*** CDM INVALIDO *** {type(e).__name__}: {str(e)[:300]}")
    raise SystemExit(1)

print("*** CDM OK ***")
print(f"  system_id : {device.system_id}")
print(f"  tipo      : {device.type}  L{device.security_level}")
print(f"  key size  : {len(pk)} bytes | client_id {len(ci)} bytes")
'@

$py = $py.Replace("__PK__", $PrivateKey).Replace("__CI__", $ClientId)
$tmp = Join-Path $env:TEMP ("ofs_checkcdm_{0}.py" -f [guid]::NewGuid().ToString("N"))
Set-Content -Path $tmp -Value $py -Encoding UTF8
try {
    & $venvPy $tmp
    $code = $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
exit $code
