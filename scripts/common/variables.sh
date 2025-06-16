#!/bin/bash

# ===============================================================================
# MAXLINK - CONFIGURATION CENTRALE (VERSION NETTOYÉE)
# Toutes les variables sans SSH/FileZilla
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

# Topics MQTT à ignorer
MQTT_IGNORED_TOPICS=(
    "\$SYS/#"
    "homeassistant/#"
    "zigbee2mqtt/bridge/#"
    "frigate/#"
)

# Convertir en string pour utilisation dans les configurations
MQTT_IGNORED_TOPICS_STRING=$(IFS=','; echo "${MQTT_IGNORED_TOPICS[*]}")

# ===============================================================================
# CONFIGURATION NGINX ET DASHBOARD
# ===============================================================================

# Configuration du serveur web NGINX
NGINX_DASHBOARD_DIR="/var/www/dashboard"
NGINX_DASHBOARD_DOMAIN="maxlink.local"
NGINX_PORT="80"

# ===============================================================================
# CONFIGURATION BUREAU ET AFFICHAGE
# ===============================================================================

# Image de fond d'écran
BG_IMAGE_SOURCE_DIR="assets/bg.jpg"
BG_IMAGE_FILENAME="fond_ecran_logo.png"
BG_IMAGE_DEST_DIR="/usr/share/backgrounds"

# Configuration du bureau LXDE
DESKTOP_FONT="Roboto 11"
DESKTOP_BG_COLOR="#2E3440"
DESKTOP_FG_COLOR="#D8DEE9"
DESKTOP_SHADOW_COLOR="#000000"

# ===============================================================================
# CONFIGURATION SYSTÈME
# ===============================================================================

# Fichier de configuration système
CONFIG_FILE="/boot/config.txt"

# Configuration des logs
LOG_BASE="/var/log/maxlink"
LOG_SYSTEM="$LOG_BASE/system"
LOG_INSTALL="$LOG_BASE/install"
LOG_WIDGETS="$LOG_BASE/widgets"
LOG_PYTHON="$LOG_BASE/python"
LOG_SSH="$LOG_BASE/ssh"

# Configuration des logs par défaut
LOG_TO_CONSOLE_DEFAULT=true
LOG_TO_FILE_DEFAULT=true

# ===============================================================================
# CONFIGURATION RÉSEAU ET TIMEOUTS
# ===============================================================================

# Timeouts et tentatives réseau
NETWORK_TIMEOUT=30
PING_COUNT=3
APT_RETRY_MAX_ATTEMPTS=3
APT_RETRY_DELAY=5

# ===============================================================================
# CONFIGURATION MATÉRIEL
# ===============================================================================

# Gestion du ventilateur (températures en Celsius)
FAN_TEMP_MIN=45
FAN_TEMP_ACTIVATE=60
FAN_TEMP_MAX=80

# ===============================================================================
# CONFIGURATION DES SERVICES
# ===============================================================================

# Liste des services gérés par MaxLink
SERVICES_LIST=(
    "mosquitto"          # Broker MQTT
    "nginx"              # Serveur web
    "hostapd"            # Point d'accès WiFi
    "dnsmasq"            # Serveur DNS/DHCP
    "maxlink-mqtt"       # Service MQTT MaxLink
    "maxlink-fan"        # Contrôle du ventilateur
    "maxlink-gpio"       # Gestion des GPIO
    "maxlink-orchestrator" # Orchestrateur principal
)

# Fichier de statut des services
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"
SERVICES_STATUS_DIR="/var/lib/maxlink"

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