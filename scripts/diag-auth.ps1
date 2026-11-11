<#
.SYNOPSIS
    Aisla si el fallo de auth viene de las cookies o de la firma.

.DESCRIPTION
    Hace dos experimentos controlados:

    1) MISMA firma, cookies reales vs cookies inventadas.
       Si el resultado es identico, las cookies no son la variable.

    2) MISMAS cookies reales, firmas de distintas revisiones.
       Si el resultado cambia, la variable es la firma.

    No escribe nada ni descarga contenido. Solo lee auth.json.

.EXAMPLE
    .\scripts\diag-auth.ps1
#>
[CmdletBinding()]
param(
    [string]$AuthFile = "$env:USERPROFILE\.config\ofscraper\main_profile\auth.json"
)

$ErrorActionPreference = 'Stop'
$venvPy = Join-Path $env:LOCALAPPDATA 'pipx\pipx\venvs\ofscraper\Scripts\python.exe'
if (-not (Test-Path $venvPy))   { throw "No encuentro el entorno de OF-Scraper en $venvPy" }
if (-not (Test-Path $AuthFile)) { throw "No existe auth.json en $AuthFile" }

$py = @'
import hashlib, json, pathlib, time
from urllib.parse import urlparse
import httpx

AUTH_FILE = r"__AUTH_FILE__"
LINK = "https://onlyfans.com/api2/v2/users/me"
APP = "33d57ade8c02dbc5a333db99ff9ae26a"

auth = json.loads(pathlib.Path(AUTH_FILE).read_text(encoding="utf-8"))
try:
    rules = httpx.get("https://raw.githubusercontent.com/DATAHOARDERS/dynamic-rules/main/onlyfans.json",
                      timeout=30, follow_redirects=True).json()
    revision = str(rules.get("format") or "")[:5]
except Exception as e:
    print(f"No pude descargar reglas: {e}")
    raise SystemExit(2)

def firma(uid):
    t = str(round(time.time() * 1000))
    msg = "\n".join([str(rules["static_param"]), t, urlparse(LINK).path, str(uid)]).encode()
    sha = hashlib.sha1(msg, usedforsecurity=False).hexdigest()
    ck = sum(sha.encode("ascii")[i] for i in rules["checksum_indexes"]) + rules["checksum_constant"]
    return rules["format"].format(sha, abs(ck)), t

def pedir(etiqueta, sess, aid, sign, t, xbc):
    h = {"accept": "application/json, text/plain, */*", "app-token": APP, "x-bc": xbc,
         "referer": "https://onlyfans.com", "user-agent": auth["user_agent"],
         "sign": sign, "time": t}
    try:
        r = httpx.get(LINK, headers=h, cookies={"sess": sess, "auth_id": str(aid)},
                      timeout=40, follow_redirects=True)
        print(f"  {etiqueta:38} {r.status_code}  {r.text[:80]}")
    except Exception as e:
        print(f"  {etiqueta:38} EXC {type(e).__name__} {str(e)[:60]}")

sign, t = firma(auth["auth_id"])

print(f"auth.json: sess {len(auth.get('sess',''))} chars | auth_id {auth.get('auth_id')}")
print(f"reglas activas: revision {revision}\n")

print("1) MISMA firma, cambiando cookies")
pedir("tus cookies reales", auth["sess"], auth["auth_id"], sign, t, auth["x-bc"])
pedir("cookies inventadas", "sess_falsa_000", "111111", sign, t, auth["x-bc"])

print("\n2) MISMAS cookies reales, cambiando firma")
pedir(f"firma revision {revision} (reglas)", auth["sess"], auth["auth_id"], sign, t, auth["x-bc"])
pedir("firma revision 26974 (datawhores)", auth["sess"], auth["auth_id"],
      "26974:0000000000000000000000000000000000000000:0:669fb034", "1793309730832", auth["x-bc"])
pedir("firma revision 67378 (navegador)", auth["sess"], auth["auth_id"],
      "67378:16dd1504a66ef117a47074279031cdaf9a4df342:8bb:6ae36867", "1793309730832", auth["x-bc"])

print("\nLectura:")
print("  Si (1) da lo mismo con cookies buenas y falsas -> las cookies no causan el fallo.")
print("  Si (2) cambia al cambiar la firma             -> el fallo es la revision de firma.")
'@

$py = $py.Replace("__AUTH_FILE__", $AuthFile)
$tmp = Join-Path $env:TEMP ("ofs_diag_{0}.py" -f [guid]::NewGuid().ToString("N"))
Set-Content -Path $tmp -Value $py -Encoding UTF8
try {
    & $venvPy $tmp
    $code = $LASTEXITCODE
} finally {
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}
exit $code
