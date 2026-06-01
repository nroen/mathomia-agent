#!/bin/bash

# =============================================================
# 🐧 Mathomia Linux Agent (All-in-one Production Version)
# =============================================================

WORKER_URL="https://mathomia-worker.nrcignis.workers.dev"
SERVER_NAME=$(hostname | xargs)

# Version info (Automated via GitHub Actions)
AGENT_VERSION="2026.05.30-be01434"
COMMIT_HASH="be01434"

echo "============================================="
echo " 🐧 Mathomia Linux Agent ($AGENT_VERSION)"
echo "============================================="

# --- 1. OS & Core Data Detection ---
echo "🧠 Fetching OS and Core details..."

# Fetch CPU info safely
CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//' | xargs)
[ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu | grep 'Model name' | sed 's/Model name:\s*//' | xargs)

# Detect OS details & map icons/types safely
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME=$NAME          # E.g. "Ubuntu" or "Proxmox Virtual Environment"
    OS_VERSION=$VERSION_ID # E.g. "24.04" or "8.1.4"
    
    # Smart check for Proxmox VE
    if [ "$ID" = "pve" ] || [ "$ID_LIKE" = "pve" ] || [[ "$NAME" == *"Proxmox"* ]]; then
        OS_TYPE="proxmox"
    else
        OS_TYPE="linux"
    fi
else
    OS_NAME="Unknown Linux"
    OS_VERSION="Unknown"
    OS_TYPE="linux"
fi # <--- FIKSET: Manglet i forrige skript!

OS_DETAIL="$OS_NAME $OS_VERSION"

# --- 2. RAM & Hardware Identification ---
echo "📟 Fetching RAM size..."
TOTAL_RAM_BYTES=$(free -b | awk '/Mem:/ {print $2}' | xargs)

echo "🆔 Fetching Hardware UUID & Motherboard..."
SYS_UUID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs)

if [ -z "$SYS_UUID" ] || [ "$SYS_UUID" = "Not Specified" ] || [[ "$SYS_UUID" =~ ^[0,-]*$ ]]; then
    if [[ "$SYS_UUID" =~ ^[0,-]*$ ]] && [ ! -z "$SYS_UUID" ]; then
        echo "ℹ️  System uses a valid null-prefixed UUID."
    else
        echo "⚠️  Motherboard lacks unique UUID. Using /etc/machine-id fallback..."
        SYS_UUID=$(cat /etc/machine-id 2>/dev/null | xargs)
    fi
fi

# Motherboard hardware profile details
MOBO_VENDOR=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | xargs)
MOBO_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null | xargs)
MOBO_SERIAL=$(cat /sys/class/dmi/id/board_serial 2>/dev/null | xargs)

# Fallbacks for hypervisors or generic whitebox builds
[ -z "$MOBO_VENDOR" ] && MOBO_VENDOR="Linux System"
[ -z "$MOBO_NAME" ] && MOBO_NAME="Generic Hardware"
[ -z "$MOBO_SERIAL" ] && MOBO_SERIAL="Unknown"
[ -z "$SYS_UUID" ] && SYS_UUID="fallback-$(echo "$SERVER_NAME" | md5sum | awk '{print $1}')"

# --- 3. Parsing Component Details (RAM Chips) ---
echo "📟 Parsing memory sticks details..."
MEMORY_JSON_ARRAY=""

in_device=false
size=""; locator=""; vendor=""; speed=""; type=""; serial=""; part=""

process_current_device() {
    if [ "$in_device" = true ] && [ ! -z "$size" ] && [ "$size" != "No Module Installed" ]; then
        [ -z "$vendor" ] || [ "$vendor" = "Unknown" ] && vendor="Generic"
        [ -z "$speed" ] && speed="Unknown"
        [ -z "$locator" ] && locator="Unknown Slot"
        [ -z "$type" ] && type="DDR"
        [[ "$serial" =~ "Unknown" || "$serial" =~ "0000" || -z "$serial" ]] && serial=""
        [[ "$part" =~ "Unknown" || -z "$part" ]] && part=""

        RAW_SIZE_NUM=$(echo "$size" | grep -oE '[0-9]+')
        SIZE_BYTES=0
        if [[ "$size" =~ "GB" ]]; then
            SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024 * 1024))
        elif [[ "$size" =~ "MB" ]]; then
            SIZE_BYTES=$((RAW_SIZE_NUM * 1024 * 1024))
        fi

        # FIKSET: Konvertert til ENGELSKE nøkler for å matche DB/Windows
        MEM_ITEM=$(jq -c -n \
          --arg loc "$locator" \
          --arg ven "$vendor" \
          --arg spd "$speed" \
          --arg size "$SIZE_BYTES" \
          --arg type "$type" \
          --arg sn "$serial" \
          --arg pn "$part" \
          '{
            model: ("RAM Stick (" + $loc + ")"),
            vendor: $ven,
            type: $type,
            speed: $spd,
            size_bytes: ($size | tonumber),
            serial_number: (if $sn == "" then null else $sn end),
            part_number: (if $pn == "" then null else $pn end)
          } | del(..|nulls)')

        if [ -z "$MEMORY_JSON_ARRAY" ]; then
            MEMORY_JSON_ARRAY="$MEM_ITEM"
        else
            MEMORY_JSON_ARRAY="$MEMORY_JSON_ARRAY,$MEM_ITEM"
        fi
    fi
}

