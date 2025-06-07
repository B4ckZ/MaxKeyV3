#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION COMPLÈTE AUTOMATISÉE
# Script unique pour l'interface - Installe tous les composants
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Délai entre les installations (en secondes)
INSTALL_DELAY=10

# Scripts à exécuter dans l'ordre
INSTALL_SCRIPTS=(
    "update_install.sh:Mise à jour système et cache"
    "ap_install.sh:Point d'accès WiFi"
    "nginx_install.sh:Serveur Web et Dashboard"
    "mqtt_install.sh:Broker MQTT"
    "mqtt_wgs_install.sh:Widgets MQTT"
    "orchestrator_install.sh:Orchestrateur et finalisation"
)

# Fichier de statut pour suivre la progression
INSTALL_STATUS_FILE="/var/lib/maxlink/full_install_status.json"
INSTALL_STATUS_DIR="$(dirname "$INSTALL_STATUS_FILE")"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Créer le répertoire de statut
mkdir -p "$INSTALL_STATUS_DIR"

# Initialiser le logging
init_logging "Installation complète MaxLink" "install"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Mettre à jour le statut d'installation
update_install_status() {
    local script_name="$1"
    local status="$2"  # "pending", "running", "success", "failed"
    local message="$3"
    
    python3 -c "
import json
from datetime import datetime

try:
    with open('$INSTALL_STATUS_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {'installations': {}, 'start_time': datetime.now().isoformat()}

data['installations']['$script_name'] = {
    'status': '$status',
    'message': '$message',
    'timestamp': datetime.now().isoformat()
}

with open('$INSTALL_STATUS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Afficher le statut d'installation
show_install_status() {
    echo ""
    echo "========================================================================"
    echo "STATUT DE L'INSTALLATION"
    echo "========================================================================"
    
    if [ -f "$INSTALL_STATUS_FILE" ]; then
        python3 -c "
import json

with open('$INSTALL_STATUS_FILE', 'r') as f:
    data = json.load(f)

for script, info in data.get('installations', {}).items():
    status = info['status']
    symbol = '✓' if status == 'success' else '✗' if status == 'failed' else '⟳' if status == 'running' else '○'
    print(f'  {symbol} {script}: {status}')
"
    fi
    
    echo "========================================================================"
    echo ""
}

# Vérifier si un script a déjà été exécuté avec succès
is_already_installed() {
    local script_name="$1"
    
    if [ -f "$INSTALL_STATUS_FILE" ]; then
        python3 -c "
import json
try:
    with open('$INSTALL_STATUS_FILE', 'r') as f:
        data = json.load(f)
    status = data.get('installations', {}).get('$script_name', {}).get('status', '')
    print('yes' if status == 'success' else 'no')
except:
    print('no')
"
    else
        echo "no"
    fi
}

# Attendre avec affichage
wait_with_countdown() {
    local seconds=$1
    local message=$2
    
    echo -n "  ↦ $message "
    for ((i=$seconds; i>0; i--)); do
        echo -n "$i "
        sleep 1
    done
    echo "✓"
}

# ===============================================================================
# VÉRIFICATIONS
# ===============================================================================

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    echo "Usage: sudo bash $0"
    exit 1
fi

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

clear
echo ""
echo "========================================================================"
echo " MAXLINK™ - INSTALLATION COMPLÈTE V$MAXLINK_VERSION"
echo " $MAXLINK_COPYRIGHT"
echo "========================================================================"
echo ""
echo "Installation automatique de tous les composants MaxLink :"
echo ""

# Afficher la liste des installations prévues
for script_info in "${INSTALL_SCRIPTS[@]}"; do
    IFS=':' read -r script desc <<< "$script_info"
    echo "  • $desc"
done

echo ""
echo "L'installation complète prendra environ 10-15 minutes."
echo ""
echo "Démarrage de l'installation..."
echo ""

log_info "========== DÉBUT DE L'INSTALLATION COMPLÈTE MAXLINK =========="

# Initialiser le fichier de statut
echo "{}" > "$INSTALL_STATUS_FILE"

# Timer global
TOTAL_START_TIME=$(date +%s)

# Exécuter chaque script
CURRENT_STEP=0
TOTAL_STEPS=${#INSTALL_SCRIPTS[@]}
FAILED_SCRIPTS=0

for script_info in "${INSTALL_SCRIPTS[@]}"; do
    IFS=':' read -r script_name description <<< "$script_info"
    ((CURRENT_STEP++))
    
    echo ""
    echo "========================================================================"
    echo "ÉTAPE $CURRENT_STEP/$TOTAL_STEPS : $description"
    echo "========================================================================"
    echo ""
    
    # Vérifier si déjà installé
    if [ "$(is_already_installed "$script_name")" = "yes" ]; then
        echo "  ↦ Déjà installé, passage à l'étape suivante ✓"
        log_info "$script_name déjà installé, skip"
        continue
    fi
    
    # Chemins du script (même répertoire que ce script)
    script_path="$SCRIPT_DIR/$script_name"
    
    if [ ! -f "$script_path" ]; then
        echo "  ↦ Script non trouvé : $script_path ✗"
        echo "  ↦ ERREUR : Impossible de continuer sans ce script"
        log_error "Script non trouvé: $script_path"
        update_install_status "$script_name" "failed" "Script non trouvé"
        ((FAILED_SCRIPTS++))
        continue
    fi
    
    # Mettre à jour le statut
    update_install_status "$script_name" "running" "Installation en cours"
    
    echo "◦ Exécution de $script_name..."
    echo ""
    log_info "Exécution de $script_name"
    
    # Exécuter le script avec la variable pour ne pas reboot
    export SKIP_REBOOT=true
    export SERVICE_ID="${script_name%.sh}"  # Pour la mise à jour des statuts
    
    if bash "$script_path"; then
        echo ""
        echo "  ↦ $description : Installation réussie ✓"
        update_install_status "$script_name" "success" "Installation réussie"
        log_success "$script_name installé avec succès"
    else
        echo ""
        echo "  ↦ $description : Échec de l'installation ✗"
        echo "  ↦ ERREUR : Consultez les logs pour plus de détails"
        update_install_status "$script_name" "failed" "Échec de l'installation"
        log_error "$script_name a échoué"
        ((FAILED_SCRIPTS++))
        
        # Continuer avec les autres scripts
        echo ""
        echo "  ↦ Poursuite de l'installation malgré l'erreur..."
    fi
    
    # Attendre entre les installations (sauf pour la dernière)
    if [ $CURRENT_STEP -lt $TOTAL_STEPS ]; then
        echo ""
        wait_with_countdown $INSTALL_DELAY "Pause avant l'étape suivante..."
    fi
done

# Calculer le temps total
TOTAL_END_TIME=$(date +%s)
TOTAL_DURATION=$((TOTAL_END_TIME - TOTAL_START_TIME))
TOTAL_MINUTES=$((TOTAL_DURATION / 60))
TOTAL_SECONDS=$((TOTAL_DURATION % 60))

# Afficher le résumé final
echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE"
echo "========================================================================"
echo ""
echo "Durée totale : ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
echo ""

# Afficher le statut final
show_install_status

# Mettre à jour explicitement tous les statuts des services installés avec succès
echo "◦ Mise à jour finale des statuts des services..."

# S'assurer que le fichier de statuts existe
mkdir -p "$(dirname "$SERVICES_STATUS_FILE")"
[ ! -f "$SERVICES_STATUS_FILE" ] && echo "{}" > "$SERVICES_STATUS_FILE"

if [ -f "$INSTALL_STATUS_FILE" ]; then
    python3 << EOF
import json
import subprocess
import sys

# Charger le statut d'installation
with open('$INSTALL_STATUS_FILE', 'r') as f:
    install_data = json.load(f)

# Mapper les scripts aux service_ids
script_to_service = {
    'update_install.sh': 'update',
    'ap_install.sh': 'ap',
    'nginx_install.sh': 'nginx',
    'mqtt_install.sh': 'mqtt',
    'mqtt_wgs_install.sh': 'mqtt_wgs',
    'orchestrator_install.sh': 'orchestrator'
}

# Pour chaque installation réussie, mettre à jour le statut
updated_count = 0
for script_name, info in install_data.get('installations', {}).items():
    if info.get('status') == 'success' and script_name in script_to_service:
        service_id = script_to_service[script_name]
        # Exécuter la commande bash pour mettre à jour le statut
        cmd = f'source $BASE_DIR/scripts/common/variables.sh && update_service_status {service_id} active'
        result = subprocess.run(['bash', '-c', cmd], capture_output=True)
        if result.returncode == 0:
            updated_count += 1
            print(f"  ↦ Statut mis à jour : {service_id}")

print(f"  ↦ {updated_count} statuts de services mis à jour ✓")
EOF
fi

if [ $FAILED_SCRIPTS -eq 0 ]; then
    echo "✓ Tous les composants ont été installés avec succès !"
    echo ""
    echo "MaxLink est maintenant opérationnel. Les fonctionnalités suivantes sont disponibles :"
    echo "  • Point d'accès WiFi : $AP_SSID"
    echo "  • Dashboard Web : http://$AP_IP ou http://$NGINX_DASHBOARD_DOMAIN"
    echo "  • Broker MQTT : $MQTT_USER@localhost:$MQTT_PORT"
    echo "  • Widgets de monitoring actifs"
    echo "  • Orchestrateur pour la gestion des services"
    echo ""
    echo "Commandes utiles :"
    echo "  • État du système : sudo /usr/local/bin/maxlink-orchestrator status"
    echo "  • Vérification : sudo /usr/local/bin/maxlink-orchestrator check"
    echo "  • Diagnostic : sudo $BASE_DIR/diag.sh"
    echo ""
    
    log_success "Installation complète réussie - 0 erreur"
    
    # Un seul redémarrage à la fin
    echo "========================================================================"
    echo "REDÉMARRAGE NÉCESSAIRE"
    echo "========================================================================"
    echo ""
    echo "Un redémarrage est nécessaire pour finaliser l'installation."
    echo ""
    echo "  ↦ Redémarrage du système dans 30 secondes..."
    echo ""
    
    # Compte à rebours de 30 secondes
    for ((i=30; i>0; i--)); do
        echo -ne "\r  Redémarrage dans $i secondes... "
        sleep 1
    done
    echo ""
    
    log_info "Redémarrage du système pour finalisation"
    reboot
else
    echo "⚠ Installation terminée avec $FAILED_SCRIPTS erreur(s)"
    echo ""
    echo "Certains composants n'ont pas pu être installés correctement."
    echo "Consultez les logs pour plus de détails :"
    echo "  • Logs système : $LOG_SYSTEM"
    echo "  • Logs d'installation : $LOG_INSTALL"
    echo ""
    echo "Actions possibles :"
    echo "  • Relancer ce script pour réessayer les installations échouées"
    echo "  • Installer manuellement les composants manquants"
    echo "  • Vérifier l'état avec : sudo $BASE_DIR/check.sh"
    echo ""
    
    log_error "Installation terminée avec $FAILED_SCRIPTS erreurs"
    
    # Si l'orchestrateur est installé, on peut quand même redémarrer
    if [ "$(is_already_installed "orchestrator_install.sh")" = "yes" ]; then
        echo "L'orchestrateur est installé, un redémarrage est recommandé."
        echo ""
        echo "  ↦ Redémarrage du système dans 30 secondes..."
        echo ""
        
        for ((i=30; i>0; i--)); do
            echo -ne "\r  Redémarrage dans $i secondes... "
            sleep 1
        done
        echo ""
        
        log_info "Redémarrage du système malgré les erreurs"
        reboot
    else
        echo "Le système ne sera pas redémarré automatiquement."
        echo "Redémarrez manuellement après avoir résolu les problèmes."
    fi
    
    exit 1
fi