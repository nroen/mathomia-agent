# ====================================================
#        Mathomia Agent - Windows Installer
# ====================================================

$INSTALL_DIR = "C:\Program Files\MathomiaAgent"
$CONFIG_URL  = "https://mathomia-worker.nrcignis.workers.dev"

# 1. Sjekk Administrator-rettigheter
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[FEIL] Du MÅ kjøre dette skriptet som Administrator!"
    Exit 1
}

# 2. Opprett installasjonsmappen
if (-not (Test-Path $INSTALL_DIR)) {
    Write-Host "Oppretter mappe: $INSTALL_DIR" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $INSTALL_DIR -Force | Out-Null
}

# 3. Generer config.json
Write-Host "[1/3] Genererer config.json..." -ForegroundColor Cyan
$config = @{ endpoint_url = $CONFIG_URL } | ConvertTo-Json
Set-Content -Path (Join-Path $INSTALL_DIR "config.json") -Value $config -Force

# 4. Finn og kopier agent.ps1 relativt fra repoet (eller fallback til GitHub)
Write-Host "[2/3] Kopierer agent.ps1 til programfiler..." -ForegroundColor Cyan

$localAgent = $null

# Sjekk om skriptet faktisk kjører fra en lokal fil (ikke via iex)
if ($MyInvocation.MyCommand.Path) {
    $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $localAgent = Join-Path $scriptPath "windows\agent.ps1"
    }
}

# Hvis vi fant en lokal fil, kopier den. Hvis ikke, hent fra GitHub.
if ($localAgent -and (Test-Path $localAgent)) {
    Copy-Item -Path $localAgent -Destination (Join-Path $INSTALL_DIR "agent.ps1") -Force
} else {
    Write-Host "Kjører online installasjon, henter agent.ps1 fra GitHub..." -ForegroundColor Yellow
    
    # ERSTATT MED DITT FAKTISKE NAVN PÅ GITHUB:
    $githubAgentUrl = "https://raw.githubusercontent.com/DITT_GITHUB_BRUKERNAVN/mathomia-agent/main/windows/agent.ps1"
    Invoke-WebRequest -Uri $githubAgentUrl -OutFile (Join-Path $INSTALL_DIR "agent.ps1") -UseBasicParsing
}

# 5. Opprett Windows Scheduled Task
Write-Host "[3/3] Oppretter planlagt oppgave..." -ForegroundColor Cyan
& schtasks.exe /delete /tn "MathomiaAgent" /f 2>$null

$taskArgs = @("/create", "/tn", "MathomiaAgent", "/tr", "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File 'C:\Program Files\MathomiaAgent\agent.ps1'", "/sc", "hourly", "/mo", "1", "/ru", "SYSTEM", "/f")
& schtasks.exe $taskArgs

if ($LASTEXITCODE -eq 0) {
    & schtasks.exe /run /tn "MathomiaAgent"
    Write-Host "====================================================" -ForegroundColor Green
    Write-Host "[SUKSESS] Mathomia Agent er installert og kjører!" -ForegroundColor Green
    Write-Host "====================================================" -ForegroundColor Green
} else {
    Write-Error "Kunne ikke opprette Scheduled Task."
}