# Line by line extraction from dmidecode
while IFS= read -r line; do
    if [[ "$line" =~ "Memory Device" ]]; then
        process_current_device
        in_device=true
        size=""; locator=""; vendor=""; speed=""; type=""; serial=""; part=""
        continue
    fi

    if [[ "$line" =~ Handle\ 0x ]]; then
        process_current_device
        in_device=false
    fi

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

process_current_device

# Virtualization fallback
if [ -z "$MEMORY_JSON_ARRAY" ]; then
    MEMORY_JSON_ARRAY=$(jq -c -n \
      --arg size "$TOTAL_RAM_BYTES" \
      '{model: "Virtual Memory Allocation", vendor: "Hypervisor", size_bytes: ($size | tonumber)}')
fi

# --- 4. Storage Disks Data ---
echo "💾 Fetching storage drives..."
DISKS_JSON_ARRAY=""
LSBLK_JSON=$(lsblk -d -J -o NAME,MODEL,SIZE,SERIAL,ROTA 2>/dev/null)

if [ ! -z "$LSBLK_JSON" ]; then
    while read -r disk_line; do
        [ -z "$disk_line" ] && continue
        
        if [ -z "$DISKS_JSON_ARRAY" ]; then
            DISKS_JSON_ARRAY="$disk_line"
        else
            DISKS_JSON_ARRAY="$DISKS_JSON_ARRAY,$disk_line"
        fi
    done < <(echo "$LSBLK_JSON" | jq -c '.blockdevices[] | select(.name | startswith("loop") | not) |
        ((.size | match("([0-9.]+)").string | tonumber)) as $raw_val |
        ((.size | match("([GKMTEP])").string // "B")) as $unit |
        (if $unit == "T" then $raw_val * 1024 * 1024 * 1024 * 1024
         elif $unit == "G" then $raw_val * 1024 * 1024 * 1024
         elif $unit == "M" then $raw_val * 1024 * 1024
         else $raw_val end) as $bytes |
        
        (if (.name | startswith("nvme")) then "NVMe"
         elif .rota == "1" or .rota == true or .rota == "true" then "HDD"
         else "SSD" end) as $dtype |
         
        {
          model: (if .model == null or .model == "" then "Generic Disk (/" + .name + ")" else .model end),
          vendor: (if .model != null then (.model | split(" ")[0]) else "Unknown" end),
          type: $dtype,
          size_bytes: $bytes,
          serial_number: (if .serial == null or .serial == "" or .serial == "Unknown" then null else .serial end)
        } | del(..|nulls)')
fi

# --- 5. GPU Details ---
echo "🏎️  Fetching GPU details..."
GRAPHICS_JSON_ARRAY=""

while read -r gpu_line; do
    [ -z "$gpu_line" ] && continue
    GPU_RAW=$(echo "$gpu_line" | sed -E 's/^[0-9a-fA-F|.: ]+ (VGA compatible controller|3D controller|Display controller): //I')
    GPU_VENDOR=$(echo "$GPU_RAW" | awk '{print $1}')
    
    GPU_JSON=$(jq -c -n --arg model "$GPU_RAW" --arg vendor "$GPU_VENDOR" '{model: $model, vendor: $vendor}')
        
    if [ -z "$GRAPHICS_JSON_ARRAY" ]; then
        GRAPHICS_JSON_ARRAY="$GPU_JSON"
    else
        GRAPHICS_JSON_ARRAY="$GRAPHICS_JSON_ARRAY,$GPU_JSON"
    fi
done < <(lspci 2>/dev/null | grep -E -i "vga|3d|display")

# --- 6. Pack Final Payload via jq ---
echo "📦 Compiling dynamic hardware payload JSON..."
PAYLOAD=$(jq -n \
  --arg sn "$SERVER_NAME" \
  --arg ver "$AGENT_VERSION" \
  --arg hash "$COMMIT_HASH" \
  --arg cpu "$CPU_MODEL" \
  --arg ram "$TOTAL_RAM_BYTES" \
  --arg uuid "$SYS_UUID" \
  --arg ot "$OS_TYPE" \
  --arg ov "$OS_DETAIL" \
  --arg mb_vendor "$MOBO_VENDOR" \
  --arg mb_name "$MOBO_NAME" \
  --arg mb_serial "$MOBO_SERIAL" \
  --argjson mem_array "[$MEMORY_JSON_ARRAY]" \
  --argjson disk_array "[$DISKS_JSON_ARRAY]" \
  --argjson gfx_array "[$GRAPHICS_JSON_ARRAY]" \
  '{
    server_name: $sn,
    agent_version: $ver,
    commit_hash: $hash,
    hardware_uuid: $uuid,
    cpu_model: $cpu,
    total_ram_bytes: ($ram | tonumber),
    os_type: $ot,
    os_version: $ov,
    hardware_json: {
      motherboard: {
        vendor: $mb_vendor,
        model: $mb_name,
        hardware_uuid: $uuid,
        serial_number: $mb_serial
      },
      processors: [{model: $cpu, vendor: ($cpu | split(" ")[0]), cores: null}],
      memory: $mem_array,
      disks: $disk_array,
      graphics: $gfx_array
    }
  }')

# --- 7. Ship Payload to Cloudflare Worker ---
echo "📡 Shipping metrics to Mathomia Cloud..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WORKER_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo "✅ Success! Node synchronized safely."
else
    echo "❌ Transmission failed (HTTP $HTTP_STATUS)"
    echo "Server Response: $BODY"
fi