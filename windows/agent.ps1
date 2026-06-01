# --- Konfigurasjon ---
$AGENT_VERSION = "1.0.0"
$COMMIT_HASH   = "main"

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$configFile = Join-Path $scriptPath "config.json"

if (-not (Test-Path $configFile)) {
    Write-Error "Feil: Fant ikke konfigurasjonsfilen på: $configFile"
    Exit 1
}

$config = Get-Content -Raw $configFile | ConvertFrom-Json
$ENDPOINT_URL = $config.endpoint_url

# --- 1. Grunndata ---
$computerName = $env:COMPUTERNAME
$uuid = (Get-CimInstance -ClassName Win32_ComputerSystemProduct).UUID
$osName = (Get-CimInstance -ClassName Win32_OperatingSystem).Caption

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
    hardware_json   = $hardwareJson
} | ConvertTo-Json -Depth 5 -Compress

# --- 4. Send ---
$headers = @{ "Content-Type" = "application/json" }
try {
    $response = Invoke-RestMethod -Uri $ENDPOINT_URL -Method Post -Body $payload -Headers $headers -TimeoutSec 15 -SkipHttpErrorCheck
    if ($response.error) { Write-Error "Serverfeil: $($response.error)"; Exit 1 }
    Write-Host "Suksess! Data sendt for $computerName." -ForegroundColor Green
} catch {
    Write-Error "Nettverksfeil: $_"
    Exit 1
}