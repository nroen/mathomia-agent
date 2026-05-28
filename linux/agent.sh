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

# Vi bruker dmidecode til å loope gjennom alle installerte minnebrikker
while read -r size locator vendor speed; do
    # Hvis feltet er tomt eller brikken er markert som tom/ukjent, hopper vi over
    if [ -z "$size" ] || [[ "$size" =~ "No" ]] || [[ "$size" =~ "Unknown" ]]; then
        continue
    fi
    
    # Konverter størrelse til bytes (dmidecode gir ofte f.eks. "16 GB" eller "16384 MB")
    RAW_SIZE_NUM=$(echo "$size" | grep -oE '[0-9]+')
    SIZE_BYTES=0
    if [[ "$size" =~ "GB" ]]; then
        SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024 * 1024))
    elif [[ "$size" =~ "MB" ]]; then
        SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024))
    fi

    # Rens opp lokasjon, produsent og hastighet
    [ -z "$vendor" ] || [ "$vendor" = "Unknown" ] && vendor="Generisk"
    [ -z "$speed" ] || [ "$speed" = "Unknown" ] && speed="Ukjent"
    
    # Bygg et lite JSON-objekt for denne brikken ved hjelp av jq
    MEM_ITEM=$(jq -n \
      --arg loc "$locator" \
      --arg ven "$vendor" \
      --arg spd "$speed" \
      --arg size "$SIZE_BYTES" \
      '{modell: ("RAM-brikke (" + $loc + ")"), produsent: $ven, hastighet: $spd, storrelse_bytes: ($size | tonumber)}')

    if [ -z "$MEMORY_JSON_ARRAY" ]; then
        MEMORY_JSON_ARRAY="$MEM_ITEM"
    else
        MEMORY_JSON_ARRAY="$MEMORY_JSON_ARRAY,$MEM_ITEM"
    fi
done < <(sudo dmidecode -t memory 2>/dev/null | awk '
    /Size:/ {size=$2" "$3}
    /Locator:/ {loc=$2}
    /Manufacturer:/ {vendor=$2; for(i=3;i<=NF;i++) vendor=vendor" "$i}
    /Speed:/ {speed=$2" "$3; print size"|"loc"|"vendor"|"speed}
' | grep -v "No Module Installed" | tr '|' ' ')

# Hvis maskinen er en VM eller dmidecode feilet helt, lager vi en virtuell brikke basert på total RAM
if [ -z "$MEMORY_JSON_ARRAY" ]; then
    MEMORY_JSON_ARRAY=$(jq -n \
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
