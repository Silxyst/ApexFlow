@echo off
REM ApexFlow — abre o painel WEB com 1 duplo clique (liga o servidor + abre o navegador).
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py panel_server.py --open
) else (
  python panel_server.py --open
)
if %errorlevel%ne0 (
  echo.
  echo [ERRO] Python 3 nao encontrado. Instale em https://www.python.org/downloads/
  pause
)
