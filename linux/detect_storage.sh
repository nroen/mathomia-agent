# Modul: Lagring / Disk Detektor
DISKS_JSON="[]"

# Sjekk om sysfs er tilgjengelig for passive blokkenheter
if [ -d /sys/block ]; then
    DISKS_JSON="["
    FIRST_DISK=true
    
    for disk in $(ls /sys/block/ | grep -E '^sd|^nvme'); do
        # Hopp over partisjonsnumre (f.eks. sda1, nvme0n1p1)
        if [[ "$disk" =~ [0-9]$ && "$disk" != nvme* ]]; then continue; fi
        
        # Hent størrelse i bytes (sektorer * 512)
        if [ -f "/sys/block/$disk/size" ]; then
            SECTORS=$(cat /sys/block/$disk/size)
            SIZE_BYTES=$((SECTORS * 512))
        else
            SIZE_BYTES=0
        fi

        # Hent modell og serienummer passivt fra enhetsstrukturen
        MODELL=$(cat /sys/block/$disk/device/model 2>/dev/null | xargs || echo "Standard Disk ($disk)")
        SERIAL=$(cat /sys/block/$disk/device/serial 2>/dev/null | xargs || echo "Ukjent S/N")
        
        # Sjekk grensesnitttype
        INTERFACE="SATA/SAS"
        if [[ "$disk" == nvme* ]]; then INTERFACE="NVMe (PCIe)"; fi

        if [ "$FIRST_DISK" = false ]; then DISKS_JSON+=","; fi
        DISKS_JSON+="{\"type\":\"disk\",\"modell\":\"$MODELL\",\"storrelse_bytes\":$SIZE_BYTES,\"serienummer\":\"$SERIAL\",\"disk_grensesnitt\":\"$INTERFACE\"}"
        FIRST_DISK=false
    done
    DISKS_JSON+="]"
fi