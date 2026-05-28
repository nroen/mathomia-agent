#!/bin/bash
# Mathomia Linux Main Agent v3.0 (Modulær)

WORKER_URL="https://mathomia-worker.nrcignis.workers.dev"
GITHUB_RAW="https://raw.githubusercontent.com/nroen/mathomia-agent/main/linux"
SERVER_NAME=$(hostname)

# Sentral feilrapportering hvis noe tryner underveis
rapporter_feil() {
  local linje=$1
  local kommando=$2
  curl -s -X POST "$WORKER_URL" \
    -H "Content-Type: application/json" \
    -d "{\"server_name\": \"$SERVER_NAME\", \"type\": \"error_report\", \"error_message\": \"Linux-agent feilet på linje $linje under kommando: $kommando\"}"
}

set -e
trap 'rapporter_feil $LINENO "$BASH_COMMAND"' ERR

echo "============================================="
echo " 🐧 Mathomia Linux Agent"
echo "============================================="

# 1. Last inn alle sub-skript dynamisk fra GitHub inn i minnet
echo "📥 Henter moduler fra GitHub..."
source <(curl -sSL "$GITHUB_RAW/detect_cpu.sh")
source <(curl -sSL "$GITHUB_RAW/detect_ram.sh")
source <(curl -sSL "$GITHUB_RAW/detect_storage.sh")
source <(curl -sSL "$GITHUB_RAW/detect_graphics.sh")
source <(curl -sSL "$GITHUB_RAW/detect_other.sh")

# 2. Siden vi har delt opp i moduler, limer vi sammen de ulike JSON-strengene
# Vi bruker jq til å bygge den endelige payloaden helt trygt
PAYLOAD=$(jq -n \
  --arg sn "$SERVER_NAME" \
  --arg cpu "$CPU_MODEL" \
  --argjson ram "$TOTAL_RAM_BYTES" \
  --argjson disks "$DISKS_JSON" \
  --argjson gpu "$GPU_JSON" \
  --argjson other "$OTHER_JSON" \
  '{
    server_name: $sn, 
    cpu_model: $cpu, 
    total_ram_bytes: ($ram | tonumber), 
    hardware_json: {
      motherboard: $other,
      processors: [$cpu],
      disks: $disks,
      graphics: $gpu
    }
  }')

# 3. Send til Cloudflare Workers
echo "📡 Sender komplett hardware-kartotek til Cloudflare..."
curl -s -X POST "$WORKER_URL" -H "Content-Type: application/json" -d "$PAYLOAD"
echo "✅ Skanning fullført for $SERVER_NAME!"
