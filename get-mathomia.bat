@echo off
SETLOCAL EnableExtensions EnableDelayedExpansion
cls
echo ====================================================
echo        Mathomia Agent - Windows Installer
echo ====================================================
echo.

:: 1. Definer installasjonsmål og felles API-endpoint
set "INSTALL_DIR=C:\Program Files\MathomiaAgent"
set "CONFIG_URL=https://mathomia-worker.nrcignis.workers.dev"

:: Sjekk om skriptet kjøres med Administrator-rettigheter
net session >nul 2>&1
if %errorLevel% == 0 (
    echo [OK] Kjorer som Administrator.
) else (
    echo [FEIL] Du MA kjore dette skriptet som Administrator!
    echo Hoyreklikk pa get-mathomia.bat og velg "Kjor som administrator".
    pause
    exit /b 1
)

:: 2. Opprett installasjonsmappen hvis den ikke finnes
if not exist "%INSTALL_DIR%" (
    echo Oppretter mappe: %INSTALL_DIR%
    mkdir "%INSTALL_DIR%"
)

:: 3. Generer config.json automatisk med riktig URL
echo [1/3] Genererer config.json...
(
echo {
echo     "endpoint_url": "%CONFIG_URL%"
echo }
) > "%INSTALL_DIR%\config.json"

:: 4. Kopier agent.ps1 fra \windows-undermappen
echo [2/3] Kopierer agent.ps1 til programfiler...
if exist "%~dp0windows\agent.ps1" (
    copy /Y "%~dp0windows\agent.ps1" "%INSTALL_DIR%\agent.ps1" >nul
) else (
    echo [FEIL] Fant ikke agent.ps1 i mappen: %~dp0windows\
    echo Sjekk at du har trukket ned hele repo-strukturen intakt.
    pause
    exit /b 1
)

:: 5. Opprett en Windows Scheduled Task (Oppgaveplanlegger)
echo [3/3] Oppretter planlagt oppgave i Windows...

:: Slett gammel oppgave hvis den eksisterer fra tidligere testing
schtasks /delete /tn "MathomiaAgent" /f >nul 2>&1

:: Opprett ny oppgave som kjører skjult under SYSTEM-brukeren hver time
schtasks /create /tn "MathomiaAgent" /tr "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File \"'%INSTALL_DIR%\agent.ps1'\"" /sc hourly /mo 1 /ru "SYSTEM" /f

if %errorLevel% == 0 (
    echo.
    echo ====================================================
    echo [SUKSESS] Mathomia Agent er ferdig installert!
    echo Skriptet vil na kjore automatisk hver time under SYSTEM.
    echo ====================================================
    echo.
    echo Kjorer forste skanning med en gang for og verifisere...
    schtasks /run /tn "MathomiaAgent"
) else (
    echo [FEIL] Kunne ikke opprette Scheduled Task.
)

pause