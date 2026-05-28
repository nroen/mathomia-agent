# Modul: Grafikkort / GPU Detektor
GPU_JSON="[]"

if command -v lspci &> /dev/null; then
    # Hent alle linjer som inneholder VGA eller 3D controller
    GPU_LINES=$(lspci | grep -E -i "vga|3d|display" || true)
    
    if [ ! -z "$GPU_LINES" ]; then
        GPU_JSON="["
        FIRST_GPU=true
        
        while read -r line; do
            # Vask ut PCI-id i starten for å få et rent produktnavn
            GPU_NAME=$(echo "$line" | cut -d':' -f3- | xargs)
            
            # Identifiser produsent kjapt
            PRODUSENT="Ukjent"
            if echo "$GPU_NAME" | grep -q -i "nvidia"; then PRODUSENT="NVIDIA"; fi
            if echo "$GPU_NAME" | grep -q -i "amd"; then PRODUSENT="AMD"; fi
            if echo "$GPU_NAME" | grep -q -i "intel"; then PRODUSENT="Intel"; fi

            if [ "$FIRST_GPU" = false ]; then GPU_JSON+=","; fi
            GPU_JSON+="{\"type\":\"graphics\",\"produsent\":\"$PRODUSENT\",\"modell\":\"$GPU_NAME\"}"
            FIRST_GPU=false
        done <<< "$GPU_LINES"
        
        GPU_JSON+="]"
    fi
fi