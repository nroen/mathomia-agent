# Modul: CPU Detektor
if command -v lshw &> /dev/null; then
    CPU_MODEL=$(lshw -json 2>/dev/null | jq -r '.. | select(.class? == "processor") | .product' | head -n1)
else
    CPU_MODEL=$(grep -m1 'model name' /proc/cpuinfo | sed 's/model name\s*:\s*//')
fi

[ -z "$CPU_MODEL" ] && CPU_MODEL="Ukjent Linux CPU"