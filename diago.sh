#!/bin/bash

# ===============================================================================
# TRAÇAGE DU MAUVAIS TIMESTAMP
# Identifier d'où vient le timestamp 21
# ===============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}TRAÇAGE DU TIMESTAMP ERRONÉ${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# ===============================================================================
# 1. CAPTURER TOUS LES MESSAGES SUR LES TOPICS TIME
# ===============================================================================

echo -e "${BLUE}▶ CAPTURE COMPLÈTE DES TOPICS TIME (15 secondes)${NC}"
echo "========================================================================"

echo "Topics surveillés :"
echo "  - rpi/system/time"
echo "  - system/time/+"
echo "  - rpi/system/+"
echo ""

# Fichier temporaire
TMPFILE=$(mktemp)

# Capturer TOUS les topics système
timeout 15 mosquitto_sub \
    -h localhost \
    -u mosquitto \
    -P mqtt \
    -t "rpi/system/+" \
    -t "system/time/+" \
    -t "rpi/system/time" \
    -v 2>/dev/null > "$TMPFILE" &

MQTT_PID=$!

# Progress
echo -n "Capture en cours: "
for i in {1..15}; do
    echo -n "."
    sleep 1
done
echo " Terminé"

wait $MQTT_PID 2>/dev/null

# Analyser les résultats
echo ""
echo "◦ Messages capturés :"

if [ -s "$TMPFILE" ]; then
    while IFS= read -r line; do
        # Extraire topic et payload
        TOPIC=$(echo "$line" | cut -d' ' -f1)
        PAYLOAD=$(echo "$line" | cut -d' ' -f2-)
        
        echo ""
        echo -e "  ${YELLOW}Topic:${NC} $TOPIC"
        
        # Vérifier si c'est du JSON
        if echo "$PAYLOAD" | python3 -m json.tool >/dev/null 2>&1; then
            # Analyser le timestamp
            TS=$(echo "$PAYLOAD" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    ts = data.get('timestamp', 'N/A')
    if isinstance(ts, (int, float)):
        print(f'Timestamp: {ts}')
        if ts < 1000:  # Timestamp suspect
            print('⚠ TIMESTAMP SUSPECT!')
    else:
        print(f'Timestamp non numérique: {ts}')
except:
    pass
" 2>/dev/null)
            
            echo "    $TS"
            
            # Afficher le payload complet si timestamp suspect
            if echo "$TS" | grep -q "SUSPECT"; then
                echo -e "    ${RED}Payload complet:${NC}"
                echo "$PAYLOAD" | python3 -m json.tool | head -10 | sed 's/^/      /'
            fi
        else
            # Pas du JSON, afficher tel quel
            echo "    Payload: $PAYLOAD" | cut -c1-80
        fi
    done < "$TMPFILE"
else
    echo -e "  ${RED}Aucun message capturé${NC}"
fi

rm -f "$TMPFILE"

echo ""

# ===============================================================================
# 2. VÉRIFIER TOUS LES SERVICES WIDGET
# ===============================================================================

echo -e "${BLUE}▶ ÉTAT DES SERVICES WIDGETS${NC}"
echo "========================================================================"

# Liste des services à vérifier
SERVICES=(
    "maxlink-widget-timesync"
    "maxlink-widget-wifistats"
    "maxlink-widget-uptime"
    "maxlink-widget-servermonitoring"
    "maxlink-widget-mqttstats"
)

for SERVICE in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$SERVICE"; then
        echo -e "  ${GREEN}✓${NC} $SERVICE : Actif"
        
        # Vérifier si ce service publie sur un topic time
        if [[ "$SERVICE" == *"uptime"* ]] || [[ "$SERVICE" == *"servermonitoring"* ]]; then
            echo "    ⚠ Ce service pourrait publier des données temps"
        fi
    else
        echo -e "  ${YELLOW}○${NC} $SERVICE : Inactif"
    fi
done

echo ""

# ===============================================================================
# 3. VÉRIFIER LE WIDGET UPTIME
# ===============================================================================

echo -e "${BLUE}▶ ANALYSE DU WIDGET UPTIME${NC}"
echo "========================================================================"

# Le widget uptime pourrait publier un mauvais timestamp
echo "◦ Vérification du topic rpi/system/uptime :"

UPTIME_MSG=$(timeout 5 mosquitto_sub \
    -h localhost -u mosquitto -P mqtt \
    -t "rpi/system/uptime" \
    -C 1 2>/dev/null)

if [ -n "$UPTIME_MSG" ]; then
    echo "  Message reçu : $UPTIME_MSG"
    
    # Vérifier si c'est un nombre simple
    if [[ "$UPTIME_MSG" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "  ${YELLOW}⚠ Uptime publié comme nombre simple${NC}"
        echo "    Valeur: $UPTIME_MSG secondes"
        
        # Si c'est environ 21, c'est probablement notre coupable
        if (( $(echo "$UPTIME_MSG < 100" | bc -l) )); then
            echo -e "  ${RED}✗ PROBLÈME IDENTIFIÉ !${NC}"
            echo "    Le widget uptime publie probablement un timestamp erroné"
        fi
    fi
else
    echo "  Aucun message reçu sur ce topic"
fi

echo ""

# ===============================================================================
# 4. VÉRIFIER L'ORCHESTRATEUR
# ===============================================================================

echo -e "${BLUE}▶ MAPPING DE L'ORCHESTRATEUR${NC}"
echo "========================================================================"

echo "L'orchestrateur pourrait mal interpréter certains topics."
echo ""
echo "Topics qui pourraient causer confusion :"
echo "  - rpi/system/uptime → pourrait être mappé vers system.time ?"
echo "  - rpi/system/time → mappé vers system.time"
echo ""
echo "Vérifiez dans le navigateur (F12) :"
echo "  ${YELLOW}window.orchestrator.subscribedTopics${NC}"
echo "  ${YELLOW}window.orchestrator.topicMapping${NC}"

echo ""

# ===============================================================================
# 5. SOLUTION SUGGÉRÉE
# ===============================================================================

echo -e "${BLUE}▶ SOLUTION SUGGÉRÉE${NC}"
echo "========================================================================"

echo "1. Si le widget uptime publie un mauvais timestamp :"
echo "   ${YELLOW}sudo systemctl stop maxlink-widget-uptime${NC}"
echo ""
echo "2. Vérifiez dans config/variables.js le mapping des topics"
echo ""
echo "3. Dans la console du navigateur, tracez l'origine :"
echo "   ${YELLOW}window.orchestrator.handleMessage = function(topic, payload) {${NC}"
echo "   ${YELLOW}  console.log('MQTT Message:', topic, payload);${NC}"
echo "   ${YELLOW}  // Code original...${NC}"
echo "   ${YELLOW}}${NC}"

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo ""