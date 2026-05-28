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

# Midlertidige variabler for å holde på dataene til én brikke mens vi leser
in_device=false
size=""
locator=""
vendor=""
speed=""
type=""
serial=""
part=""

process_current_device() {
    if [ "$in_device" = true ] && [ ! -z "$size" ] && [ "$size" != "No Module Installed" ]; then
        # Fallbacks hvis felter mangler eller er "Unknown"
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

        # Bygg kompakt JSON
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
    fi
}

# Les linje for linje direkte fra dmidecode uten awk-avhengigheter
while IFS= read -r line; do
    # Hvis vi treffer en ny enhet, prosesser den forrige og nullstill
    if [[ "$line" =~ "Memory Device" ]]; then
        process_current_device
        in_device=true
        size=""; locator=""; vendor=""; speed=""; type=""; serial=""; part=""
        continue
    fi

    # Hvis vi treffer en helt ny tabelltype som ikke er RAM, avslutt nåværende enhet
    if [[ "$line" =~ Handle\ 0x ]]; then
        process_current_device
        in_device=false
    fi

    # Hvis vi er inni en gyldig minne-enhet, plukk opp verdiene
    if [ "$in_device" = true ]; then
        [[ "$line" =~ Size: ]] && size=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ Locator: && ! "$line" =~ "Bank" ]] && locator=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ Manufacturer: ]] && vendor=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ Speed: && ("$line" =~ "MT/s" || "$line" =~ "MHz") ]] && speed=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ Type: && ! "$line" =~ "Error" ]] && type=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ "Serial Number:" ]] && serial=$(echo "$line" | cut -d: -f2 | xargs)
        [[ "$line" =~ "Part Number:" ]] && part=$(echo "$line" | cut -d: -f2 | xargs)
    fi
done < <(sudo dmidecode -t memory 2>/dev/null)

# Prosesser den aller siste brikken i filen
process_current_device

# Hvis maskinen er en VM eller ingen fysiske brikker ble funnet
if [ -z "$MEMORY_JSON_ARRAY" ]; then
    MEMORY_JSON_ARRAY=$(jq -c -n \
      --arg size "$TOTAL_RAM_BYTES" \
      '{modell: "Virtuell minneallokering", produsent: "Hypervisor", storrelse_bytes: ($size | tonumber)}')
fi













# 3.5 Hent detaljer om fysiske lagringsdisker
echo "💾 Henter detaljer om lagringsdisker..."
DISKS_JSON_ARRAY=""

# Vi henter ut kun fysiske disker (type "disk") i JSON-format fra lsblk
LSBLK_JSON=$(lsblk -d -J -o NAME,MODEL,SIZE,SERIAL,ROTA 2>/dev/null)

if [ ! -z "$LSBLK_JSON" ]; then
    # Vi bruker jq til å filtrere, vaske og strukturere diskene på én kompakt linje per disk
    while read -r disk_line; do
        [ -z "$disk_line" ] && continue
        
        if [ -z "$DISKS_JSON_ARRAY" ]; then
            DISKS_JSON_ARRAY="$disk_line"
        else
            DISKS_JSON_ARRAY="$DISKS_JSON_ARRAY,$disk_line"
        fi
    # jq-magi: Regner ut bytes, setter disktype basert på rotasjon (ROTA) eller NVMe-navn, og fjerner tomme serienummer
    done < <(echo "$LSBLK_JSON" | jq -c '.blockdevices[] | select(.type != "loop") | 
        # Beregn størrelse i bytes basert på lsblk-størrelsen (f.eks. 500G eller 1T)
        (.size | sub("(?<_1>[0-9.]+)(?<_2>[GKMTEP])"; "\(.[] | tostring)") | split(" ") | .[0] | tonumber) as $raw_val |
        (.size | grep -oE "[GKMTEP]") as $unit |
        (if $unit == "G" then $raw_val * 1024 * 1024 * 1024
         elif $unit == "T" then $raw_val * 1024 * 1024 * 1024 * 1024
         elif $unit == "M" then $raw_val * 1024 * 1024
         else $raw_val end) as $bytes |
        
        # Finn disktype (NVMe, SSD eller HDD)
        (if (.name | startswith("nvme")) then "NVMe"
         elif .rota == "1" or .rota == true then "HDD"
         else "SSD" end) as $dtype |
         
        {
          modell: (if .model == null or .model == "" then "Generisk Disk (/" + .name + ")" else .model | xargs end),
          produsent: (if .model != null then (.model | split(" ")[0]) else "Ukjent" end),
          type: $dtype,
          storrelse_bytes: $bytes,
          serienummer: (if .serial == null or .serial == "" or .serial == "Unknown" then null else .serial | xargs end)
        } | del(..|nulls)')
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
