#!/bin/bash

# ===============================================================================
# MAXLINK - CONFIGURATION CENTRALE (VERSION NETTOYÉE)
# Toutes les variables utilisées dans le système
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
VERSION_OVERLAY_MARGIN_RIGHT=50              # Marge depuis le bord droit
VERSION_OVERLAY_MARGIN_BOTTOM=50             # Marge depuis le bas
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

# Configuration du repository GitHub pour le dashboard
GITHUB_REPO_URL="https://github.com/patrickelectronique/maxlink-dashboard"
GITHUB_BRANCH="V3"
GITHUB_DASHBOARD_DIR=""  # Vide = racine de l'archive
GITHUB_TOKEN=""  # Token optionnel pour les repos privés

# ===============================================================================
# CONFIGURATION NGINX
# ===============================================================================

# Dashboard web
NGINX_DASHBOARD_DIR="/var/www/maxlink"
NGINX_DASHBOARD_DOMAIN="maxlink.local"
NGINX_PORT="80"

# ===============================================================================
# CONFIGURATION SYSTÈME
# ===============================================================================

# Fichier de configuration système
CONFIG_FILE="/boot/config.txt"

# Configuration du fond d'écran et bureau
BG_IMAGE_SOURCE_DIR="/media/prod/USBTOOL/assets/images"
BG_IMAGE_FILENAME="wallpaper.jpg"
BG_IMAGE_DEST_DIR="/usr/share/backgrounds"

# Apparence du bureau
DESKTOP_FONT="DejaVu Sans 10"
DESKTOP_BG_COLOR="#2E3440"  # Couleur de fond (Nord0)
DESKTOP_FG_COLOR="#ECEFF4"  # Couleur du texte (Nord6)
DESKTOP_SHADOW_COLOR="#000000"  # Couleur de l'ombre

# ===============================================================================
# CONFIGURATION LOGGING
# ===============================================================================

# Configuration du système de logs
LOG_TO_CONSOLE_DEFAULT=true   # Afficher les logs dans la console
LOG_TO_FILE_DEFAULT=true      # Écrire les logs dans les fichiers

# ===============================================================================
# PARAMÈTRES RÉSEAU
# ===============================================================================

# Timeouts et paramètres de connexion
NETWORK_TIMEOUT=10            # Timeout pour les tests de connexion (secondes)
PING_COUNT=3                  # Nombre de pings pour tester la connexion
APT_RETRY_MAX_ATTEMPTS=3      # Nombre de tentatives pour APT update
APT_RETRY_DELAY=10            # Délai entre les tentatives APT (secondes)

# ===============================================================================
# CONFIGURATION D'AFFICHAGE
# ===============================================================================

# Délais d'affichage (pour les scripts d'installation)
DISPLAY_DELAY_STARTUP=2       # Délai au démarrage (secondes)
DISPLAY_DELAY_BETWEEN_STEPS=3 # Délai entre les étapes (secondes)

# ===============================================================================
# CONFIGURATION MATÉRIEL
# ===============================================================================

# Configuration du ventilateur (températures en degrés Celsius)
FAN_TEMP_MIN=40              # Température minimale pour démarrer le ventilateur
FAN_TEMP_ACTIVATE=45         # Température d'activation normale
FAN_TEMP_MAX=50              # Température maximale (vitesse max)

# ===============================================================================
# CONFIGURATION MQTT
# ===============================================================================

# Paramètres du broker MQTT
MQTT_USER="prod"
MQTT_PASS="1234567890"
MQTT_PORT=1883
MQTT_WEBSOCKET_PORT=9001

