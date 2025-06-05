#!/bin/bash

# ===============================================================================
# MAXLINK - SCRIPT DE DIAGNOSTIC COMPLET
# Vérifie l'état de tous les services et la communication MQTT
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
MQTT_USER="${MQTT_USER:-mosquitto}"
MQTT_PASS="${MQTT_PASS:-mqtt}"
MQTT_PORT="${MQTT_PORT:-1883}"
ERRORS=0
WARNINGS=0

# Header
clear
echo ""
echo "========================================================================"
echo "DIAGNOSTIC MAXLINK - $(date)"
echo "========================================================================"
echo ""

# ===============================================================================
# 1. VÉRIFICATION DES SERVICES SYSTEMD
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION DES SERVICES${NC}"
echo "========================================================================"

# Liste des services à vérifier
SERVICES=(
    "mosquitto:Broker MQTT"
    "nginx:Serveur Web"
    "NetworkManager:Gestionnaire réseau"
    "maxlink-widget-servermonitoring:Widget Server Monitoring"
    "maxlink-widget-mqttstats:Widget MQTT Stats"
    "maxlink-widget-wifistats:Widget WiFi Stats"
)

for service_info in "${SERVICES[@]}"; do
    IFS=':' read -r service_name service_desc <<< "$service_info"
    
    printf "%-40s" "◦ $service_desc"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo -e "${GREEN}[ACTIF]${NC}"
        
        # Afficher l'uptime du service
        uptime=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [ -n "$uptime" ]; then
            echo "  ↦ Démarré: $uptime"
        fi
    else
        echo -e "${RED}[INACTIF]${NC}"
        ((ERRORS++))
        
        # Vérifier si le service existe
        if systemctl list-unit-files | grep -q "^$service_name"; then
            echo "  ↦ Service installé mais non actif"
            
            # Afficher les dernières lignes de log si disponibles
            echo "  ↦ Derniers logs:"
            journalctl -u "$service_name" -n 3 --no-pager 2>/dev/null | sed 's/^/    /'
        else
            echo "  ↦ Service non installé"
        fi
    fi
done

echo ""

# ===============================================================================
# 2. VÉRIFICATION MQTT
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION MQTT${NC}"
echo "========================================================================"

# Test de connexion basique
printf "%-40s" "◦ Connexion au broker"
if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/diagnostic" -m "test" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC}"
else
    echo -e "${RED}[ÉCHEC]${NC}"
    ((ERRORS++))
fi

# Vérifier les topics système
printf "%-40s" "◦ Topics système (\$SYS)"
if timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null | grep -q "mosquitto"; then
    echo -e "${GREEN}[OK]${NC}"
    
    # Afficher la version
    version=$(timeout 1 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null)
    echo "  ↦ Version: $version"
else
    echo -e "${YELLOW}[INDISPONIBLE]${NC}"
    ((WARNINGS++))
fi

