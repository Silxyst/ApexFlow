@echo off
REM ApexFlow — remove a inicializacao automatica do painel.
del "%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\ApexFlowPanel.vbs" 2>nul
echo [OK] Inicializacao automatica removida.
pause