# Topics système à ignorer dans le monitoring
MQTT_IGNORED_TOPICS=(
    '$SYS/broker/version'
    '$SYS/broker/timestamp'
    '$SYS/broker/uptime'
    '$SYS/broker/load/bytes/received'
    '$SYS/broker/load/bytes/sent'
    '$SYS/broker/clients/connected'
    '$SYS/broker/clients/total'
    '$SYS/broker/messages/stored'
    '$SYS/broker/messages/received'
    '$SYS/broker/messages/sent'
    '$SYS/broker/subscriptions/count'
    '$SYS/broker/retained messages/count'
    '$SYS/broker/heap/current'
    '$SYS/broker/heap/maximum'
    '$SYS/broker/publish/messages/received'
    '$SYS/broker/publish/messages/sent'
    '$SYS/broker/publish/bytes/received'
    '$SYS/broker/publish/bytes/sent'
    '$SYS/broker/messages/received/1min'
    '$SYS/broker/messages/sent/1min'
    '$SYS/broker/publish/messages/received/1min'
    '$SYS/broker/publish/messages/sent/1min'
    '$SYS/broker/load/messages/received/1min'
    '$SYS/broker/load/messages/sent/1min'
    '$SYS/broker/load/publish/received/1min'
    '$SYS/broker/load/publish/sent/1min'
    '$SYS/broker/load/bytes/received/1min'
    '$SYS/broker/load/bytes/sent/1min'
    '$SYS/broker/load/connections/1min'
    '$SYS/broker/messages/received/5min'
    '$SYS/broker/messages/sent/5min'
    '$SYS/broker/publish/messages/received/5min'
    '$SYS/broker/publish/messages/sent/5min'
    '$SYS/broker/load/messages/received/5min'
    '$SYS/broker/load/messages/sent/5min'
    '$SYS/broker/load/publish/received/5min'
    '$SYS/broker/load/publish/sent/5min'
    '$SYS/broker/load/bytes/received/5min'
    '$SYS/broker/load/bytes/sent/5min'
    '$SYS/broker/load/connections/5min'
    '$SYS/broker/messages/received/15min'
    '$SYS/broker/messages/sent/15min'
    '$SYS/broker/publish/messages/received/15min'
    '$SYS/broker/publish/messages/sent/15min'
    '$SYS/broker/load/messages/received/15min'
    '$SYS/broker/load/messages/sent/15min'
    '$SYS/broker/load/publish/received/15min'
    '$SYS/broker/load/publish/sent/15min'
    '$SYS/broker/load/bytes/received/15min'
    '$SYS/broker/load/bytes/sent/15min'
    '$SYS/broker/load/connections/15min'
)

# Conversion en chaîne pour mosquitto_sub
MQTT_IGNORED_TOPICS_STRING=""
for topic in "${MQTT_IGNORED_TOPICS[@]}"; do
    MQTT_IGNORED_TOPICS_STRING+=" -T \"$topic\""
done

# ===============================================================================
# LISTES DE SERVICES
# ===============================================================================

# Services à monitorer
SERVICES_LIST="mosquitto nginx NetworkManager systemd-networkd wpa_supplicant"

# ===============================================================================
# FICHIERS DE STATUT
# ===============================================================================

# Fichier de statut d'installation des services
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"
SERVICES_STATUS_DIR="$(dirname "$SERVICES_STATUS_FILE")"

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

# Obtenir l'utilisateur effectif (prod ou $SUDO_USER)
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

# Construire le chemin complet de l'image source
get_bg_image_source() {
    echo "$BG_IMAGE_SOURCE_DIR/$BG_IMAGE_FILENAME"
}

# Construire le chemin complet de l'image destination
get_bg_image_dest() {
    echo "$BG_IMAGE_DEST_DIR/$BG_IMAGE_FILENAME"
}

# Fonction de mise à jour du statut (utilisée dans les scripts d'installation)
update_service_status() {
    local service_id="$1"
    local status="$2"
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

# Valider la configuration
validate_config() {
    local errors=0
    
    # Vérifier que les variables essentielles sont définies
    if [ -z "$WIFI_SSID" ]; then
        echo "ERREUR: WIFI_SSID n'est pas défini"
        ((errors++))
    fi
    
    if [ -z "$AP_SSID" ]; then
        echo "ERREUR: AP_SSID n'est pas défini"
        ((errors++))
    fi
    
    # Vérifier que l'IP du point d'accès est valide
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
export VERSION_OVERLAY_FONT_COLOR VERSION_OVERLAY_MARGIN_RIGHT VERSION_OVERLAY_MARGIN_BOTTOM
export VERSION_OVERLAY_PREFIX
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