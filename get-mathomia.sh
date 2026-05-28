#!/bin/bash

# ====================================================
# 🛠️ Mathomia Hardware Agent Installer
# ====================================================

echo "===================================================="
echo " 🛠️  Installerer Mathomia Hardware Agent..."
echo "===================================================="

# Sjekk at skriptet kjøres som root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Vennligst kjør som root (sudo bash get-mathomia.sh)"
  exit 1
fi

# Installer jq og curl hvis det mangler
if ! command -v jq &> /dev/null || ! command -v curl &> /dev/null; then
    echo "📦 Installerer nødvendige pakker (curl, jq)..."
    apt-get update -y && apt-get install -y curl jq
fi

# Opprett mappe til agenten
INSTALL_DIR="/usr/local/bin/mathomia"
mkdir -p "$INSTALL_DIR"

echo "📥 Henter alt-i-ett-agenten fra GitHub..."
curl -sSL "https://raw.githubusercontent.com/nroen/mathomia-agent/main/linux/agent.sh" > "$INSTALL_DIR/agent.sh"
chmod +x "$INSTALL_DIR/agent.sh"

echo "⏰ Setter opp cron-jobb (Kjører hver time)..."
CRON_JOB="0 * * * * /usr/local/bin/mathomia/agent.sh > /var/log/mathomia-agent.log 2>&1"
(crontab -l 2>/dev/null | grep -F "$INSTALL_DIR/agent.sh") && echo "ℹ️  Cron-jobben er allerede konfigurert." || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

echo "🚀 Kjører første maskinvareskanning umiddelbart..."
bash "$INSTALL_DIR/agent.sh"

echo "===================================================="
echo " 🎉 Installasjonen er fullført!"
echo " 🕵️‍♂️ Agenten skanner maskinvaren og sender status hver time."
echo "===================================================="
