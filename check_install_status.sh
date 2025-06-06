#!/bin/bash

# ===============================================================================
# MAXLINK - VÉRIFICATION DE L'ÉTAT DE L'INSTALLATION
# Script pour vérifier où en est l'installation complète
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fichiers de statut
INSTALL_STATUS_FILE="/var/lib/maxlink/full_install_status.json"
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"

# Header
clear
echo ""
echo "========================================================================"
echo "VÉRIFICATION DE L'ÉTAT DE L'INSTALLATION MAXLINK"
echo "========================================================================"
echo ""

# ===============================================================================
# 1. VÉRIFIER L'ÉTAT DE L'INSTALLATION COMPLÈTE
# ===============================================================================

echo -e "${BLUE}▶ ÉTAT DE L'INSTALLATION${NC}"
echo "========================================================================"

if [ -f "$INSTALL_STATUS_FILE" ]; then
    echo "◦ Historique d'installation trouvé"
    echo ""
    
    # Afficher l'état de chaque script
    python3 << EOF
import json
from datetime import datetime

with open('$INSTALL_STATUS_FILE', 'r') as f:
    data = json.load(f)

# Calculer la durée depuis le début
if 'start_time' in data:
    start = datetime.fromisoformat(data['start_time'])
    print(f"  ↦ Début de l'installation : {start.strftime('%Y-%m-%d %H:%M:%S')}")
    print("")

# Scripts attendus dans l'ordre
expected_scripts = [
    'update_install.sh',
    'ap_install.sh', 
    'nginx_install.sh',
    'mqtt_install.sh',
    'mqtt_wgs_install.sh',
    'orchestrator_install.sh'
]

print("  État des composants :")
print("")

all_success = True
for script in expected_scripts:
    if script in data.get('installations', {}):
        info = data['installations'][script]
        status = info['status']
        
        if status == 'success':
            symbol = '✓'
            color = '\033[0;32m'  # Green
        elif status == 'failed':
            symbol = '✗'
            color = '\033[0;31m'  # Red
            all_success = False
        elif status == 'running':
            symbol = '⟳'
            color = '\033[1;33m'  # Yellow
            all_success = False
        else:
            symbol = '○'
            color = '\033[0m'     # Default
            all_success = False
            
        script_name = script.replace('_install.sh', '').replace('_', ' ').title()
        print(f"  {color}{symbol}\033[0m {script_name:20} : {status}")
    else:
        all_success = False
        script_name = script.replace('_install.sh', '').replace('_', ' ').title()
        print(f"  ○ {script_name:20} : non installé")

print("")
if all_success:
    print("  \033[0;32m✓ Installation complète réussie !\033[0m")
else:
    print("  \033[1;33m⚠ Installation incomplète ou en cours\033[0m")
EOF
    
else
    echo -e "  ${YELLOW}↦ Aucune installation complète détectée${NC}"
    echo ""
    echo "  Pour lancer l'installation complète :"
    echo "    sudo bash /media/prod/USBTOOL/full_install.sh"
fi

echo ""

# ===============================================================================
# 2. VÉRIFIER L'ÉTAT DES SERVICES
# ===============================================================================

echo -e "${BLUE}▶ ÉTAT DES SERVICES${NC}"
echo "========================================================================"

if [ -f "$SERVICES_STATUS_FILE" ]; then
    echo "◦ État des services MaxLink :"
    echo ""
    
    python3 << EOF
import json

with open('$SERVICES_STATUS_FILE', 'r') as f:
    services = json.load(f)

service_names = {
    'update': 'Mise à jour système',
    'ap': 'Point d\'accès WiFi',
    'nginx': 'Serveur Web',
    'mqtt': 'Broker MQTT',
    'mqtt_wgs': 'Widgets MQTT',
    'orchestrator': 'Orchestrateur'
}

for service_id, info in services.items():
    status = info.get('status', 'unknown')
    name = service_names.get(service_id, service_id)
    
    if status == 'active':
        symbol = '✓'
        color = '\033[0;32m'  # Green
    else:
        symbol = '✗'
        color = '\033[0;31m'  # Red
        
    print(f"  {color}{symbol}\033[0m {name:20} : {status}")
