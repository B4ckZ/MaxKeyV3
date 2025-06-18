#!/bin/bash

# ===============================================================================
# VÉRIFICATION ET CONFIGURATION DEVICES.JSON
# ===============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Le bon chemin
DEVICES_FILE="/var/www/maxlink-dashboard/widgets/wifistats/devices.json"

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}CONFIGURATION TIME SOURCE - DEVICES.JSON${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# ===============================================================================
# 1. VÉRIFICATION DU FICHIER
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION DU FICHIER DEVICES.JSON${NC}"
echo "========================================================================"

if [ -f "$DEVICES_FILE" ]; then
    echo -e "  ${GREEN}✓${NC} Fichier trouvé : $DEVICES_FILE"
    
    # Afficher le contenu actuel
    echo ""
    echo "◦ Contenu actuel :"
    cat "$DEVICES_FILE" | python3 -m json.tool 2>/dev/null | head -20 | sed 's/^/    /' || {
        echo "    Format JSON invalide ou fichier vide"
        cat "$DEVICES_FILE" | head -10 | sed 's/^/    /'
    }
    
    # Chercher les time_source
    echo ""
    echo "◦ Devices avec time_source activé :"
    python3 -c "
import json
try:
    with open('$DEVICES_FILE', 'r') as f:
        devices = json.load(f)
        time_sources = [(mac, info['name']) for mac, info in devices.items() if info.get('time_source', False)]
        if time_sources:
            for mac, name in time_sources:
                print(f'    ✓ {mac} - {name}')
        else:
            print('    ⚠ Aucun device configuré comme time_source')
except:
    print('    ✗ Erreur lors de la lecture du fichier')
" 2>/dev/null
else
    echo -e "  ${RED}✗${NC} Fichier non trouvé"
fi

echo ""

# ===============================================================================
# 2. VÉRIFICATION DES CLIENTS WIFI ACTUELS
# ===============================================================================

echo -e "${BLUE}▶ CLIENTS WIFI CONNECTÉS${NC}"
echo "========================================================================"

# Vérifier les clients connectés
CLIENT_COUNT=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station")

if [ $CLIENT_COUNT -eq 0 ]; then
    echo -e "  ${YELLOW}⚠${NC} Aucun client WiFi connecté actuellement"
    echo ""
    echo "  Pour que l'indicateur fonctionne, vous devez :"
    echo "  1. Connecter un appareil au WiFi MaxLink-NETWORK"
    echo "  2. Configurer cet appareil comme time_source dans devices.json"
else
    echo -e "  ${GREEN}✓${NC} $CLIENT_COUNT client(s) connecté(s) :"
    echo ""
    
    # Lister les MACs des clients
    MACS=$(iw dev wlan0 station dump 2>/dev/null | grep "Station" | awk '{print $2}')
    
    for MAC in $MACS; do
        echo "    • $MAC"
        
        # Vérifier si ce MAC est dans devices.json
        if [ -f "$DEVICES_FILE" ]; then
            python3 -c "
import json
try:
    with open('$DEVICES_FILE', 'r') as f:
        devices = json.load(f)
        mac_lower = '$MAC'.lower()
        if mac_lower in devices:
            info = devices[mac_lower]
            print(f'      → Configuré: {info.get(\"name\", \"Sans nom\")}')
            if info.get('time_source', False):
                print('      → ✓ TIME SOURCE ACTIF')
        else:
            print('      → Non configuré dans devices.json')
except:
    pass
" 2>/dev/null
        fi
    done
fi

echo ""

# ===============================================================================
# 3. EXEMPLE DE CONFIGURATION
# ===============================================================================

echo -e "${BLUE}▶ EXEMPLE DE CONFIGURATION${NC}"
echo "========================================================================"

echo "Pour ajouter un device comme source de temps :"
echo ""
echo "1. Éditez le fichier :"
echo "   ${YELLOW}sudo nano $DEVICES_FILE${NC}"
echo ""
echo "2. Ajoutez ou modifiez une entrée (exemple) :"
echo '   {'
echo '     "aa:bb:cc:dd:ee:ff": {'
echo '       "name": "PC Bureau",'
echo '       "type": "computer",'
echo '       "icon": "laptop",'
echo '       "time_source": true'
echo '     }'
echo '   }'
echo ""
echo "3. Remplacez aa:bb:cc:dd:ee:ff par l'adresse MAC réelle"
echo ""
echo "4. Sauvegardez et rafraîchissez le dashboard"

echo ""

# ===============================================================================
# 4. TEST EN TEMPS RÉEL
# ===============================================================================

echo -e "${BLUE}▶ TEST EN TEMPS RÉEL${NC}"
echo "========================================================================"

echo "Surveillance des messages MQTT (10 secondes)..."
echo "Topics surveillés :"
echo "  - rpi/network/wifi/clients"
echo "  - rpi/system/time"
echo ""

# Écouter les deux topics
timeout 10 mosquitto_sub \
    -h localhost -u mosquitto -P mqtt \
    -t "rpi/network/wifi/clients" \
    -t "rpi/system/time" \
    -v 2>/dev/null | while read line; do
    
    if [[ $line == *"rpi/network/wifi/clients"* ]]; then
        echo -e "${BLUE}[WIFI]${NC} Clients détectés"
        # Extraire le nombre de clients
        COUNT=$(echo "$line" | grep -o '"count": [0-9]*' | grep -o '[0-9]*' || echo "0")
        echo "       → $COUNT client(s)"
    elif [[ $line == *"rpi/system/time"* ]]; then
        echo -e "${GREEN}[TIME]${NC} Heure système reçue"
    fi
done

echo ""

# ===============================================================================
# 5. RÉSUMÉ DU STATUT
# ===============================================================================

echo -e "${BLUE}▶ RÉSUMÉ DU STATUT${NC}"
echo "========================================================================"

# Service WiFiStats
if systemctl is-active --quiet maxlink-widget-wifistats; then
    echo -e "  ${GREEN}✓${NC} Service WiFiStats : Actif"
else
    echo -e "  ${RED}✗${NC} Service WiFiStats : Inactif"
fi

# Service TimSync
if systemctl is-active --quiet maxlink-widget-timesync; then
    echo -e "  ${GREEN}✓${NC} Service TimSync : Actif"
else
    echo -e "  ${RED}✗${NC} Service TimSync : Inactif"
fi

# Clients WiFi
if [ $CLIENT_COUNT -gt 0 ]; then
    echo -e "  ${GREEN}✓${NC} Clients WiFi : $CLIENT_COUNT connecté(s)"
else
    echo -e "  ${YELLOW}⚠${NC} Clients WiFi : Aucun"
fi

# Time Source
if [ -f "$DEVICES_FILE" ]; then
    TIME_SOURCE_COUNT=$(python3 -c "
import json
try:
    with open('$DEVICES_FILE', 'r') as f:
        devices = json.load(f)
        count = sum(1 for d in devices.values() if d.get('time_source', False))
        print(count)
except:
    print(0)
" 2>/dev/null)
    
    if [ "$TIME_SOURCE_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Time Source : $TIME_SOURCE_COUNT configuré(s)"
    else
        echo -e "  ${YELLOW}⚠${NC} Time Source : Aucun configuré"
    fi
else
    echo -e "  ${RED}✗${NC} Fichier devices.json : Non trouvé"
fi

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# ===============================================================================
# 6. ACTION SUGGÉRÉE
# ===============================================================================

if [ $CLIENT_COUNT -eq 0 ]; then
    echo -e "${YELLOW}⚠ ACTION REQUISE :${NC}"
    echo "  Connectez votre PC ou téléphone au réseau WiFi MaxLink-NETWORK"
    echo "  pour que le widget puisse détecter des clients."
elif [ "$TIME_SOURCE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ ACTION REQUISE :${NC}"
    echo "  Configurez au moins un device comme time_source dans devices.json"
    echo "  pour que l'indicateur passe au vert."
else
    echo -e "${GREEN}✓ Tout semble correctement configuré !${NC}"
    echo "  Si l'indicateur reste rouge, rafraîchissez le dashboard."
fi

echo ""