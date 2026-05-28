#!/bin/bash

# =============================================
# 🐧 Mathomia Linux Agent (Alt-i-ett-versjon)
# =============================================

WORKER_URL="https://mathomia-worker.nrcignis.workers.dev"
SERVER_NAME=$(hostname | xargs)

echo "============================================="
echo " 🐧 Mathomia Linux Agent "
echo "============================================="

# 1. Hent CPU-info
echo "🧠 Henter CPU-informasjon..."
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu | grep 'Model name' | sed 's/Model name:\s*//' | xargs)

# 2. Hent RAM-info (i bytes)
echo "📟 Henter RAM-størrelse..."
TOTAL_RAM_BYTES=$(free -b | awk '/Mem:/ {print $2}' | xargs)

# 3. Hent unik Hardware UUID og Hovedkort-info
echo "🆔 Henter maskinvare- og hovedkort-info..."
SYS_UUID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)

if [ -z "$SYS_UUID" ] || [ "$SYS_UUID" = "Not Specified" ] || [[ "$SYS_UUID" =~ ^[0,-]*$ ]]; then
    if [[ "$SYS_UUID" =~ ^[0,-]*$ ]] && [ ! -z "$SYS_UUID" ]; then
        echo "ℹ️  Maskinen bruker en gyldig null-prefixet UUID."
    else
        echo "⚠️  Hovedkort mangler UUID. Bruker /etc/machine-id som fallback..."
        SYS_UUID=$(cat /etc/machine-id 2>/dev/null | xargs)
    fi
fi

# Hent detaljer om det fysiske hovedkortet
MOBO_VENDOR=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | xargs)
MOBO_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null | xargs)
MOBO_SERIAL=$(cat /sys/class/dmi/id/board_serial 2>/dev/null | xargs)

# Fallbacks hvis variablene er tomme
[ -z "$MOBO_VENDOR" ] && MOBO_VENDOR="Linux System"
[ -z "$MOBO_NAME" ] && MOBO_NAME="Generic Hardware"
[ -z "$MOBO_SERIAL" ] && MOBO_SERIAL="Ukjent"

[ -z "$SYS_UUID" ] && SYS_UUID="fallback-$(echo "$SERVER_NAME" | md5sum | awk '{print $1}')"













# Hent detaljer om minnebrikker (RAM)
echo "📟 Henter detaljer om minnebrikker..."
MEMORY_JSON_ARRAY=""

# Vi bruker RS="Handle " som vi VET at ATLAS sin awk spytter ut perfekt!
while read -r block; do
    # Hvis blokken ikke inneholder en fysisk brikke med størrelse, hopp over
    if [[ ! "$block" =~ "Size:" ]] || [[ "$block" =~ "No Module Installed" ]]; then
        continue
    fi

    # Hent ut verdiene ved å søke gjennom hele tekstblokken
    size=$(echo "$block" | grep "Size:" | head -n1 | cut -d: -f2 | xargs)
    locator=$(echo "$block" | grep "Locator:" | grep -v "Bank" | head -n1 | cut -d: -f2 | xargs)
    vendor=$(echo "$block" | grep "Manufacturer:" | head -n1 | cut -d: -f2 | xargs)
    speed=$(echo "$block" | grep "Speed:" | grep -E "MT/s|MHz" | head -n1 | cut -d: -f2 | xargs)
    type=$(echo "$block" | grep "Type:" | grep -v "Error" | head -n1 | cut -d: -f2 | xargs)
    serial=$(echo "$block" | grep "Serial Number:" | head -n1 | cut -d: -f2 | xargs)
    part=$(echo "$block" | grep "Part Number:" | head -n1 | cut -d: -f2 | xargs)

    [ -z "$size" ] && continue

    # Fallbacks hvis felter mangler eller inneholder kjedelige BIOS-standarder
    [ -z "$vendor" ] || [ "$vendor" = "Unknown" ] && vendor="Generisk"
    [ -z "$speed" ] && speed="Ukjent"
    [ -z "$locator" ] && locator="Ukjent spor"
    [ -z "$type" ] && type="DDR"
    [[ "$serial" =~ "Unknown" || "$serial" =~ "0000" || -z "$serial" ]] && serial=""
    [[ "$part" =~ "Unknown" || -z "$part" ]] && part=""

    # Konverter størrelse til bytes
    RAW_SIZE_NUM=$(echo "$size" | grep -oE '[0-9]+')
    SIZE_BYTES=0
    if [[ "$size" =~ "GB" ]]; then
        SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024 * 1024))
    elif [[ "$size" =~ "MB" ]]; then
        SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024))
    fi

    # Pakk alt til en kompakt, herlig JSON-linje
    MEM_ITEM=$(jq -c -n \
      --arg loc "$locator" \
      --arg ven "$vendor" \
      --arg spd "$speed" \
      --arg size "$SIZE_BYTES" \
      --arg type "$type" \
      --arg sn "$serial" \
      --arg pn "$part" \
      '{
        modell: ("RAM-brikke (" + $loc + ")"),
        produsent: $ven,
        type: $type,
        hastighet: $spd,
        storrelse_bytes: ($size | tonumber),
        serienummer: (if $sn == "" then null else $sn end),
        delenummer: (if $pn == "" then null else $pn end)
      } | del(..|nulls)')

    if [ -z "$MEMORY_JSON_ARRAY" ]; then
        MEMORY_JSON_ARRAY="$MEM_ITEM"
    else
        MEMORY_JSON_ARRAY="$MEMORY_JSON_ARRAY,$MEM_ITEM"
    fi

done < <(sudo dmidecode -t memory 2>/dev/null | awk 'BEGIN {RS="Handle "} {print $0}')

# Hvis maskinen er en VM eller dmidecode feilet helt
if [ -z "$MEMORY_JSON_ARRAY" ]; then
    MEMORY_JSON_ARRAY=$(jq -c -n \
      --arg size "$TOTAL_RAM_BYTES" \
      '{modell: "Virtuell minneallokering", produsent: "Hypervisor", storrelse_bytes: ($size | tonumber)}')
fi
















# 4. Pakk alt sammen i en 100% trygg JSON-struktur med jq
echo "📦 Pakker data til JSON..."
PAYLOAD=$(jq -n \
  --arg sn "$SERVER_NAME" \
  --arg cpu "$CPU_MODEL" \
  --arg ram "$TOTAL_RAM_BYTES" \
  --arg uuid "$SYS_UUID" \
  --arg mb_vendor "$MOBO_VENDOR" \
  --arg mb_name "$MOBO_NAME" \
  --arg mb_serial "$MOBO_SERIAL" \
  --argjson mem_array "[$MEMORY_JSON_ARRAY]" \
  '{
    server_name: $sn,
    cpu_model: $cpu,
    total_ram_bytes: ($ram | tonumber),
    hardware_uuid: $uuid,
    hardware_json: {
      motherboard: {
        produsent: $mb_vendor,
        modell: $mb_name,
        hardware_uuid: $uuid,
        serienummer: $mb_serial
      },
      processors: [$cpu],
      memory: $mem_array,
      disks: [],
      graphics: []
    }
  }')
  
  
# 5. Send herligheten til Cloudflare Workers
echo "📡 Sender maskinvarestatus til Mathomia Cloud..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WORKER_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Suksess! Data lagret i Neon-databasen."
else
    echo "❌ Feil under innsending! (HTTP $HTTP_STATUS)"
    echo "Svar fra server: $BODY"
fi
