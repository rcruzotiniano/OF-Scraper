<#
.SYNOPSIS
    Importa las cookies reales de OnlyFans desde el navegador y escribe auth.json.

.DESCRIPTION
    Lee el almacen del navegador (NO document.cookie, asi que incluye las cookies
    HttpOnly, que son justo sess y auth_id). Las extensiones que leen con
    JavaScript no pueden ver esas cookies: por eso devuelven valores vacios.

    Conserva user_agent y x-bc que ya tuvieras en auth.json, y hace backup.

.PARAMETER Browser
    auto (por defecto), chrome, edge, brave, opera, vivaldi, chromium, firefox

.PARAMETER UserAgent
    Forzar user-agent (si no, usa el de auth.json actual)

.PARAMETER XBc
    Forzar x-bc (si no, usa el de auth.json actual)

.EXAMPLE
    .\scripts\import-cookies.ps1
    .\scripts\import-cookies.ps1 -Browser edge
#>
[CmdletBinding()]
param(
    [string]$Browser   = 'auto',
    [string]$UserAgent = '',
    [string]$XBc       = ''
)

$ErrorActionPreference = 'Stop'

$venvPy   = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper\Scripts\python.exe'
$authFile = Join-Path $env:USERPROFILE '.config\ofscraper\main_profile\auth.json'
if (-not (Test-Path $venvPy)) { throw "No encuentro el entorno de OF-Scraper en $venvPy" }

$py = @'
import json, pathlib, shutil, sys, time
import browser_cookie3 as bc

AUTH_FILE = pathlib.Path(r"__AUTH_FILE__")
WANT      = "__BROWSER__"
UA_OVERRIDE  = "__UA__"
XBC_OVERRIDE = "__XBC__"
APP_TOKEN    = "33d57ade8c02dbc5a333db99ff9ae26a"

old = {}
if AUTH_FILE.exists():
    try:
        old = json.loads(AUTH_FILE.read_text(encoding="utf-8"))
    except Exception:
        old = {}

order = ["chrome", "edge", "brave", "opera", "vivaldi", "chromium", "firefox"]
if WANT != "auto":
    order = [WANT]

def gather(name):
    fn = getattr(bc, name, None)
    if fn is None:
        return None, "no soportado"
    try:
        jar = fn(domain_name="onlyfans.com")
    except PermissionError as e:
        return None, "BLOQUEADO (cierra el navegador): " + str(e)[:80]
    except Exception as e:
        return None, f"{type(e).__name__}: {str(e)[:80]}"
    out = {}
    for c in jar:
        if "onlyfans" in (c.domain or "") and c.value:
            out.setdefault(c.name, c.value)
    return out, None

chosen = None
for name in order:
    data, err = gather(name)
    if err:
        print(f"  {name:10} {err}")
        continue
    if not data:
        print(f"  {name:10} sin cookies de onlyfans")
        continue
    print(f"  {name:10} leidas {len(data)} cookies:")
    for k in sorted(data):
        print(f"             - {k}  ({len(data[k])} chars)")
    if data.get("sess") and data.get("auth_id"):
        chosen = (name, data)
        break
    print(f"  {name:10} pero faltan sess/auth_id, sigo con el siguiente")

if not chosen:
    print("\n[FALLO] Ningun navegador dio sess + auth_id.")
    print("Cierra Chrome/Edge del todo (ni en bandeja) y reintenta.")
    print("Si sigue igual, usa la via manual: F12 > Network > XHR > recarga > 'init' > Request Headers > Cookie")
    raise SystemExit(1)

name, data = chosen
sess = data.get("sess", "")
aid  = data.get("auth_id", "")
auid = data.get("auth_uid") or data.get("auth_uid_") or ""
if not auid:
    for k, v in data.items():
        if k.startswith("auth_uid"):
            auid = v
            break

print(f"\nOrigen: {name}")
print(f"  sess    : {len(sess)} chars")
print(f"  auth_id : {len(aid)} chars -> {aid[:6]}...{' (NUMERICO!)' if aid.isdigit() else ''}")
print(f"  auth_uid: {auid}")

if aid.isdigit() or len(aid) < 20:
    print("\n[AVISO] auth_id sigue pareciendo el ID numerico, no el valor del cookie 'auth_id='.")
    print("        Cookie crudo encontrado: ", {k: (len(v)) for k, v in data.items()})

ua  = UA_OVERRIDE or old.get("user_agent") or ""
xbc = XBC_OVERRIDE or old.get("x-bc") or ""
if not ua or not xbc:
    print("\n[FALLO] Falta user_agent o x-bc (no hay valor previo en auth.json).")
    print("        Pasalos con -UserAgent '...' -XBc '...'")
    raise SystemExit(1)

new = {
    "sess": sess,
    "auth_id": aid,
    "auth_uid": auid or old.get("auth_uid") or "",
    "user_agent": ua,
    "x-bc": xbc,
    "app-token": APP_TOKEN,
}

if AUTH_FILE.exists():
    bak = AUTH_FILE.with_suffix(f".json.bak-{int(time.time())}")
    shutil.copy2(AUTH_FILE, bak)
    print(f"\nBackup: {bak.name}")

AUTH_FILE.write_text(json.dumps(new, indent=4), encoding="utf-8")
print(f"Escrito: {AUTH_FILE}")
print("Ahora ejecuta: .\\scripts\\check-auth.ps1")
'@

$py = $py.Replace("__AUTH_FILE__", $authFile).Replace("__BROWSER__", $Browser).Replace("__UA__", $UserAgent).Replace("__XBC__", $XBc)
$tmp = Join-Path $env:TEMP ("ofs_importauth_{0}.py" -f [guid]::NewGuid().ToString("N"))
Set-Content -Path $tmp -Value $py -Encoding UTF8
try {
    & $venvPy $tmp
    $code = $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
exit $code
