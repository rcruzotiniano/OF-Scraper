<#
.SYNOPSIS
    Comprueba el estado real del auth de OnlyFans para OF-Scraper.

.DESCRIPTION
    Firma una peticion a /api2/v2/users/me igual que lo hace OF-Scraper (reglas
    dinamicas + cookies de auth.json) y clasifica la respuesta:

      200                       -> AUTH OK, puedes descargar
      301 Wrong user            -> la firma no identifica al usuario
      401 Please refresh page   -> OF rechaza la revision de firma: las reglas
                                   online estan desfasadas (problema upstream,
                                   no de tus cookies)

    Nota: el navegador puede devolver 200 con las MISMAS cookies. En ese caso
    las cookies son validas y el bloqueo es de la firma de OF-Scraper.

.EXAMPLE
    .\scripts\check-auth.ps1
#>
[CmdletBinding()]
param(
    [string]$AuthFile = "$env:USERPROFILE\.config\ofscraper\main_profile\auth.json",
    [string]$Source   = 'https://raw.githubusercontent.com/DATAHOARDERS/dynamic-rules/main/onlyfans.json'
)

$ErrorActionPreference = 'Stop'

$venvPy = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper\Scripts\python.exe'
if (-not (Test-Path $venvPy))    { throw "No encuentro el entorno de OF-Scraper en $venvPy" }
if (-not (Test-Path $AuthFile))  { throw "No existe auth.json en $AuthFile" }

$py = @'
import hashlib, json, pathlib, time
from urllib.parse import urlparse
import httpx

AUTH_FILE = r"__AUTH_FILE__"
RULES_URL = "__RULES__"
APP_TOKEN = "33d57ade8c02dbc5a333db99ff9ae26a"
LINK = "https://onlyfans.com/api2/v2/users/me"

auth = json.loads(pathlib.Path(AUTH_FILE).read_text(encoding="utf-8"))
print(f"auth.json -> sess {len(auth.get('sess',''))} chars | auth_id {auth.get('auth_id')} | auth_uid {auth.get('auth_uid') or auth.get('auth_uid_')}")

try:
    c = httpx.get(RULES_URL, timeout=30, follow_redirects=True).json()
except Exception as e:
    print(f"[FALLO] no pude descargar reglas: {type(e).__name__}: {str(e)[:120]}")
    raise SystemExit(2)

fmt = c.get("format")
if fmt is None and c.get("prefix") is not None:
    fmt = f"{c['prefix']}:{{}}:{{:x}}:{c['suffix']}"
print(f"reglas     -> revision observada en formato: {fmt}")

uid = str(auth.get("auth_id") or "")
t = str(round(time.time() * 1000))
# Igual que ofscraper/utils/auth/request.py: la ruta firmada incluye la query
u = urlparse(LINK)
signed_path = u.path if not u.query else f"{u.path}?{u.query}"
msg = "\n".join([str(c["static_param"]), t, signed_path, uid]).encode()
sha = hashlib.sha1(msg, usedforsecurity=False).hexdigest()
checksum = sum(sha.encode("ascii")[i] for i in c["checksum_indexes"]) + c["checksum_constant"]
sign = fmt.format(sha, abs(checksum))

headers = {
    "accept": "application/json, text/plain, */*",
    "app-token": APP_TOKEN,
    "x-bc": auth.get("x-bc", ""),
    "referer": "https://onlyfans.com",
    "user-agent": auth.get("user_agent", ""),
    # El header user-id es necesario: sin el, OF responde 401
    "user-id": uid,
    "sign": sign,
    "time": t,
}
cookies = {"sess": auth.get("sess", ""), "auth_id": uid}
if auth.get("auth_uid") or auth.get("auth_uid_"):
    cookies["auth_uid_"] = str(auth.get("auth_uid") or auth.get("auth_uid_"))

try:
    r = httpx.get(LINK, headers=headers, cookies=cookies, timeout=40, follow_redirects=True)
except Exception as e:
    print(f"[FALLO] red: {type(e).__name__}: {str(e)[:120]}")
    raise SystemExit(2)

body = r.text[:220]
print(f"\nSTATUS {r.status_code} -> {body}")

if r.status_code == 200:
    d = r.json()
    print(f"\n*** AUTH OK *** id={d.get('id')} usuario={d.get('username')} suscripciones={d.get('subscribesCount')}")
    raise SystemExit(0)

if "Please refresh the page" in body:
    print("\nVEREDICTO: tus cookies NO son el problema. OF rechaza la REVISION de firma")
    print("           que usan las reglas publicas (van por detras del frontend actual).")
    print("           Comprueba en el navegador: F12 > Network > peticion 'init' >")
    print("           header 'sign' -> el primer numero es la revision que OF espera.")
    print("           Cuando las reglas publicadas la alcancen, OF-Scraper funcionara")
    print("           sin tocar tu config (las reglas se cachean ~30 min).")
    raise SystemExit(3)

if "Wrong user" in body:
    print("\nVEREDICTO: la firma no identifica al usuario. Revisa sess/auth_id contra")
    print("           el header Cookie de la peticion 'init' en el navegador.")
    raise SystemExit(1)

print("\nVEREDICTO: respuesta inesperada, revisa el cuerpo de arriba.")
raise SystemExit(1)
'@

$py = $py.Replace("__AUTH_FILE__", $AuthFile).Replace("__RULES__", $Source)
$tmp = Join-Path $env:TEMP ("ofs_checkauth_{0}.py" -f [guid]::NewGuid().ToString("N"))
Set-Content -Path $tmp -Value $py -Encoding UTF8
try {
    & $venvPy $tmp
    $code = $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
exit $code
