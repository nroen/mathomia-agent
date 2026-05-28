# Modul: RAM Detektor
if command -v lshw &> /dev/null; then
    TOTAL_RAM_BYTES=$(lshw -json 2>/dev/null | jq -r '[.. | select(.id? == "memory" and .size?) | .size] | add')
fi

# Fallback til free hvis lshw feiler eller mangler
if [ -z "$TOTAL_RAM_BYTES" ] || [ "$TOTAL_RAM_BYTES" = "null" ] || [ "$TOTAL_RAM_BYTES" -eq 0 ]; then
    TOTAL_RAM_BYTES=$(free -b | awk '/Mem:/ {print $2}')
fi

[ -z "$TOTAL_RAM_BYTES" ] && TOTAL_RAM_BYTES=0