EOF
    
else
    echo -e "  ${YELLOW}↦ Aucun statut de service trouvé${NC}"
fi

echo ""

# ===============================================================================
# 3. VÉRIFIER LES SERVICES SYSTEMD
# ===============================================================================

echo -e "${BLUE}▶ SERVICES SYSTEMD${NC}"
echo "========================================================================"

# Services critiques à vérifier
SERVICES=(
    "mosquitto:Broker MQTT"
    "nginx:Serveur Web"
    "NetworkManager:Gestionnaire réseau"
)

echo "◦ Services système :"
for service_info in "${SERVICES[@]}"; do
    IFS=':' read -r service_name service_desc <<< "$service_info"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $service_desc : actif"
    else
        echo -e "  ${RED}✗${NC} $service_desc : inactif"
    fi
done

echo ""
echo "◦ Widgets MaxLink :"

# Vérifier les widgets
widget_count=0
active_widgets=0

for service_file in /etc/systemd/system/maxlink-widget-*.service; do
    if [ -f "$service_file" ]; then
        service_name=$(basename "$service_file" .service)
        widget_name=$(echo "$service_name" | sed 's/maxlink-widget-//')
        
        ((widget_count++))
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Widget $widget_name : actif"
            ((active_widgets++))
        else
            echo -e "  ${RED}✗${NC} Widget $widget_name : inactif"
        fi
    fi
done

if [ $widget_count -eq 0 ]; then
    echo -e "  ${YELLOW}↦ Aucun widget installé${NC}"
else
    echo ""
    echo "  Total : $active_widgets/$widget_count widgets actifs"
fi

echo ""

# ===============================================================================
# 4. RÉSUMÉ ET RECOMMANDATIONS
# ===============================================================================

echo -e "${BLUE}▶ RÉSUMÉ${NC}"
echo "========================================================================"

# Déterminer l'état global
if [ -f "$INSTALL_STATUS_FILE" ]; then
    all_installed=$(python3 -c "
import json
with open('$INSTALL_STATUS_FILE', 'r') as f:
    data = json.load(f)
installations = data.get('installations', {})
expected = ['update_install.sh', 'ap_install.sh', 'nginx_install.sh', 'mqtt_install.sh', 'mqtt_wgs_install.sh', 'orchestrator_install.sh']
all_success = all(installations.get(s, {}).get('status') == 'success' for s in expected)
print('yes' if all_success else 'no')
")
    
    if [ "$all_installed" = "yes" ]; then
        echo -e "${GREEN}✓ Installation complète réussie${NC}"
        echo ""
        echo "Tous les composants MaxLink sont installés et configurés."
        echo ""
        echo "Accès au système :"
        echo "  • Dashboard : http://192.168.4.1"
        echo "  • WiFi : MaxLink-NETWORK"
        echo "  • MQTT : localhost:1883 (mosquitto/mqtt)"
    else
        echo -e "${YELLOW}⚠ Installation incomplète${NC}"
        echo ""
        echo "Certains composants ne sont pas installés ou ont échoué."
        echo ""
        echo "Actions recommandées :"
        echo "  1. Relancer l'installation complète :"
        echo "     sudo bash /media/prod/USBTOOL/full_install.sh"
        echo ""
        echo "  2. Ou installer les composants manquants individuellement"
    fi
else
    echo -e "${YELLOW}⚠ Aucune installation détectée${NC}"
    echo ""
    echo "Pour installer MaxLink, exécutez :"
    echo "  sudo bash /media/prod/USBTOOL/full_install.sh"
fi

echo ""
echo "========================================================================"
echo ""

# Options supplémentaires
echo "Autres commandes utiles :"
echo "  • Diagnostic complet : sudo /media/prod/USBTOOL/diag.sh"
echo "  • État orchestrateur : sudo /usr/local/bin/maxlink-orchestrator status"
echo "  • Logs temps réel   : sudo journalctl -u 'maxlink-*' -f"
echo ""