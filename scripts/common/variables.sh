#!/bin/bash

# ===============================================================================
# MAXLINK - CONFIGURATION CENTRALE (VERSION CORRIGÉE)
# Toutes les variables sans les delays de démarrage
# ===============================================================================

# ===============================================================================
# INFORMATIONS GÉNÉRALES DU PROJET
# ===============================================================================

# Version et informations de l'interface
MAXLINK_VERSION="3"
MAXLINK_COPYRIGHT="© 2025 WERIT. Tous droits réservés."

# ===============================================================================
# CONFIGURATION DE L'OVERLAY DE VERSION
# ===============================================================================

# Configuration de l'overlay de version sur le fond d'écran
VERSION_OVERLAY_ENABLED=true                 # Activer/désactiver l'overlay
VERSION_OVERLAY_FONT_SIZE=48                 # Taille de la police (pixels)
VERSION_OVERLAY_FONT_COLOR="#FFFFFF"         # Couleur du texte (hex)
VERSION_OVERLAY_SHADOW_COLOR="#000000"       # Couleur de l'ombre (hex)
VERSION_OVERLAY_SHADOW_OPACITY=128           # Opacité de l'ombre (0-255)
VERSION_OVERLAY_MARGIN_RIGHT=50              # Marge depuis le bord droit
VERSION_OVERLAY_MARGIN_BOTTOM=50             # Marge depuis le bas
VERSION_OVERLAY_FONT_BOLD=true               # Police en gras
VERSION_OVERLAY_PREFIX="MaxLink "            # Préfixe avant la version

# ===============================================================================
# CONFIGURATION UTILISATEUR SYSTÈME
# ===============================================================================

# Utilisateur principal du Raspberry Pi
SYSTEM_USER="prod"
SYSTEM_USER_HOME="/home/$SYSTEM_USER"

# ===============================================================================
# CONFIGURATION RÉSEAU WIFI
# ===============================================================================

# Réseau WiFi pour les mises à jour
WIFI_SSID="Max"
WIFI_PASSWORD="1234567890"


# Configuration du point d'accès WiFi
AP_SSID="MaxLink-NETWORK"
AP_PASSWORD="MDPsupersecret007"
AP_IP="192.168.4.1"
AP_NETMASK="24"
AP_DHCP_START="192.168.4.10"
AP_DHCP_END="192.168.4.100"

# ===============================================================================
# CONFIGURATION GITHUB
# ===============================================================================

# Configuration du dépôt GitHub pour le dashboard
GITHUB_REPO_URL="https://github.com/B4ckZ/DashboardV3"
GITHUB_BRANCH="main"
GITHUB_DASHBOARD_DIR=""
GITHUB_TOKEN=""

# ===============================================================================
# CONFIGURATION MQTT
# ===============================================================================

# Configuration du broker MQTT
MQTT_USER="mosquitto"
MQTT_PASS="mqtt"
MQTT_PORT="1883"
MQTT_WEBSOCKET_PORT="9001"

# Topics MQTT à ignorer (CORRIGÉ - ajout de la variable manquante)
MQTT_IGNORED_TOPICS=(
    "test/+"
    "debug/+"
    "\$SYS/broker/load/+"
    "\$SYS/broker/subscriptions/+"
    "\$SYS/broker/heap/+"
)

# Convertir en string pour l'export (séparateur |)
MQTT_IGNORED_TOPICS_STRING=$(IFS='|'; echo "${MQTT_IGNORED_TOPICS[*]}")

# ===============================================================================
# CONFIGURATION NGINX
# ===============================================================================

# Configuration du serveur web
NGINX_DASHBOARD_DIR="/var/www/maxlink-dashboard"
NGINX_DASHBOARD_DOMAIN="maxlink-dashboard.local"
NGINX_PORT="80"

# ===============================================================================
# CONFIGURATION FICHIERS SYSTÈME
# ===============================================================================

# Fichiers de configuration système
CONFIG_FILE="/boot/firmware/config.txt"

# Répertoires pour les assets
BG_IMAGE_SOURCE_DIR="assets"
BG_IMAGE_FILENAME="bg.png"
BG_IMAGE_DEST_DIR="/usr/share/backgrounds/maxlink"

