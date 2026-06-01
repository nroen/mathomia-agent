# Modul: Hovedkort og System-UUID Detektor
BOARD_PROD=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | xargs || echo "Ukjent Produsent")
BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null | xargs || echo "Hovedkort")
SYS_UUID=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | xargs || echo "N/A")

OTHER_JSON=$(jq -n \
  --arg prod "$BOARD_PROD" \
  --arg mod "$BOARD_NAME" \
  --arg uuid "$SYS_UUID" \
  '{produsent: $prod, modell: $mod, hardware_uuid: $uuid}')
