#!/bin/bash

# ===============================================================================
# MAXLINK - VÉRIFICATION DE L'ÉTAT DE L'INSTALLATION
# Script pour vérifier où en est l'installation complète
# Version corrigée - utilise uniquement services_status.json
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fichier de statut unique
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

if [ -f "$SERVICES_STATUS_FILE" ]; then
    echo "◦ Fichier de statuts trouvé"
    echo ""
    
    # Afficher l'état de chaque service
    python3 << EOF
import json
from datetime import datetime

with open('$SERVICES_STATUS_FILE', 'r') as f:
    data = json.load(f)

# Services attendus dans l'ordre
expected_services = [
    ('update', 'Mise à jour système'),
    ('ap', 'Point d\'accès WiFi'),
    ('nginx', 'Serveur Web'),
    ('mqtt', 'Broker MQTT'),
    ('mqtt_wgs', 'Widgets MQTT'),
    ('orchestrator', 'Orchestrateur')
]

print("  État des composants :")
print("")

all_active = True
for service_id, service_name in expected_services:
    if service_id in data:
        info = data[service_id]
        status = info.get('status', 'inactive')
        
        if status == 'active':
            symbol = '✓'
            color = '\033[0;32m'  # Green
        else:
            symbol = '✗'
            color = '\033[0;31m'  # Red
            all_active = False
            
        print(f"  {color}{symbol}\033[0m {service_name:20} : {status}")
        
        # Afficher la date de mise à jour si disponible
        if 'last_update' in info:
            try:
                dt = datetime.fromisoformat(info['last_update'])
                print(f"    ↦ Mis à jour: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
            except:
                pass
    else:
        all_active = False
        print(f"  ○ {service_name:20} : non installé")

print("")
if all_active:
    print("  \033[0;32m✓ Installation complète réussie !\033[0m")
else:
    print("  \033[1;33m⚠ Installation incomplète\033[0m")
EOF
    
else
    echo -e "  ${YELLOW}↦ Aucune installation détectée${NC}"
    echo ""
    echo "  Pour lancer l'installation complète :"
    echo "    sudo bash /media/prod/USBTOOL/full_install.sh"
fi

echo ""

# ===============================================================================
# 2. VÉRIFIER L'ÉTAT DES SERVICES SYSTEMD
# ===============================================================================

echo -e "${BLUE}▶ ÉTAT DES SERVICES${NC}"
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
# 3. RÉSUMÉ ET RECOMMANDATIONS
# ===============================================================================

echo -e "${BLUE}▶ RÉSUMÉ${NC}"
echo "========================================================================"

# Déterminer l'état global
if [ -f "$SERVICES_STATUS_FILE" ]; then
    all_active=$(python3 -c "
import json
with open('$SERVICES_STATUS_FILE', 'r') as f:
    data = json.load(f)
expected = ['update', 'ap', 'nginx', 'mqtt', 'mqtt_wgs', 'orchestrator']
all_active = all(data.get(s, {}).get('status') == 'active' for s in expected)
print('yes' if all_active else 'no')
")
    
    if [ "$all_active" = "yes" ]; then
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
        echo "Certains composants ne sont pas installés ou inactifs."
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