# ===============================================================================
# CONFIGURATION INTERFACE GRAPHIQUE
# ===============================================================================

# Configuration de l'environnement de bureau
DESKTOP_FONT="Inter 12"
DESKTOP_BG_COLOR="#000000"
DESKTOP_FG_COLOR="#ECEFF4"
DESKTOP_SHADOW_COLOR="#000000"

# Services disponibles dans l'interface - CORRIGÉ: tous inactifs par défaut
SERVICES_LIST=(
    "update:Update RPI:inactive"
    "ap:Network AP:inactive" 
    "nginx:NginX Web:inactive"
    "mqtt:MQTT BKR:inactive"
    "mqtt_wgs:MQTT WGS:inactive"
    "php_archives:PHP Archives:inactive"
    "orchestrator:Orchestrateur:inactive"
)

# ===============================================================================
# CONFIGURATION DU LOGGING
# ===============================================================================

# Configuration des logs
LOG_TO_CONSOLE_DEFAULT=false
LOG_TO_FILE_DEFAULT=true

# ===============================================================================
# CONFIGURATION RÉSEAU ET SÉCURITÉ
# ===============================================================================

# Timeouts réseau (en secondes)
NETWORK_TIMEOUT=5
PING_COUNT=3
APT_RETRY_MAX_ATTEMPTS=3
APT_RETRY_DELAY=3

# ===============================================================================
# CONFIGURATION AVANCÉE
# ===============================================================================

# Délais d'affichage pour l'interface (en secondes)
DISPLAY_DELAY_STARTUP=2
DISPLAY_DELAY_BETWEEN_STEPS=2

# Configuration ventilateur
FAN_TEMP_MIN=0
FAN_TEMP_ACTIVATE=60
FAN_TEMP_MAX=60

# ===============================================================================
# CONFIGURATION DES STATUTS DES SERVICES
# ===============================================================================

# Fichier de statut pour communication avec l'interface
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"
SERVICES_STATUS_DIR="$(dirname "$SERVICES_STATUS_FILE")"

# Créer le répertoire si nécessaire
[ ! -d "$SERVICES_STATUS_DIR" ] && mkdir -p "$SERVICES_STATUS_DIR"

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

