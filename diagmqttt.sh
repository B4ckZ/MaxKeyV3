#!/bin/bash

# ==============================================================================
# VÉRIFICATION RAPIDE DU WIDGET MQTTLOGS509511
# ==============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}  DIAGNOSTIC WIDGET MQTTLOGS509511${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

# 1. Vérifier si testpersist est installé
echo -e "${BLUE}▶ VÉRIFICATION DU SERVICE TESTPERSIST${NC}"
echo "========================================"

if systemctl list-units --all | grep -q "maxlink-widget-testpersist"; then
    if systemctl is-active --quiet maxlink-widget-testpersist; then
        echo -e "◦ Service testpersist: ${GREEN}[ACTIF]${NC}"
    else
        echo -e "◦ Service testpersist: ${RED}[INACTIF]${NC}"
        echo ""
        echo -e "${YELLOW}Le widget mqttlogs509511 a besoin que testpersist soit actif${NC}"
        echo -e "${YELLOW}pour recevoir les messages confirmés.${NC}"
        echo ""
        echo "Solution: sudo systemctl start maxlink-widget-testpersist"
    fi
else
    echo -e "◦ Service testpersist: ${RED}[NON INSTALLÉ]${NC}"
    echo ""
    echo -e "${RED}PROBLÈME IDENTIFIÉ:${NC}"
    echo "Le widget mqttlogs509511 a été modifié pour écouter les topics"
    echo "'/confirmed' qui sont publiés par le service testpersist."
    echo ""
    echo "Sans testpersist, le widget ne recevra aucun message."
fi

echo ""

# 2. Vérifier les topics MQTT
echo -e "${BLUE}▶ TOPICS MQTT ÉCOUTÉS${NC}"
echo "========================================"

echo "Le widget mqttlogs509511 écoute maintenant :"
echo "• SOUFFLAGE/509/ESP32/result/confirmed"
echo "• SOUFFLAGE/511/ESP32/result/confirmed"
echo ""

# 3. Test des topics
echo -e "${BLUE}▶ TEST D'ÉCOUTE (5 secondes)${NC}"
echo "========================================"

TEMP_FILE=$(mktemp)

# Écouter les topics confirmés
timeout 5 mosquitto_sub -h localhost -u mosquitto -P mqtt \
    -t "SOUFFLAGE/+/ESP32/result/confirmed" -v 2>/dev/null > "$TEMP_FILE" &

echo -n "Écoute en cours"
for i in {1..5}; do
    echo -n "."
    sleep 1
done
echo ""

if [ -s "$TEMP_FILE" ]; then
    echo -e "${GREEN}Messages confirmés reçus :${NC}"
    cat "$TEMP_FILE"
else
    echo -e "${YELLOW}Aucun message confirmé reçu${NC}"
fi

rm -f "$TEMP_FILE"

echo ""

# 4. Solutions
echo -e "${BLUE}▶ SOLUTIONS${NC}"
echo "========================================"

if ! systemctl list-units --all | grep -q "maxlink-widget-testpersist"; then
    echo "1. Installer le widget testpersist pour activer la persistance :"
    echo "   - Copier les fichiers testpersist sur la clé USB"
    echo "   - Lancer l'installation depuis MaxKey"
    echo ""
    echo "2. OU revenir à l'ancienne version du widget mqttlogs509511 :"
    echo "   - Qui écoute directement '/result' sans confirmation"
    echo ""
    echo "3. Pour tester temporairement, envoyer un message confirmé :"
    echo "   mosquitto_pub -h localhost -u mosquitto -P mqtt \\"
    echo "     -t 'SOUFFLAGE/509/ESP32/result/confirmed' \\"
    echo "     -m '{\"timestamp\":\"27-01-2025T15:00:00\",\"team\":\"A\",\"barcode\":\"123456789\",\"result\":\"OK\"}'"
else
    echo "• Vérifier que le service testpersist est actif"
    echo "• Envoyer un message de test sur '/result' pour déclencher la persistance"
    echo "• Vérifier les logs : journalctl -u maxlink-widget-testpersist -f"
fi

echo ""