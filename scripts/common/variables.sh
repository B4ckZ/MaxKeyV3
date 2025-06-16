#!/bin/bash

# ===============================================================================
# MAXLINK - VARIABLES GLOBALES (VERSION USB LOGS)
# Version modifiée avec logs sur clé USB
# ===============================================================================

# ===============================================================================
# INFORMATIONS DU PROJET
# ===============================================================================

export MAXLINK_VERSION="3.0.0"
export MAXLINK_COPYRIGHT="© 2024 MaxLink Network System"

# ===============================================================================
# CONFIGURATION DE L'OVERLAY DE VERSION
# ===============================================================================

export VERSION_OVERLAY_ENABLED="true"
export VERSION_OVERLAY_FONT_SIZE="14"
export VERSION_OVERLAY_FONT_COLOR="#FFFFFF"
export VERSION_OVERLAY_SHADOW_COLOR="#000000"
export VERSION_OVERLAY_SHADOW_OPACITY="0.5"
export VERSION_OVERLAY_MARGIN_RIGHT="20"
export VERSION_OVERLAY_MARGIN_BOTTOM="20"
export VERSION_OVERLAY_FONT_BOLD="true"
export VERSION_OVERLAY_PREFIX="MaxLink Network"

# ===============================================================================
# DÉTECTION DE BASE
# ===============================================================================

# Déterminer BASE_DIR si pas déjà défini
if [ -z "$BASE_DIR" ]; then
    # Obtenir le répertoire du script actuel
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # BASE_DIR doit pointer vers la racine de la clé USB (3 niveaux au-dessus)
    export BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# ===============================================================================
# CONFIGURATION DES LOGS (NOUVELLE SECTION)
# ===============================================================================

# Détection automatique de la clé USB
USB_MOUNT_POINT=$(df "$BASE_DIR" | tail -1 | awk '{print $6}')

# Dossier de logs sur la clé USB
export USB_LOG_DIR="$USB_MOUNT_POINT/logs"
export LOG_DIR="$USB_LOG_DIR"

# Définir les chemins de logs directement dans le dossier logs
export LOG_BASE="$USB_LOG_DIR"
export LOG_SYSTEM="$LOG_BASE/system"
export LOG_INSTALL="$LOG_BASE/install"
export LOG_WIDGETS="$LOG_BASE/widgets"
export LOG_PYTHON="$LOG_BASE/python"

# Créer la structure des logs sur la clé USB
mkdir -p "$LOG_SYSTEM" "$LOG_INSTALL" "$LOG_WIDGETS" "$LOG_PYTHON" 2>/dev/null || true

# Configuration des logs par défaut
export LOG_TO_CONSOLE_DEFAULT="true"
export LOG_TO_FILE_DEFAULT="true"

# ===============================================================================
# UTILISATEURS SYSTÈME
# ===============================================================================

export SYSTEM_USER="prod"
export SYSTEM_USER_HOME="/home/prod"

# ===============================================================================
# CONFIGURATION WIFI
# ===============================================================================

export WIFI_SSID="prodfloor"
export WIFI_PASSWORD="proditec"

# ===============================================================================
# CONFIGURATION ACCESS POINT
# ===============================================================================

export AP_SSID="MaxLink-NETWORK"
export AP_PASSWORD="maxlink2024"
export AP_IP="192.168.4.1"
export AP_NETMASK="255.255.255.0"
export AP_DHCP_START="192.168.4.2"
export AP_DHCP_END="192.168.4.20"

# ===============================================================================
# CONFIGURATION GITHUB
# ===============================================================================

export GITHUB_REPO_URL="https://github.com/Harvey13/Cp-terminal"
export GITHUB_BRANCH="main"
export GITHUB_DASHBOARD_DIR="DashBoardV1"
export GITHUB_TOKEN=""

# ===============================================================================
# CONFIGURATION NGINX
# ===============================================================================

export NGINX_DASHBOARD_DIR="/var/www/html"
export NGINX_DASHBOARD_DOMAIN="maxlink.local"
export NGINX_PORT="80"

# ===============================================================================
# CONFIGURATION FAN CONTROL
# ===============================================================================

export FAN_TEMP_MIN="40"
export FAN_TEMP_ACTIVATE="45"
export FAN_TEMP_MAX="65"

# ===============================================================================
# CONFIGURATION MQTT
# ===============================================================================

export MQTT_USER="mosquitto"
export MQTT_PASS="mqtt"
export MQTT_PORT="1883"
export MQTT_WEBSOCKET_PORT="9001"

# Topics à ignorer dans les logs MQTT
export MQTT_IGNORED_TOPICS=(
    "rpi/wifi/quality"
    "rpi/mqtt/stats"
    "rpi/cpu/percent"
)
export MQTT_IGNORED_TOPICS_STRING=$(IFS='|'; echo "${MQTT_IGNORED_TOPICS[*]}")