# Fonction pour obtenir l'utilisateur système effectif
get_effective_user() {
    if [ -d "$SYSTEM_USER_HOME" ]; then
        echo "$SYSTEM_USER"
    elif [ -n "$SUDO_USER" ] && [ -d "/home/$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$SYSTEM_USER"
    fi
}

# Fonction pour obtenir le répertoire home effectif
get_effective_user_home() {
    local effective_user=$(get_effective_user)
    echo "/home/$effective_user"
}

# Fonction pour construire les chemins d'assets
get_bg_image_source() {
    echo "${MAXLINK_BASE_DIR:-/media/prod/USBTOOL}/$BG_IMAGE_SOURCE_DIR/$BG_IMAGE_FILENAME"
}

get_bg_image_dest() {
    echo "$BG_IMAGE_DEST_DIR/$BG_IMAGE_FILENAME"
}

# Fonction pour mettre à jour le statut d'un service
update_service_status() {
    local service_id="$1"
    local status="$2"  # "active" ou "inactive"
    
    # S'assurer que le répertoire existe
    mkdir -p "$(dirname "$SERVICES_STATUS_FILE")"
    
    # Créer le fichier de statut s'il n'existe pas
    if [ ! -f "$SERVICES_STATUS_FILE" ]; then
        echo "{}" > "$SERVICES_STATUS_FILE"
    fi
    
    # Mettre à jour le statut via Python pour gérer le JSON proprement
    python3 -c "
import json
import sys
from datetime import datetime

service_id = '$service_id'
status = '$status'

try:
    # Charger les données existantes
    with open('$SERVICES_STATUS_FILE', 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f'Erreur lecture: {e}', file=sys.stderr)
    data = {}

# Mettre à jour
data[service_id] = {
    'status': status,
    'last_update': datetime.now().isoformat()
}

# Sauvegarder
try:
    with open('$SERVICES_STATUS_FILE', 'w') as f:
        json.dump(data, f, indent=2)
    print(f'Statut {service_id} mis à jour: {status}')
except Exception as e:
    print(f'Erreur sauvegarde: {e}', file=sys.stderr)
    sys.exit(1)
"
    
    # Vérifier que la mise à jour a réussi
    if [ $? -eq 0 ]; then
        echo "  ↦ Statut du service $service_id mis à jour: $status"
        return 0
    else
        echo "  ↦ Erreur lors de la mise à jour du statut"
        return 1
    fi
}

# ===============================================================================
# VALIDATION DE LA CONFIGURATION
# ===============================================================================

# Fonction pour valider la configuration
validate_config() {
    local errors=0
    
    [ -z "$WIFI_SSID" ] && echo "ERREUR: WIFI_SSID non défini" && ((errors++))
    [ -z "$AP_SSID" ] && echo "ERREUR: AP_SSID non défini" && ((errors++))
    [ -z "$SYSTEM_USER" ] && echo "ERREUR: SYSTEM_USER non défini" && ((errors++))
    
    if [[ ! "$AP_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "ERREUR: AP_IP ($AP_IP) n'est pas une adresse IP valide"
        ((errors++))
    fi
    
    return $errors
}

# ===============================================================================
# VARIABLES DYNAMIQUES
# ===============================================================================

# Ces variables sont calculées automatiquement
EFFECTIVE_USER=$(get_effective_user)
EFFECTIVE_USER_HOME=$(get_effective_user_home)
BG_IMAGE_SOURCE=$(get_bg_image_source)
BG_IMAGE_DEST=$(get_bg_image_dest)

# ===============================================================================
# EXPORT DES VARIABLES
# ===============================================================================

# Exporter toutes les variables nécessaires
export MAXLINK_VERSION MAXLINK_COPYRIGHT
export VERSION_OVERLAY_ENABLED VERSION_OVERLAY_FONT_SIZE
export VERSION_OVERLAY_FONT_COLOR VERSION_OVERLAY_SHADOW_COLOR VERSION_OVERLAY_SHADOW_OPACITY
export VERSION_OVERLAY_MARGIN_RIGHT VERSION_OVERLAY_MARGIN_BOTTOM
export VERSION_OVERLAY_FONT_BOLD VERSION_OVERLAY_PREFIX
export SYSTEM_USER SYSTEM_USER_HOME
export EFFECTIVE_USER EFFECTIVE_USER_HOME
export WIFI_SSID WIFI_PASSWORD
export AP_SSID AP_PASSWORD AP_IP AP_NETMASK AP_DHCP_START AP_DHCP_END
export GITHUB_REPO_URL GITHUB_BRANCH GITHUB_DASHBOARD_DIR GITHUB_TOKEN
export NGINX_DASHBOARD_DIR NGINX_DASHBOARD_DOMAIN NGINX_PORT
export CONFIG_FILE
export BG_IMAGE_SOURCE_DIR BG_IMAGE_FILENAME BG_IMAGE_DEST_DIR
export BG_IMAGE_SOURCE BG_IMAGE_DEST
export DESKTOP_FONT DESKTOP_BG_COLOR DESKTOP_FG_COLOR DESKTOP_SHADOW_COLOR
export LOG_TO_CONSOLE_DEFAULT LOG_TO_FILE_DEFAULT
export NETWORK_TIMEOUT PING_COUNT APT_RETRY_MAX_ATTEMPTS APT_RETRY_DELAY
export DISPLAY_DELAY_STARTUP DISPLAY_DELAY_BETWEEN_STEPS
export FAN_TEMP_MIN FAN_TEMP_ACTIVATE FAN_TEMP_MAX
export MQTT_USER MQTT_PASS MQTT_PORT MQTT_WEBSOCKET_PORT
export MQTT_IGNORED_TOPICS MQTT_IGNORED_TOPICS_STRING
export SERVICES_LIST
export SERVICES_STATUS_FILE SERVICES_STATUS_DIR

# Export de la fonction update_service_status
export -f update_service_status

# Valider la configuration
if ! validate_config; then
    echo "ATTENTION: Des erreurs de configuration ont été détectées"
fi