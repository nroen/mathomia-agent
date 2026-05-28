#!/bin/bash
# ====================================================
# 🌐 Mathomia Agent Installer for Linux
# ====================================================

GITHUB_RAW="https://raw.githubusercontent.com/nroen/mathomia-agent/main"

echo "===================================================="
echo " 🛠️  Installerer Mathomia Hardware Agent..."
echo "===================================================="

# 1. Sjekk om skriptet kjøres som root (nødvendig for å skrive til crontab og lese DMI/UUID)
if [ "$EUID" -ne 0 ]; then
  echo "❌ Feil: Dette installasjonsskriptet må kjøres som root (sudo bash)."
  exit 1
fi

# 2. Sjekk og installer jq hvis det mangler (hovedagenten trenger det)
if ! command -v jq &> /dev/null; then
    echo "📦 'jq' mangler. Prøver å installere automatisk..."
    if command -v apt-get &> /dev/null; then
        apt-get update && apt-get install -y jq
    elif command -v yum &> /dev/null; then
        yum install -y jq
    else
        echo "❌ Kunne ikke installere jq automatisk. Installer det manuelt og kjør igjen."
        exit 1
    fi
fi

# 3. Opprett den timelige cron-jobben
echo "⏰ Setter opp cron-jobb (Kjører hver time)..."

# Kommandoen som cron skal kjøre
CRON_CMD="0 * * * * curl -sSL $GITHUB_RAW/linux/agent.sh | bash"

# Sjekk om jobben allerede finnes i crontab fra før av for å unngå duplikater
if crontab -l 2>/dev/null | grep -Fq "$GITHUB_RAW/linux/agent.sh"; then
    echo "ℹ️  Cron-jobben er allerede konfigurert."
else
    # Hent eksisterende cron, legg til den nye linjen, og lagre tilbake
    (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo "✅ Cron-jobb ble lagt til i systemet."
fi

# 4. Trigger en første skanning umiddelbart så dataene sendes til Neon med en gang
echo "🚀 Kjører første maskinvareskanning umiddelbart..."
curl -sSL "$GITHUB_RAW/linux/agent.sh" | bash

echo "===================================================="
echo " 🎉 Installasjonen er fullført!"
echo " 🕵️‍♂️ Agenten sjekker seg inn på GitHub hver time."
echo "===================================================="