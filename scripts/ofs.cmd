@echo off
REM ============================================================
REM  Lanzador de OF-Scraper desde el propio repo clonado.
REM  Usa el entorno aislado de pipx (que apunta al codigo de
REM  este repositorio en modo editable), asi que lo que se
REM  ejecuta son las fuentes de C:\Users\rcruz\Documents\GitHub\OF-Scraper
REM
REM  Uso:   scripts\ofs.cmd            (menu interactivo)
REM         scripts\ofs.cmd --help
REM         scripts\ofs.cmd --version
REM ============================================================

setlocal
set "OFS_VENV=%LOCALAPPDATA%\pipx\pipx\venvs\ofscraper\Scripts"

REM ffmpeg 7.1.1 delante en el PATH: OF-Scraper exige >=6 y <8 para descifrar DRM,
REM y el primer ffmpeg del sistema (DVDStyler 4.2.1) se rechaza. La config
REM (binary_options.ffmpeg) no se aplica de forma fiable, asi que forzamos PATH.
if exist "C:\ffmpeg71\bin\ffmpeg.exe" (
    set "PATH=C:\ffmpeg71\bin;%PATH%"
)
if not exist "%OFS_VENV%\python.exe" (
    echo [ERROR] No existe el entorno de OF-Scraper en:
    echo         %OFS_VENV%
    echo         Reinstalalo con:  pipx install --editable "%~dp0.."
    endlocal
    exit /b 1
)

REM -m ofscraper ejecuta el paquete importado desde el repo (editable)
"%OFS_VENV%\python.exe" -m ofscraper %*
endlocal