# Compter les clients connectés
printf "%-40s" "◦ Clients MQTT connectés"
clients=$(timeout 1 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/clients/connected' -C 1 2>/dev/null)
if [ -n "$clients" ]; then
    echo -e "${GREEN}[$clients clients]${NC}"
else
    echo -e "${YELLOW}[?]${NC}"
fi

echo ""

# ===============================================================================
# 3. VÉRIFICATION DES TOPICS DE DONNÉES
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION DES TOPICS DE DONNÉES${NC}"
echo "========================================================================"

# Topics à vérifier
TOPICS=(
    "rpi/system/cpu/core1:CPU Core 1"
    "rpi/system/temperature/cpu:Température CPU"
    "rpi/system/memory/ram:Mémoire RAM"
    "rpi/system/uptime:Uptime système"
    "rpi/network/mqtt/stats:Stats MQTT"
    "rpi/network/wifi/clients:Clients WiFi"
)

echo "◦ Écoute des topics pendant 5 secondes..."
echo ""

# Créer un fichier temporaire pour stocker les résultats
TEMP_FILE=$(mktemp)

# Lancer l'écoute en arrière-plan
timeout 5 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '#' -v 2>/dev/null > "$TEMP_FILE" &
SUB_PID=$!

# Afficher une barre de progression
for i in {1..5}; do
    echo -ne "\r  ↦ Collecte en cours... [$i/5s]"
    sleep 1
done
echo ""

# Attendre la fin du timeout
wait $SUB_PID 2>/dev/null

echo ""
echo "◦ Topics détectés:"

# Analyser les topics reçus
for topic_info in "${TOPICS[@]}"; do
    IFS=':' read -r topic_name topic_desc <<< "$topic_info"
    
    printf "  %-35s" "• $topic_desc"
    
    if grep -q "^$topic_name " "$TEMP_FILE"; then
        echo -e "${GREEN}[REÇU]${NC}"
        
        # Afficher la dernière valeur
        last_value=$(grep "^$topic_name " "$TEMP_FILE" | tail -1 | cut -d' ' -f2-)
        if [ -n "$last_value" ]; then
            # Essayer d'extraire la valeur du JSON
            if echo "$last_value" | grep -q '"value"'; then
                value=$(echo "$last_value" | grep -o '"value":[^,}]*' | cut -d':' -f2)
                echo "    ↦ Valeur: $value"
            fi
        fi
    else
        echo -e "${RED}[ABSENT]${NC}"
        ((WARNINGS++))
    fi
done

# Afficher d'autres topics détectés
echo ""
echo "◦ Autres topics actifs:"
grep -v '^\$SYS' "$TEMP_FILE" | cut -d' ' -f1 | sort -u | grep -v -E "$(echo ${TOPICS[@]} | sed 's/:.*//g' | tr ' ' '|')" | head -10 | sed 's/^/  • /'

rm -f "$TEMP_FILE"
echo ""

# ===============================================================================
# 4. VÉRIFICATION RÉSEAU
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION RÉSEAU${NC}"
echo "========================================================================"

# Vérifier l'interface WiFi
printf "%-40s" "◦ Interface WiFi (wlan0)"
if ip link show wlan0 >/dev/null 2>&1; then
    echo -e "${GREEN}[PRÉSENTE]${NC}"
    
    # Vérifier le mode
    if iw dev wlan0 info 2>/dev/null | grep -q "type AP"; then
        echo "  ↦ Mode: Access Point"
        
        # Compter les clients
        client_count=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station")
        echo "  ↦ Clients connectés: $client_count"
    else
        echo "  ↦ Mode: Client ou inactif"
    fi
else
    echo -e "${RED}[ABSENTE]${NC}"
    ((ERRORS++))
fi

# Vérifier l'accès au dashboard
printf "%-40s" "◦ Dashboard Web (port 80)"
if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200\|304"; then
    echo -e "${GREEN}[ACCESSIBLE]${NC}"
else
    echo -e "${RED}[INACCESSIBLE]${NC}"
    ((ERRORS++))
fi

# Vérifier le port WebSocket MQTT
printf "%-40s" "◦ WebSocket MQTT (port 9001)"
if netstat -tlnp 2>/dev/null | grep -q ":9001" || ss -tlnp 2>/dev/null | grep -q ":9001"; then
    echo -e "${GREEN}[OUVERT]${NC}"
else
    echo -e "${RED}[FERMÉ]${NC}"
    ((ERRORS++))
fi

echo ""

# ===============================================================================
# 5. VÉRIFICATION DES LOGS
# ===============================================================================

echo -e "${BLUE}▶ DERNIERS MESSAGES D'ERREUR${NC}"
echo "========================================================================"

# Vérifier les erreurs dans les logs des widgets
echo "◦ Erreurs récentes dans les services MaxLink:"
journalctl -u 'maxlink-widget-*' --since "1 hour ago" -p err --no-pager | tail -5 | sed 's/^/  /'

if [ $(journalctl -u 'maxlink-widget-*' --since "1 hour ago" -p err --no-pager | wc -l) -eq 0 ]; then
    echo "  ↦ Aucune erreur récente"
fi

echo ""

# ===============================================================================
# 6. RÉSUMÉ
# ===============================================================================

echo -e "${BLUE}▶ RÉSUMÉ DU DIAGNOSTIC${NC}"
echo "========================================================================"

TOTAL_ISSUES=$((ERRORS + WARNINGS))

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ Système MaxLink opérationnel${NC}"
    echo ""
    echo "Tous les services sont actifs et les données circulent correctement."
else
    echo -e "◦ Erreurs critiques  : ${RED}$ERRORS${NC}"
    echo -e "◦ Avertissements     : ${YELLOW}$WARNINGS${NC}"
    echo ""
    
    if [ $ERRORS -gt 0 ]; then
        echo "Actions recommandées:"
        
        # Recommandations basées sur les erreurs
        if ! systemctl is-active --quiet mosquitto; then
            echo "  • Démarrer Mosquitto : sudo systemctl start mosquitto"
        fi
        
        if ! systemctl is-active --quiet nginx; then
            echo "  • Démarrer Nginx : sudo systemctl start nginx"
        fi
        
        if ! systemctl is-active --quiet maxlink-widget-servermonitoring; then
            echo "  • Démarrer les widgets : sudo /usr/local/bin/maxlink-orchestrator restart-widgets"
        fi
    fi
fi

echo ""
echo "========================================================================"
echo ""

# ===============================================================================
# 7. TESTS ADDITIONNELS (OPTIONNELS)
# ===============================================================================

echo -e "${YELLOW}Tests additionnels disponibles:${NC}"
echo ""
echo "1. Voir les logs en temps réel:"
echo "   journalctl -u 'maxlink-*' -f"
echo ""
echo "2. Tester la publication MQTT:"
echo "   mosquitto_pub -h localhost -u $MQTT_USER -P $MQTT_PASS -t 'test/message' -m 'Hello'"
echo ""
echo "3. Écouter tous les messages MQTT:"
echo "   mosquitto_sub -h localhost -u $MQTT_USER -P $MQTT_PASS -t '#' -v"
echo ""
echo "4. Redémarrer tous les services MaxLink:"
echo "   sudo /usr/local/bin/maxlink-orchestrator restart-all"
echo ""

exit $ERRORS