<#
.SYNOPSIS
    Vigila los repos de reglas de firma y avisa cuando publiquen una revision
    que OnlyFans acepte.

.DESCRIPTION
    Cada N minutos descarga las fuentes de reglas usadas por OF-Scraper y
    compara su revision (el primer numero del campo "format") contra la que
    el navegador usa actualmente. Cuando cambia, lanza la comprobacion real
    de auth y escribe el resultado en el log.

    Uso en primer plano (ver por consola):
        .\scripts\watch-rules.ps1

    Uso en segundo plano, escribiendo a un log:
        Start-Job { & .\scripts\watch-rules.ps1 -Minutes 10 -Hours 12 }

.PARAMETER Minutes
    Intervalo entre comprobaciones. Por defecto 10.

.PARAMETER Hours
    Duracion maxima. Por defecto 12.

.PARAMETER Target
    Revision que OF esta pidiendo. Por defecto 67378.

.EXAMPLE
    .\scripts\watch-rules.ps1 -Minutes 15 -Hours 24
#>
[CmdletBinding()]
param(
    [int]$Minutes = 10,
    [int]$Hours   = 12,
    [string]$Target = '67378'
)

$ErrorActionPreference = 'Stop'
$venvPy  = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper\Scripts\python.exe'
$script  = Join-Path $PSScriptRoot 'check-auth.ps1'
$logFile = Join-Path $env:TEMP ("ofs_watch_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log([string]$msg, [string]$color = 'Gray') {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line
}

$py = @'
import httpx, sys
SRC = {
 "digitalcriminals": "https://raw.githubusercontent.com/DATAHOARDERS/dynamic-rules/main/onlyfans.json",
 "datawhores": "https://raw.githubusercontent.com/datawhores/onlyfans-dynamic-rules/main/dynamicRules.json",
 "xagler": "https://raw.githubusercontent.com/xagler/dynamic-rules/main/onlyfans.json",
 "rafa": "https://raw.githubusercontent.com/rafa-9/dynamic-rules/main/rules.json",
 "riley": "https://raw.githubusercontent.com/riley-access-labs/onlyfans-dynamic-rules-1/refs/heads/main/dynamicRules.json",
}
found = {}
for name, url in SRC.items():
    try:
        c = httpx.get(url, timeout=20, follow_redirects=True).json()
        f = c.get("format") or f"{c.get('prefix')}:{{}}:{{:x}}:{c.get('suffix')}"
        found[name] = str(f)
    except Exception:
        found[name] = "ERROR"
for n, f in found.items():
    print(f"{n}|{f}")
'@
$tmpPy = Join-Path $env:TEMP ("ofs_watch_probe_{0}.py" -f (Get-Date -Format 'HHmmss'))
Set-Content -Path $tmpPy -Value $py -Encoding UTF8

try {
    $deadline = (Get-Date).AddHours($Hours)
    Write-Log "vigilante iniciado (cada $Minutes min, hasta $($deadline.ToString('HH:mm'))), buscando revision $Target" 'Cyan'
    Write-Log "log: $logFile" 'DarkGray'

    while ((Get-Date) -lt $deadline) {
        $lines = & $venvPy $tmpPy 2>&1
        $revisions = @{}
        foreach ($l in $lines) {
            if ($l -match '^([^|]+)\|(.+)$') { $revisions[$matches[1]] = $matches[2] }
        }
        $current = $revisions['digitalcriminals']
        $rev = if ($current -match '^\s*(\d{4,6}):') { $matches[1] } else { '?' }

        $usable = $revisions.GetEnumerator() | Where-Object { $_.Value -match "^$Target`:" }
        if ($usable) {
            foreach ($u in $usable) {
                Write-Log "REVISION $Target publicada en '$($u.Key)': $($u.Value)" 'Green'
            }
            Write-Log "lanzando comprobacion real de auth..." 'Green'
            $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $script 2>&1
            $out | ForEach-Object { Add-Content -Path $logFile -Value $_ }
            if ($out -match 'AUTH OK') {
                Write-Log "*** AUTH OK *** OF-Scraper ya puede autenticarse. Lanza la descarga." 'Green'
                exit 0
            }
            Write-Log "reglas actualizadas pero el auth aun falla; sigo vigilando" 'Yellow'
        }
        else {
            Write-Log "digitalcriminals sigue en $rev (esperando $Target)" 'DarkGray'
        }

        $left = [math]::Max(1, [int](($deadline - (Get-Date)).TotalMinutes))
        Start-Sleep -Seconds ([math]::Min($Minutes * 60, $left * 60))
    }
    Write-Log "plazo agotado sin que aparezca la revision $Target" 'Yellow'
    exit 1
}
finally {
    Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
}