# ===============================================================================
# FICHIERS DE CONFIGURATION
# ===============================================================================

export CONFIG_FILE="/etc/maxlink/maxlink.conf"

# ===============================================================================
# IMAGES ET PERSONNALISATION
# ===============================================================================

export BG_IMAGE_SOURCE_DIR="assets/images"
export BG_IMAGE_FILENAME="bg.jpg"
export BG_IMAGE_DEST_DIR="/usr/share/backgrounds"

# Couleurs du bureau
export DESKTOP_FONT="0xffffff"
export DESKTOP_BG_COLOR="0x2e3440"
export DESKTOP_FG_COLOR="0xd8dee9"
export DESKTOP_SHADOW_COLOR="0x000000"

# ===============================================================================
# TIMEOUTS ET RETRY
# ===============================================================================

export NETWORK_TIMEOUT="10"
export PING_COUNT="3"
export APT_RETRY_MAX_ATTEMPTS="3"
export APT_RETRY_DELAY="5"

# ===============================================================================
# SERVICES
# ===============================================================================

export SERVICES_LIST=(
    "update:Update System:update_install.sh:Version 3.0:Mise à jour et personnalisation système"
    "ap:Access Point:ap_install.sh:Version 1.0:Point d'accès WiFi MaxLink-NETWORK"
    "nginx:Web Server:nginx_install.sh:Version 1.0:Serveur web pour dashboard"
    "mqtt:MQTT Broker:mqtt_install.sh:Version 1.0:Broker MQTT Mosquitto"
    "mqtt_wgs:MQTT Widgets:mqtt_wgs_install.sh:Version 1.0:Widgets MQTT pour monitoring"
    "orchestrator:Orchestrateur:orchestrator_install.sh:Version 1.0:Orchestrateur de démarrage systemd"
)

export SERVICES_STATUS_DIR="/var/lib/maxlink"
export SERVICES_STATUS_FILE="$SERVICES_STATUS_DIR/services_status.json"

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

# Mettre à jour le statut d'un service
update_service_status() {
    local service_id="$1"
    local status="$2"
    local message="${3:-}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Créer le répertoire si nécessaire
    mkdir -p "$SERVICES_STATUS_DIR"
    
    # Créer le fichier s'il n'existe pas
    if [ ! -f "$SERVICES_STATUS_FILE" ]; then
        echo "{}" > "$SERVICES_STATUS_FILE"
    fi
    
    # Utiliser Python pour mettre à jour le JSON
    python3 -c "
import json
import sys

service_id = '$service_id'
status = '$status'
message = '$message'
timestamp = '$timestamp'

try:
    with open('$SERVICES_STATUS_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

data[service_id] = {
    'status': status,
    'message': message,
    'timestamp': timestamp
}

with open('$SERVICES_STATUS_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    
    # Log du changement de statut
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Service $service_id: $status - $message" >> "$LOG_SYSTEM/service_status.log"
}

# Obtenir l'utilisateur effectif
get_effective_user() {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        echo "$SUDO_USER"
    else
        echo "$SYSTEM_USER"
    fi
}

# Obtenir le home de l'utilisateur effectif
get_effective_user_home() {
    local user=$(get_effective_user)
    echo "/home/$user"
}

# Obtenir le chemin source de l'image de fond
get_bg_image_source() {
    echo "$BASE_DIR/$BG_IMAGE_SOURCE_DIR/$BG_IMAGE_FILENAME"
}

# Obtenir le chemin destination de l'image de fond
get_bg_image_dest() {
    echo "$BG_IMAGE_DEST_DIR/$BG_IMAGE_FILENAME"
}

# ===============================================================================
# VALIDATION DE LA CONFIGURATION
# ===============================================================================

# Valider la configuration
validate_config() {
    local errors=0
    
    # Vérifier les chemins critiques
    if [ ! -d "$BASE_DIR" ]; then
        echo "ERREUR: BASE_DIR ($BASE_DIR) n'existe pas"
        ((errors++))
    fi
    
    # Vérifier le point de montage USB
    if [ -z "$USB_MOUNT_POINT" ]; then
        echo "ERREUR: Impossible de détecter le point de montage USB"
        ((errors++))
    fi
    
    # Vérifier l'utilisateur système
    if ! id "$SYSTEM_USER" &>/dev/null; then
        echo "ATTENTION: L'utilisateur système $SYSTEM_USER n'existe pas"
    fi
    
    # Vérifier l'adresse IP AP
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
export USB_MOUNT_POINT USB_LOG_DIR LOG_DIR
export LOG_BASE LOG_SYSTEM LOG_INSTALL LOG_WIDGETS LOG_PYTHON

# Export de la fonction update_service_status
export -f update_service_status

# Valider la configuration
if ! validate_config; then
    echo "ATTENTION: Des erreurs de configuration ont été détectées"
fi