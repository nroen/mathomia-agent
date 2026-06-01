




# --- Konfigurasjon ---
$AGENT_VERSION = "1.0.0"
$COMMIT_HASH   = "main"

# Siden agenten installeres fast her, bruker vi eksplisitt sti så SYSTEM-brukeren aldri går seg vill
$configFile = "C:\Program Files\MathomiaAgent\config.json"

if (-not (Test-Path $configFile)) {
    Write-Error "Feil: Fant ikke konfigurasjonsfilen på: $configFile"
    Exit 1
}

$config = Get-Content -Raw $configFile | ConvertFrom-Json
$ENDPOINT_URL = $config.endpoint_url

# --- 1. Grunndata ---
$computerName = $env:COMPUTERNAME
$uuid = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID

# Hent detaljert OS-info
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$osName = $osInfo.Caption # F.eks. "Microsoft Windows 11 Pro"
$osVersion = $osInfo.Version # F.eks. "10.0.22631"
$osBuild = $osInfo.BuildNumber

# Kombiner til en pen og detaljert streng
$osDetail = "$osName (Build $osBuild)"
$osType = "windows"  # Denne brukes til ikon-mapping i databasen/frontend

# --- 2. Maskinvare (for hardware_json) ---
$baseboard = Get-CimInstance -ClassName Win32_BaseBoard | Select-Object -First 1
$motherboard = @{
    vendor        = $baseboard.Manufacturer.Trim()
    model         = $baseboard.Product.Trim()
    hardware_uuid = $uuid
    serial_number = $baseboard.SerialNumber.Trim()
}

$cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
$cpuName = $cpuInfo.Name.Trim()
$processors = @(@{
    model  = $cpuName
    vendor = $cpuInfo.Manufacturer.Trim()
    cores  = $cpuInfo.NumberOfCores
})

# Memory (Brikke-detaljer og total_ram_bytes)
$ramBytes = 0
$memoryChips = Get-CimInstance -ClassName Win32_PhysicalMemory | ForEach-Object {
    $chipBytes = [int64]$_.Capacity
    $ramBytes += $chipBytes
    
    # Map minnetype til lesbar tekst
    $memType = "DDR4"
    if ($_.MemoryType -eq 26 -or $_.Speed -gt 4000) { $memType = "DDR5" }
    elseif ($_.MemoryType -eq 24) { $memType = "DDR3" }

    @{
        model         = $_.PartNumber.Trim()
        vendor        = $_.Manufacturer.Trim()
        type          = $memType
        speed         = "$($_.Speed) MHz"
        size          = $chipBytes  # <--- NÅ: Rå bytes som rent tall (Int64)
        serial_number = $_.SerialNumber.Trim()
        part_number   = $_.PartNumber.Trim()
    }
}

$disks = Get-CimInstance -ClassName Win32_DiskDrive | ForEach-Object {
    @{ device_id = $_.DeviceID; model = $_.Model.Trim(); size_bytes = $_.Size; vendor = $_.Manufacturer }
}

$graphics = Get-CimInstance -ClassName Win32_VideoController | ForEach-Object {
    @{ model = $_.Name.Trim(); vendor = $_.AdapterCompatibility.Trim() }
}

$hardwareJson = @{
    motherboard = $motherboard; processors = $processors; memory = $memoryChips; disks = $disks; graphics = $graphics; os_detail = $osName
}

# --- 3. Payload (INGEN TIMESTAMP) ---

$payload = [ordered]@{
    agent_version   = $AGENT_VERSION
    commit_hash     = $COMMIT_HASH
    server_name     = $computerName
    hardware_uuid   = $uuid
    cpu_model       = $cpuName
    total_ram_bytes = $ramBytes
    os_type         = $osType        # <-- NY
    os_version      = $osDetail      # <-- NY (erstatter os_detail i hardware_json hvis du vil ha det på toppnivå)
    hardware_json   = $hardwareJson
} | ConvertTo-Json -Depth 5 -Compress



# --- 4. Send ---
$headers = @{ "Content-Type" = "application/json" }
try {
    # NÅ KORRIGERT: -SkipHttpErrorCheck er fjernet, og feil håndteres i catch-blokken
    $response = Invoke-RestMethod -Uri $ENDPOINT_URL -Method Post -Body $payload -Headers $headers -TimeoutSec 15
    if ($response.error) { Write-Error "Serverfeil: $($response.error)"; Exit 1 }
    Write-Host "Suksess! Data sendt for $computerName." -ForegroundColor Green
} catch {
    Write-Error "Nettverksfeil: $_"
    Exit 1
}