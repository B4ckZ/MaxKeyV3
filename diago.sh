#!/bin/bash

# ===============================================================================
# DIAGNOSTIC TIMESYNC - SCRIPT DE TROUBLESHOOTING
# Analyse complète du widget TimSync pour identifier les problèmes
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
SERVICE_NAME="maxlink-widget-timesync"
WIDGET_NAME="timesync"
COLLECTOR_PATH="/opt/maxlink/widgets/timesync/timesync_collector.py"
CONFIG_PATH="/opt/maxlink/config/widgets/timesync_widget.json"
LOG_PATH="/var/log/maxlink/timesync.log"

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}DIAGNOSTIC WIDGET TIMESYNC MAXLINK${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# ===============================================================================
# 1. VÉRIFICATION DU SERVICE SYSTEMD
# ===============================================================================

echo -e "${BLUE}▶ ÉTAT DU SERVICE SYSTEMD${NC}"
echo "========================================================================"

echo "◦ Service : $SERVICE_NAME"

# État du service
if systemctl is-active --quiet "$SERVICE_NAME"; then
    echo -e "  ${GREEN}✓${NC} Service actif"
else
    echo -e "  ${RED}✗${NC} Service inactif"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    echo -e "  ${GREEN}✓${NC} Service activé au démarrage"
else
    echo -e "  ${RED}✗${NC} Service non activé au démarrage"
fi

# Statut détaillé
echo ""
echo "◦ Statut détaillé :"
systemctl status "$SERVICE_NAME" --no-pager -l | head -20

echo ""

# ===============================================================================
# 2. VÉRIFICATION DES FICHIERS
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION DES FICHIERS${NC}"
echo "========================================================================"

# Collecteur Python
if [ -f "$COLLECTOR_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Collecteur présent : $COLLECTOR_PATH"
    echo "    Permissions : $(ls -la "$COLLECTOR_PATH" | awk '{print $1, $3, $4}')"
    if [ -x "$COLLECTOR_PATH" ]; then
        echo -e "    ${GREEN}✓${NC} Exécutable"
    else
        echo -e "    ${RED}✗${NC} Non exécutable"
    fi
else
    echo -e "  ${RED}✗${NC} Collecteur manquant : $COLLECTOR_PATH"
fi

# Configuration JSON
if [ -f "$CONFIG_PATH" ]; then
    echo -e "  ${GREEN}✓${NC} Configuration présente : $CONFIG_PATH"
    echo "    Permissions : $(ls -la "$CONFIG_PATH" | awk '{print $1, $3, $4}')"
    
    # Vérifier la syntaxe JSON
    if python3 -m json.tool "$CONFIG_PATH" >/dev/null 2>&1; then
        echo -e "    ${GREEN}✓${NC} JSON valide"
    else
        echo -e "    ${RED}✗${NC} JSON invalide"
        echo "    Erreur :"
        python3 -m json.tool "$CONFIG_PATH" 2>&1 | head -3 | sed 's/^/      /'
    fi
else
    echo -e "  ${RED}✗${NC} Configuration manquante : $CONFIG_PATH"
fi

# Répertoire de logs
LOG_DIR=$(dirname "$LOG_PATH")
if [ -d "$LOG_DIR" ]; then
    echo -e "  ${GREEN}✓${NC} Répertoire logs : $LOG_DIR"
    echo "    Permissions : $(ls -lad "$LOG_DIR" | awk '{print $1, $3, $4}')"
else
    echo -e "  ${RED}✗${NC} Répertoire logs manquant : $LOG_DIR"
fi

echo ""

# ===============================================================================
# 3. TEST DU COLLECTEUR PYTHON
# ===============================================================================

echo -e "${BLUE}▶ TEST DU COLLECTEUR PYTHON${NC}"
echo "========================================================================"

if [ -f "$COLLECTOR_PATH" ]; then
    echo "◦ Test de syntaxe Python :"
    if python3 -m py_compile "$COLLECTOR_PATH" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Syntaxe Python correcte"
    else
        echo -e "  ${RED}✗${NC} Erreur de syntaxe Python"
        python3 -m py_compile "$COLLECTOR_PATH" 2>&1 | head -5 | sed 's/^/    /'
    fi
    
    echo ""
    echo "◦ Test des imports :"
    python3 -c "
import sys
sys.path.append('/opt/maxlink/widgets/timesync')
try:
    import json, time, subprocess, logging, os, datetime, paho.mqtt.client
    print('  ✓ Tous les modules disponibles')
except ImportError as e:
    print(f'  ✗ Module manquant: {e}')
" 2>/dev/null || echo -e "  ${RED}✗${NC} Erreur import modules"
    
    echo ""
    echo "◦ Test de chargement du collecteur :"
    timeout 5 python3 -c "
import sys
sys.path.append('/opt/maxlink/widgets/timesync')
try:
    exec(open('$COLLECTOR_PATH').read())
    print('  ✓ Collecteur se charge sans erreur')
except Exception as e:
    print(f'  ✗ Erreur chargement: {e}')
" 2>/dev/null || echo -e "  ${RED}✗${NC} Timeout ou erreur chargement"
else
    echo -e "  ${RED}✗${NC} Impossible de tester, fichier manquant"
fi

echo ""

# ===============================================================================
# 4. VÉRIFICATION MQTT
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION MQTT${NC}"
echo "========================================================================"

# Broker actif
if systemctl is-active --quiet mosquitto; then
    echo -e "  ${GREEN}✓${NC} Broker Mosquitto actif"
else
    echo -e "  ${RED}✗${NC} Broker Mosquitto inactif"
fi

# Test de connexion MQTT
echo ""
echo "◦ Test de connexion MQTT :"
if timeout 3 mosquitto_sub -h localhost -u maxlink -P maxlink123 -t 'test' -C 1 >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Connexion MQTT OK"
else
    echo -e "  ${RED}✗${NC} Impossible de se connecter à MQTT"
    echo "    Vérifiez les identifiants dans $CONFIG_PATH"
fi

# Écouter les topics TimSync
echo ""
echo "◦ Test des topics TimSync (5 secondes) :"
timeout 5 mosquitto_sub -h localhost -u maxlink -P maxlink123 -t 'rpi/system/time' -t 'system/time/sync/+' -v 2>/dev/null | head -3 | sed 's/^/    /' &
MQTT_PID=$!
sleep 5
kill $MQTT_PID 2>/dev/null
wait $MQTT_PID 2>/dev/null

echo ""

# ===============================================================================
# 5. ANALYSE DES LOGS
# ===============================================================================

echo -e "${BLUE}▶ ANALYSE DES LOGS${NC}"
echo "========================================================================"

# Logs systemd
echo "◦ Derniers logs systemd (10 lignes) :"
journalctl -u "$SERVICE_NAME" -n 10 --no-pager | sed 's/^/    /'

echo ""

# Logs du collecteur
if [ -f "$LOG_PATH" ]; then
    echo "◦ Derniers logs du collecteur :"
    tail -10 "$LOG_PATH" | sed 's/^/    /'
    
    echo ""
    echo "◦ Erreurs dans les logs :"
    grep -i "error\|exception\|fail" "$LOG_PATH" 2>/dev/null | tail -5 | sed 's/^/    /' || echo "    Aucune erreur trouvée"
else
    echo -e "  ${YELLOW}⚠${NC} Fichier log non trouvé : $LOG_PATH"
fi

echo ""

# ===============================================================================
# 6. VÉRIFICATION DES DÉPENDANCES
# ===============================================================================

echo -e "${BLUE}▶ VÉRIFICATION DES DÉPENDANCES${NC}"
echo "========================================================================"

# Python et modules
echo "◦ Python et modules :"
python3 --version | sed 's/^/    /'

# paho-mqtt
if python3 -c "import paho.mqtt.client" 2>/dev/null; then
    echo -e "    ${GREEN}✓${NC} paho-mqtt disponible"
else
    echo -e "    ${RED}✗${NC} paho-mqtt manquant"
fi

# timedatectl
if command -v timedatectl >/dev/null 2>&1; then
    echo -e "    ${GREEN}✓${NC} timedatectl disponible"
    echo "    État NTP : $(timedatectl show -p NTP --value 2>/dev/null || echo 'Inconnu')"
else
    echo -e "    ${RED}✗${NC} timedatectl manquant"
fi

echo ""

# ===============================================================================
# 7. TEST MANUEL DU SERVICE
# ===============================================================================

echo -e "${BLUE}▶ TEST MANUEL DU SERVICE${NC}"
echo "========================================================================"

echo "◦ Tentative de démarrage manuel :"
if systemctl start "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Service démarré manuellement"
    sleep 3
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "  ${GREEN}✓${NC} Service reste actif"
    else
        echo -e "  ${RED}✗${NC} Service s'est arrêté"
        echo "    Dernière erreur :"
        journalctl -u "$SERVICE_NAME" -n 3 --no-pager | sed 's/^/      /'
    fi
else
    echo -e "  ${RED}✗${NC} Échec du démarrage manuel"
    echo "    Erreur :"
    systemctl status "$SERVICE_NAME" --no-pager | grep -A 5 "Active:" | sed 's/^/      /'
fi

echo ""

# ===============================================================================
# 8. RECOMMANDATIONS
# ===============================================================================

echo -e "${BLUE}▶ RECOMMANDATIONS${NC}"
echo "========================================================================"

# Analyser les problèmes détectés
ISSUES=0

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    ((ISSUES++))
    echo -e "${RED}1.${NC} Service inactif"
    echo "   → Commande : sudo systemctl start $SERVICE_NAME"
    echo "   → Puis vérifier : sudo systemctl status $SERVICE_NAME"
fi

if [ ! -f "$COLLECTOR_PATH" ]; then
    ((ISSUES++))
    echo -e "${RED}2.${NC} Collecteur manquant"
    echo "   → Réinstaller le widget : sudo /path/to/timesync_install.sh"
fi

if [ ! -f "$CONFIG_PATH" ]; then
    ((ISSUES++))
    echo -e "${RED}3.${NC} Configuration manquante"
    echo "   → Vérifier l'installation du widget"
fi

if ! systemctl is-active --quiet mosquitto; then
    ((ISSUES++))
    echo -e "${RED}4.${NC} MQTT inactif"
    echo "   → Commande : sudo systemctl start mosquitto"
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ Aucun problème majeur détecté${NC}"
    echo ""
    echo "Si le service reste inactif :"
    echo "  1. Vérifier les logs détaillés : journalctl -u $SERVICE_NAME -f"
    echo "  2. Tester le collecteur manuellement : python3 $COLLECTOR_PATH"
    echo "  3. Redémarrer le service : sudo systemctl restart $SERVICE_NAME"
fi

echo ""
echo -e "${BLUE}===============================================================================${NC}"
echo -e "${BLUE}FIN DU DIAGNOSTIC${NC}"
echo -e "${BLUE}===============================================================================${NC}"
echo ""

# ===============================================================================
# 9. COMMANDES UTILES
# ===============================================================================

echo -e "${YELLOW}Commandes utiles pour le debugging :${NC}"
echo ""
echo "• Logs en temps réel        : journalctl -u $SERVICE_NAME -f"
echo "• Redémarrer le service     : sudo systemctl restart $SERVICE_NAME"
echo "• Test manuel du collecteur : sudo python3 $COLLECTOR_PATH"
echo "• État détaillé du service  : sudo systemctl status $SERVICE_NAME -l"
echo "• Logs du broker MQTT       : journalctl -u mosquitto -f"
echo "• Test MQTT                 : mosquitto_sub -h localhost -u maxlink -P maxlink123 -t '#' -v"
echo ""