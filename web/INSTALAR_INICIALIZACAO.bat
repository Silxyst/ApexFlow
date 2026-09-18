@echo off
REM ApexFlow — liga o painel junto com o Windows (rode UMA vez).
REM Depois disso o botao "Abrir no Navegador" dentro do jogo sempre funciona.
set "APPDIR=%~dp0"
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "VBS=%STARTUP%\ApexFlowPanel.vbs"
where pythonw >nul 2>nul
if %errorlevel%==0 ( set "PY=pythonw.exe" ) else ( set "PY=python.exe" )
(
  echo Set sh = CreateObject^("Wscript.Shell"^)
  echo sh.Run "%PY% ""%APPDIR%panel_server.py""", 0, False
) > "%VBS%"
echo.
echo [OK] ApexFlow vai ligar junto com o Windows.
echo     Arquivo: %VBS%
echo     Para remover: rode web\DESINSTALAR_INICIALIZACAO.bat
echo.
pause
