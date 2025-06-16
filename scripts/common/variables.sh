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
# CONFIGURATION COMPTE SSH ADMIN
# ===============================================================================

# Compte SSH avec accès administrateur complet
SSH_ADMIN_USER="max"
SSH_ADMIN_PASS="localkwery"
SSH_ADMIN_HOME="/home/$SSH_ADMIN_USER"
SSH_ADMIN_SHELL="/bin/bash"
SSH_ADMIN_GROUPS="sudo,adm,www-data,systemd-journal"
SSH_ADMIN_LOG_DIR="/var/log/maxlink/ssh_admin"
SSH_ADMIN_LOG_FILE="$SSH_ADMIN_LOG_DIR/access.log"
SSH_ADMIN_AUDIT_FILE="$SSH_ADMIN_LOG_DIR/audit.log"
SSH_ADMIN_ENABLE_LOGGING=true
SSH_ADMIN_ENABLE_AUDIT=true

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
BG_IMAGE_FILENAME="bg.jpg"
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

# Fonction pour mettre à jour le statut d'un service
update_service_status() {
    local service_id="$1"
    local status="$2"  # "active" ou "inactive"
    local message="${3:-}"
    
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

# Détecter l'utilisateur effectif
get_effective_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$SYSTEM_USER"
    fi
}

# Obtenir le home de l'utilisateur effectif
get_effective_user_home() {
    local user=$(get_effective_user)
    if [ "$user" = "root" ]; then
        echo "/root"
    else
        echo "/home/$user"
    fi
}

# Chemins dynamiques pour l'image de fond
get_bg_image_source() {
    echo "$BASE_DIR/$BG_IMAGE_SOURCE_DIR/$BG_IMAGE_FILENAME"
}

get_bg_image_dest() {
    echo "$BG_IMAGE_DEST_DIR/$BG_IMAGE_FILENAME"
}

# Validation de la configuration
validate_config() {
    local errors=0
    
    # Vérifier les variables critiques
    if [ -z "$SYSTEM_USER" ]; then
        echo "ERREUR: SYSTEM_USER non défini"
        ((errors++))
    fi
    
    if [ -z "$AP_SSID" ]; then
        echo "ERREUR: AP_SSID non défini"
        ((errors++))
    fi
    
    if [ -z "$SSH_ADMIN_USER" ]; then
        echo "ERREUR: SSH_ADMIN_USER non défini"
        ((errors++))
    fi
    
    if [ -z "$SSH_ADMIN_PASS" ]; then
        echo "ERREUR: SSH_ADMIN_PASS non défini"
        ((errors++))
    fi
    
    # Vérifier format IP
    if ! [[ "$AP_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
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
export SSH_ADMIN_USER SSH_ADMIN_PASS SSH_ADMIN_HOME SSH_ADMIN_SHELL
export SSH_ADMIN_GROUPS SSH_ADMIN_LOG_DIR SSH_ADMIN_LOG_FILE SSH_ADMIN_AUDIT_FILE
export SSH_ADMIN_ENABLE_LOGGING SSH_ADMIN_ENABLE_AUDIT
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