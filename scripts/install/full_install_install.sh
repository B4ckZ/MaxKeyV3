#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION COMPLÈTE AUTOMATISÉE
# Script unique pour l'interface - Installe tous les composants
# Version corrigée - utilise uniquement services_status.json
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

# Fichier de statut unique
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"
SERVICES_STATUS_DIR="$(dirname "$SERVICES_STATUS_FILE")"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Créer le répertoire de statut
mkdir -p "$SERVICES_STATUS_DIR"

# Initialiser le logging
init_logging "Installation complète MaxLink" "install"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Mettre à jour le statut d'installation dans services_status.json
update_install_status() {
    local service_id="${1%.sh}"  # Enlever l'extension .sh
    service_id="${service_id%_install}"  # Enlever _install
    local status="$2"  # "active" ou "inactive"
    local message="$3"
    
    python3 -c "
import json
from datetime import datetime

try:
    with open('$SERVICES_STATUS_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['$service_id'] = {
    'status': '$status',
    'last_update': datetime.now().isoformat(),
    'message': '$message'
}

with open('$SERVICES_STATUS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Afficher le statut d'installation
show_install_status() {
    echo ""
    echo "========================================================================"
    echo "STATUT DE L'INSTALLATION"
    echo "========================================================================"
    
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        python3 -c "
import json

with open('$SERVICES_STATUS_FILE', 'r') as f:
    data = json.load(f)

for service_id, info in data.items():
    if service_id in ['update', 'ap', 'nginx', 'mqtt', 'mqtt_wgs', 'orchestrator']:
        status = info.get('status', 'inactive')
        symbol = '✓' if status == 'active' else '✗'
        print(f'  {symbol} {service_id}: {status}')
"
    fi
    
    echo "========================================================================"
    echo ""
}

# Vérifier si un script a déjà été exécuté avec succès
is_already_installed() {
    local script_name="$1"
    local service_id="${script_name%.sh}"
    service_id="${service_id%_install}"
    
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        python3 -c "
import json
try:
    with open('$SERVICES_STATUS_FILE', 'r') as f:
        data = json.load(f)
    status = data.get('$service_id', {}).get('status', '')
    print('yes' if status == 'active' else 'no')
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

# Initialiser le fichier de statut s'il n'existe pas
[ ! -f "$SERVICES_STATUS_FILE" ] && echo "{}" > "$SERVICES_STATUS_FILE"

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
        
        # Mettre à jour le statut
        service_id="${script_name%.sh}"
        service_id="${service_id%_install}"
        update_install_status "$script_name" "inactive" "Script non trouvé"
        
        ((FAILED_SCRIPTS++))
        continue
    fi
    
    echo "◦ Exécution de $script_name..."
    echo ""
    log_info "Exécution de $script_name"
    
    # Exécuter le script avec la variable pour ne pas reboot
    export SKIP_REBOOT=true
    export SERVICE_ID="${script_name%.sh}"
    SERVICE_ID="${SERVICE_ID%_install}"
    export SERVICE_ID
    
    if bash "$script_path"; then
        echo ""
        echo "  ↦ $description : Installation réussie ✓"
        update_install_status "$script_name" "active" "Installation réussie"
        log_success "$script_name installé avec succès"
    else
        echo ""
        echo "  ↦ $description : Échec de l'installation ✗"
        echo "  ↦ ERREUR : Consultez les logs pour plus de détails"
        update_install_status "$script_name" "inactive" "Échec de l'installation"
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
    echo ""
    echo "Un redémarrage est nécessaire pour finaliser l'installation."
    echo ""
    echo "  ↦ Redémarrage du système dans 30 secondes..."
    echo ""
    
    sleep 30
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
        
        sleep 60
        log_info "Redémarrage du système malgré les erreurs"
        reboot
    else
        echo "Le système ne sera pas redémarré automatiquement."
        echo "Redémarrez manuellement après avoir résolu les problèmes."
    fi
    
    exit 1
fi