#!/bin/bash

# ===============================================================================
# MAXLINK - MISE À JOUR SYSTÈME ET PRÉPARATION CACHE V11
# Installation optimisée avec cache local et gestion réseau améliorée
# Version corrigée avec wallpaper simplifié
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"
source "$BASE_DIR/scripts/common/packages.sh"

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Cache des paquets
CACHE_DIR="/var/cache/maxlink/apt"
CACHE_ARCHIVE_DIR="/var/cache/maxlink/archives"
CACHE_STATUS_FILE="/var/cache/maxlink/cache_status.json"

# Dashboard GitHub
GITHUB_API_URL="https://api.github.com/repos/patrickelectronique/maxlink-dashboard/tarball/$GITHUB_BRANCH"
GITHUB_ARCHIVE_URL="https://github.com/patrickelectronique/maxlink-dashboard/archive/refs/heads/$GITHUB_BRANCH.tar.gz"
DASHBOARD_CACHE_DIR="/var/cache/maxlink/dashboard"
DASHBOARD_ARCHIVE="$DASHBOARD_CACHE_DIR/dashboard.tar.gz"

# ID du service pour la mise à jour du statut
SERVICE_ID="${BASH_SOURCE[0]##*/}"
SERVICE_ID="${SERVICE_ID%.sh}"

# Variables de connexion
SKIP_REBOOT="${SKIP_REBOOT:-false}"  # Par défaut, on fait le reboot

# État du nettoyage APT
APT_CLEANUP_DONE=false

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Mise à jour système et préparation cache V11" "install"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Attente simple
wait_silently() {
    sleep "$1"
}

# Mise à jour du statut du service
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

# Sauvegarder l'état réseau actuel
save_network_state() {
    log_info "Sauvegarde de l'état réseau actuel"
    nmcli connection show --active > /tmp/maxlink_network_state_before 2>/dev/null || true
}

# Restaurer l'état réseau précédent
restore_network_state() {
    log_info "Restauration de l'état réseau précédent"
    
    # Si une connexion MaxLink était active, la déconnecter proprement
    if nmcli connection show --active | grep -q "MaxLink"; then
        log_info "Déconnexion de la connexion MaxLink temporaire"
        nmcli connection down "MaxLink" 2>/dev/null || true
        nmcli connection delete "MaxLink" 2>/dev/null || true
    fi
    
    # Réactiver les connexions qui étaient actives avant
    if [ -f /tmp/maxlink_network_state_before ]; then
        while read -r line; do
            if [[ "$line" =~ ^([^ ]+) ]]; then
                conn_name="${BASH_REMATCH[1]}"
                if [ "$conn_name" != "NAME" ] && [ "$conn_name" != "MaxLink" ]; then
                    log_info "Tentative de réactivation de: $conn_name"
                    nmcli connection up "$conn_name" 2>/dev/null || true
                fi
            fi
        done < /tmp/maxlink_network_state_before
        rm -f /tmp/maxlink_network_state_before
    fi
}

# Établir la connexion au réseau WiFi
establish_network_connection() {
    log_info "Établissement de la connexion réseau"
    
    # Fonction interne de test de connexion
    test_connection() {
        local attempt=0
        while [ $attempt -lt 3 ]; do
            if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
                return 0
            fi
            ((attempt++))
            wait_silently 2
        done
        return 1
    }
    
    # Test initial
    echo "◦ Test de la connexion internet existante..."
    if test_connection; then
        echo "  ↦ Connexion internet déjà active ✓"
        log_info "Connexion internet déjà établie"
        return 0
    fi
    
    echo "  ↦ Pas de connexion active, tentative de connexion au WiFi..."
    
    # Scanner les réseaux disponibles
    echo ""
    echo "◦ Scan des réseaux WiFi disponibles..."
    log_info "Scan des réseaux WiFi"
    
    nmcli device wifi rescan 2>/dev/null || true
    wait_silently 3
    
    # Vérifier si le réseau cible est disponible
    if nmcli device wifi list | grep -q "$WIFI_SSID"; then
        echo "  ↦ Réseau '$WIFI_SSID' détecté ✓"
        log_info "Réseau $WIFI_SSID trouvé"
    else
        echo "  ↦ Réseau '$WIFI_SSID' non trouvé ✗"
        log_error "Réseau $WIFI_SSID non trouvé"
        return 1
    fi
    
    # Supprimer une éventuelle connexion MaxLink existante
    if nmcli connection show | grep -q "MaxLink"; then
        echo "  ↦ Suppression de l'ancienne connexion MaxLink..."
        nmcli connection delete "MaxLink" 2>/dev/null || true
    fi
    
    # Créer la connexion
    echo ""
    echo "◦ Connexion au réseau WiFi '$WIFI_SSID'..."
    log_info "Tentative de connexion à $WIFI_SSID"
    
    if nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" name "MaxLink" 2>/dev/null; then
        echo "  ↦ Connexion établie, vérification..."
        wait_silently 5
        
        if test_connection; then
            echo "  ↦ Connexion internet confirmée ✓"
            log_success "Connexion établie avec succès"
            return 0
        else
            echo "  ↦ Connexion établie mais pas d'accès internet ✗"
            log_error "Pas d'accès internet malgré la connexion WiFi"
            return 1
        fi
    else
        echo "  ↦ Échec de la connexion ✗"
        log_error "Impossible de se connecter à $WIFI_SSID"
        return 1
    fi
}

# Nettoyer et préparer APT de manière sécurisée
safe_apt_cleanup() {
    if [ "$APT_CLEANUP_DONE" = true ]; then
        log_info "Nettoyage APT déjà effectué, skip"
        return 0
    fi
    
    echo "◦ Préparation du système de paquets..."
    log_info "Nettoyage sécurisé d'APT"
    
    # Arrêter les processus APT en cours
    local apt_pids=$(pgrep -f "apt-get|dpkg|apt" || true)
    if [ -n "$apt_pids" ]; then
        echo "  ↦ Arrêt des processus APT en cours..."
        for pid in $apt_pids; do
            kill -TERM "$pid" 2>/dev/null || true
        done
        wait_silently 3
    fi
    
    # Nettoyer les verrous
    rm -f /var/lib/apt/lists/lock 2>/dev/null || true
    rm -f /var/cache/apt/archives/lock 2>/dev/null || true
    rm -f /var/lib/dpkg/lock* 2>/dev/null || true
    
    # Reconfigurer dpkg si nécessaire
    dpkg --configure -a 2>/dev/null || true
    
    echo "  ↦ Système de paquets prêt ✓"
    APT_CLEANUP_DONE=true
    return 0
}

# Mise à jour APT avec retry intelligent
update_apt_lists() {
    log_info "Mise à jour des listes de paquets"
    
    local max_attempts=${APT_RETRY_MAX_ATTEMPTS:-3}
    local attempt=1
    
    # Nettoyage initial si nécessaire
    safe_apt_cleanup
    
    while [ $attempt -le $max_attempts ]; do
        echo "◦ Mise à jour des listes de paquets (tentative $attempt/$max_attempts)..."
        
        # Utiliser un timeout pour éviter les blocages
        if timeout 300 apt-get update -o Acquire::http::Timeout=30 -o Acquire::ftp::Timeout=30 > /tmp/apt_update.log 2>&1; then
            # Vérifier s'il y a eu des erreurs
            if ! grep -E "(^Err:|^E:|Failed)" /tmp/apt_update.log >/dev/null 2>&1; then
                echo "  ↦ Liste des paquets mise à jour ✓"
                log_success "APT update réussi"
                rm -f /tmp/apt_update.log
                return 0
            else
                echo "  ↦ Des erreurs ont été détectées dans la mise à jour ⚠"
                log_warn "Erreurs détectées dans APT update"
            fi
        fi
        
        # En cas d'échec
        if [ $attempt -lt $max_attempts ]; then
            echo "  ↦ Échec, nouvelle tentative dans 10 secondes..."
            log_info "Échec APT update, attente avant retry"
            
            # Nettoyer plus agressivement avant le retry
            apt-get clean
            rm -rf /var/lib/apt/lists/*
            APT_CLEANUP_DONE=true
            
            wait_silently 10
        fi
        
        ((attempt++))
    done
    
    echo "  ↦ Impossible de mettre à jour les listes après $max_attempts tentatives ✗"
    log_error "Échec définitif d'APT update après $max_attempts tentatives"
    return 1
}

# Ajouter la version sur l'image de fond (version simplifiée)
add_version_to_image() {
    local source_image=$1
    local dest_image=$2
    local version_text="${VERSION_OVERLAY_PREFIX}v$MAXLINK_VERSION"
    
    log_info "Ajout de la version $version_text sur l'image de fond"
    
    # Vérifier si l'overlay est activé
    if [ "$VERSION_OVERLAY_ENABLED" != "true" ]; then
        log_info "Overlay de version désactivé, copie simple de l'image"
        cp "$source_image" "$dest_image"
        return 0
    fi
    
    # Si PIL n'est pas disponible, copier simplement l'image
    if ! python3 -c "import PIL" >/dev/null 2>&1; then
        log_info "PIL non disponible, copie simple de l'image"
        cp "$source_image" "$dest_image"
        return 0
    fi
    
    # Script Python simplifié avec indentation correcte
    python3 << 'EOF'
import sys
import os
from PIL import Image, ImageDraw, ImageFont

# Variables depuis l'environnement
source_image = os.environ.get('SOURCE_IMAGE', sys.argv[1] if len(sys.argv) > 1 else '')
dest_image = os.environ.get('DEST_IMAGE', sys.argv[2] if len(sys.argv) > 2 else '')
version_text = os.environ.get('VERSION_TEXT', sys.argv[3] if len(sys.argv) > 3 else '')
font_size = int(os.environ.get('VERSION_OVERLAY_FONT_SIZE', '24'))
font_color = os.environ.get('VERSION_OVERLAY_FONT_COLOR', '#FFFFFF')
margin_right = int(os.environ.get('VERSION_OVERLAY_MARGIN_RIGHT', '10'))
margin_bottom = int(os.environ.get('VERSION_OVERLAY_MARGIN_BOTTOM', '10'))

def hex_to_rgb(hex_color):
    """Convertir une couleur hex en RGB"""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

try:
    # Charger l'image
    img = Image.open(source_image)
    draw = ImageDraw.Draw(img)
    
    # Essayer de charger une police
    font = None
    for font_path in ['/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
                      '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf']:
        if os.path.exists(font_path):
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except:
                pass
    
    # Si aucune police trouvée, utiliser la police par défaut
    if font is None:
        font = ImageFont.load_default()
    
    # Calculer la position du texte
    bbox = draw.textbbox((0, 0), version_text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    x = img.width - text_width - margin_right
    y = img.height - text_height - margin_bottom
    
    # Dessiner l'ombre (optionnel)
    shadow_offset = 2
    draw.text((x + shadow_offset, y + shadow_offset), version_text, 
              font=font, fill=(0, 0, 0, 128))
    
    # Dessiner le texte
    draw.text((x, y), version_text, font=font, fill=hex_to_rgb(font_color))
    
    # Sauvegarder l'image
    img.save(dest_image)
    print("Version ajoutée avec succès")
    sys.exit(0)
    
except Exception as e:
    print(f"Erreur: {str(e)}")
    # En cas d'erreur, copier simplement l'image source
    import shutil
    shutil.copy2(source_image, dest_image)
    sys.exit(1)
EOF
    
    # Passer les variables d'environnement au script Python
    export SOURCE_IMAGE="$source_image"
    export DEST_IMAGE="$dest_image"
    export VERSION_TEXT="$version_text"
    
    if [ $? -eq 0 ]; then
        log_success "Version ajoutée sur l'image"
    else
        cp "$source_image" "$dest_image"
        log_info "Image copiée sans modification (erreur lors de l'ajout)"
    fi
}

# Désactiver le splash screen au démarrage
disable_splash_screen() {
    echo ""
    echo "◦ Désactivation du splash screen..."
    log_info "Désactivation du splash screen"
    
    # Modifier cmdline.txt pour un boot silencieux
    if [ -f "/boot/cmdline.txt" ]; then
        # Sauvegarder l'original
        cp /boot/cmdline.txt /boot/cmdline.txt.backup_$(date +%Y%m%d_%H%M%S)
        
        # Ajouter quiet et supprimer les options de splash si pas déjà présent
        if ! grep -q "quiet" /boot/cmdline.txt; then
            # Lire le contenu actuel et ajouter quiet à la fin
            CMDLINE=$(cat /boot/cmdline.txt | tr -d '\n')
            echo "$CMDLINE quiet" > /boot/cmdline.txt
            echo "  ↦ Mode quiet ajouté ✓"
        else
            echo "  ↦ Mode quiet déjà actif ✓"
        fi
        
        # Supprimer les options de splash screen si présentes
        sed -i 's/splash//g' /boot/cmdline.txt
        sed -i 's/plymouth.ignore-serial-consoles//g' /boot/cmdline.txt
        log_success "cmdline.txt modifié"
    else
        echo "  ↦ Fichier cmdline.txt non trouvé ⚠"
        log_warn "Fichier /boot/cmdline.txt non trouvé"
    fi
    
    # Désactiver le rainbow splash dans config.txt
    if [ -f "$CONFIG_FILE" ]; then
        # Ajouter ou modifier disable_splash
        if grep -q "^disable_splash=" "$CONFIG_FILE"; then
            sed -i 's/^disable_splash=.*/disable_splash=1/' "$CONFIG_FILE"
            echo "  ↦ Rainbow splash déjà configuré, mis à jour ✓"
        else
            echo "disable_splash=1" >> "$CONFIG_FILE"
            echo "  ↦ Rainbow splash désactivé ✓"
        fi
        log_success "Rainbow splash désactivé dans config.txt"
    fi
    
    # Désactiver plymouth si installé
    if systemctl list-unit-files | grep -q plymouth; then
        systemctl mask plymouth-start.service 2>/dev/null || true
        systemctl mask plymouth-read-write.service 2>/dev/null || true
        systemctl mask plymouth-quit-wait.service 2>/dev/null || true
        systemctl mask plymouth-quit.service 2>/dev/null || true
        echo "  ↦ Services Plymouth désactivés ✓"
        log_success "Services Plymouth masqués"
    fi
    
    echo "  ↦ Splash screen désactivé ✓"
    log_info "Configuration splash screen terminée"
}

# Désactiver le Bluetooth
disable_bluetooth() {
    echo ""
    echo "◦ Désactivation du Bluetooth..."
    log_info "Désactivation du Bluetooth"
    
    # Méthode 1: Via rfkill (réversible facilement)
    if command -v rfkill &>/dev/null; then
        rfkill block bluetooth 2>/dev/null || true
        echo "  ↦ Bluetooth désactivé via rfkill ✓"
        log_success "Bluetooth désactivé avec rfkill"
    fi
    
    # Méthode 2: Désactiver les services Bluetooth
    if systemctl list-unit-files | grep -q bluetooth; then
        systemctl stop bluetooth.service 2>/dev/null || true
        systemctl disable bluetooth.service 2>/dev/null || true
        echo "  ↦ Service Bluetooth désactivé ✓"
        log_success "Service Bluetooth désactivé"
    fi
    
    # Méthode 3: Désactiver hciuart si présent (Raspberry Pi)
    if systemctl list-unit-files | grep -q hciuart; then
        systemctl stop hciuart.service 2>/dev/null || true
        systemctl disable hciuart.service 2>/dev/null || true
        echo "  ↦ Service hciuart désactivé ✓"
        log_success "Service hciuart désactivé"
    fi
    
    echo "  ↦ Bluetooth désactivé (réversible) ✓"
    echo "    • Pour réactiver: sudo rfkill unblock bluetooth"
    echo "    • Et: sudo systemctl enable --now bluetooth"
    log_info "Bluetooth désactivé de manière réversible"
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE LA MISE À JOUR SYSTÈME V11 =========="

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    log_error "Privilèges root requis - EUID: $EUID"
    exit 1
fi

# ===============================================================================
# ÉTAPE 1 : PRÉPARATION DU SYSTÈME
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 1 : PRÉPARATION DU SYSTÈME"
echo "========================================================================"
echo ""

send_progress 5 "Préparation du système..."

# Stabilisation initiale plus longue pour OS frais
echo "◦ Stabilisation du système après démarrage..."
echo "  ↦ Initialisation des services réseau..."
log_info "Stabilisation du système - attente 10s pour OS frais"
wait_silently 10  # Plus long pour laisser le système se stabiliser

# Désactiver temporairement les mises à jour automatiques
echo ""
echo "◦ Désactivation temporaire des mises à jour automatiques..."
log_info "Désactivation des mises à jour automatiques"

systemctl stop unattended-upgrades 2>/dev/null || true
systemctl stop apt-daily.timer 2>/dev/null || true
systemctl stop apt-daily-upgrade.timer 2>/dev/null || true

echo "  ↦ Mises à jour automatiques suspendues ✓"

# Sauvegarder l'état réseau actuel
save_network_state

# Vérifier l'interface WiFi
echo ""
echo "◦ Vérification de l'interface WiFi..."
if ip link show wlan0 >/dev/null 2>&1; then
    echo "  ↦ Interface WiFi détectée ✓"
    log_info "Interface WiFi wlan0 détectée"
    log_command "nmcli radio wifi on >/dev/null 2>&1" "Activation WiFi"
    wait_silently 3  # Attendre que le WiFi s'active complètement
    echo "  ↦ WiFi activé ✓"
else
    echo "  ↦ Interface WiFi non disponible ✗"
    log_error "Interface WiFi non disponible"
    exit 1
fi

send_progress 10 "WiFi préparé"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 2 : CONNEXION INITIALE
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 2 : CONNEXION RÉSEAU"
echo "========================================================================"
echo ""

send_progress 15 "Connexion au réseau..."

# Établir la connexion internet
if ! establish_network_connection; then
    echo ""
    echo "⚠ ERREUR : Impossible d'établir une connexion internet"
    echo ""
    echo "Vérifiez :"
    echo "  • Le SSID du réseau : $WIFI_SSID"
    echo "  • Le mot de passe configuré"
    echo "  • La disponibilité du réseau"
    echo ""
    log_error "Échec de connexion réseau - Arrêt du script"
    exit 1
fi

send_progress 25 "Connecté au réseau"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 3 : MISE À JOUR DU SYSTÈME
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 3 : MISE À JOUR DU SYSTÈME"
echo "========================================================================"
echo ""

send_progress 30 "Mise à jour du système..."

# Mise à jour des listes
if ! update_apt_lists; then
    echo "⚠ Impossible de mettre à jour les listes de paquets"
    echo "  Le script continue avec les listes existantes..."
    log_warn "Continuation avec les listes de paquets existantes"
fi

# Installation/Mise à jour des paquets essentiels
echo ""
echo "◦ Installation des paquets essentiels..."
log_info "Installation des paquets système de base"

# Installer les paquets un par un pour mieux gérer les erreurs
for package in python3-pip git curl wget; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        echo "  ↦ Installation de $package..."
        if apt-get install -y $package >/dev/null 2>&1; then
            echo "    ✓ $package installé"
            log_success "$package installé"
        else
            echo "    ⚠ Échec de l'installation de $package"
            log_warn "Échec installation $package"
        fi
    else
        echo "  ↦ $package déjà installé ✓"
    fi
done

# Installation de Pillow pour l'overlay de version
echo ""
echo "◦ Installation de Pillow pour l'affichage de version..."
if pip3 install --no-cache-dir Pillow >/dev/null 2>&1; then
    echo "  ↦ Pillow installé ✓"
    log_success "Pillow installé"
else
    echo "  ↦ Pillow non installé (overlay indisponible) ⚠"
    log_warn "Installation Pillow échouée"
fi

send_progress 50 "Paquets installés"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 4 : CRÉATION DU CACHE
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 4 : CRÉATION DU CACHE DE PAQUETS"
echo "========================================================================"
echo ""

send_progress 55 "Création du cache..."

# Créer les répertoires de cache
echo "◦ Création de la structure du cache..."
mkdir -p "$CACHE_DIR"
mkdir -p "$CACHE_ARCHIVE_DIR"
mkdir -p "$DASHBOARD_CACHE_DIR"
echo "  ↦ Structure créée ✓"
log_info "Structure de cache créée"

# Télécharger les paquets nécessaires
echo ""
echo "◦ Téléchargement des paquets pour le cache..."
log_info "Téléchargement des paquets dans le cache"

# Nettoyer le cache APT avant
apt-get clean

# Télécharger tous les paquets définis dans packages.sh
if download_all_packages "$CACHE_ARCHIVE_DIR"; then
    echo "  ↦ Paquets téléchargés dans le cache ✓"
    log_success "Cache de paquets créé avec succès"
else
    echo "  ↦ Certains paquets n'ont pas pu être téléchargés ⚠"
    log_warn "Cache de paquets partiellement créé"
fi

# Créer l'index du cache
echo ""
echo "◦ Création de l'index du cache..."
(cd "$CACHE_ARCHIVE_DIR" && dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz)
echo "  ↦ Index créé ✓"
log_info "Index Packages.gz créé"

# Créer les métadonnées du cache
create_cache_metadata() {
    local total_size=$(du -sh "$CACHE_ARCHIVE_DIR" 2>/dev/null | cut -f1)
    local package_count=$(ls -1 "$CACHE_ARCHIVE_DIR"/*.deb 2>/dev/null | wc -l)
    
    cat > "$CACHE_STATUS_FILE" << EOF
{
    "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "$MAXLINK_VERSION",
    "total_size": "$total_size",
    "package_count": $package_count,
    "packages": {
        "system": $(echo "${SYSTEM_PACKAGES[@]}" | jq -R -s -c 'split(" ")'),
        "network": $(echo "${NETWORK_PACKAGES[@]}" | jq -R -s -c 'split(" ")'),
        "web": $(echo "${WEB_PACKAGES[@]}" | jq -R -s -c 'split(" ")'),
        "mqtt": $(echo "${MQTT_PACKAGES[@]}" | jq -R -s -c 'split(" ")'),
        "monitoring": $(echo "${MONITORING_PACKAGES[@]}" | jq -R -s -c 'split(" ")'),
        "python": $(echo "${PYTHON_PACKAGES[@]}" | jq -R -s -c 'split(" ")')
    }
}
EOF
}

create_cache_metadata
echo "  ↦ Métadonnées créées ✓"
log_info "Métadonnées du cache créées"

send_progress 65 "Cache créé"

# ===============================================================================
# ÉTAPE 5 : TÉLÉCHARGEMENT DU DASHBOARD
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : TÉLÉCHARGEMENT DU DASHBOARD V3"
echo "========================================================================"
echo ""

send_progress 70 "Téléchargement du dashboard..."

echo "◦ Téléchargement du dashboard depuis GitHub..."
echo "  ↦ Branche: $GITHUB_BRANCH"
log_info "Téléchargement dashboard depuis GitHub - branche: $GITHUB_BRANCH"

# Utiliser curl ou wget selon disponibilité
if command -v curl &>/dev/null; then
    if curl -L -o "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL" 2>/dev/null; then
        echo "  ↦ Dashboard téléchargé ✓"
        log_success "Dashboard téléchargé avec curl"
    else
        echo "  ↦ Erreur lors du téléchargement ✗"
        log_error "Échec du téléchargement du dashboard"
    fi
elif command -v wget &>/dev/null; then
    if wget -q -O "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL"; then
        echo "  ↦ Dashboard téléchargé ✓"
        log_success "Dashboard téléchargé avec wget"
    else
        echo "  ↦ Erreur lors du téléchargement ✗"
        log_error "Échec du téléchargement du dashboard"
    fi
else
    echo "  ↦ Ni curl ni wget disponibles ✗"
    log_error "Aucun outil de téléchargement disponible"
fi

# Vérifier que l'archive est valide
if [ -f "$DASHBOARD_ARCHIVE" ] && tar -tzf "$DASHBOARD_ARCHIVE" >/dev/null 2>&1; then
    echo "  ↦ Archive dashboard valide ✓"
    log_success "Archive dashboard valide"
    
    # Créer aussi les métadonnées pour le dashboard
    cat > "$DASHBOARD_CACHE_DIR/metadata.json" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "$MAXLINK_VERSION",
    "branch": "$GITHUB_BRANCH",
    "url": "$GITHUB_ARCHIVE_URL"
}
EOF
else
    echo "  ↦ Archive dashboard corrompue ✗"
    log_error "Archive dashboard corrompue"
    rm -f "$DASHBOARD_ARCHIVE"
fi

# Nettoyage APT
echo ""
echo "◦ Nettoyage du système..."
log_command "apt-get autoremove -y >/dev/null 2>&1" "APT autoremove"
log_command "apt-get autoclean >/dev/null 2>&1" "APT autoclean"
echo "  ↦ Système nettoyé ✓"

send_progress 75 "Cache créé"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 6 : CONFIGURATION DU SYSTÈME
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 6 : CONFIGURATION DU SYSTÈME"
echo "========================================================================"
echo ""

send_progress 80 "Configuration du système..."

# Configuration du refroidissement
echo "◦ Configuration du ventilateur..."
log_info "Configuration du ventilateur"

if [ -f "$CONFIG_FILE" ]; then
    if ! grep -q "dtparam=fan_temp0" "$CONFIG_FILE"; then
        {
            echo ""
            echo "# Configuration ventilateur MaxLink"
            echo "dtparam=fan_temp0=$FAN_TEMP_MIN"
            echo "dtparam=fan_temp1=$FAN_TEMP_ACTIVATE"
            echo "dtparam=fan_temp2=$FAN_TEMP_MAX"
        } >> "$CONFIG_FILE"
        echo "  ↦ Configuration ajoutée ✓"
        log_success "Configuration ventilateur ajoutée"
    else
        echo "  ↦ Configuration existante ✓"
        log_info "Configuration ventilateur déjà présente"
    fi
else
    echo "  ↦ Fichier config.txt non trouvé ⚠"
    log_warn "Fichier $CONFIG_FILE non trouvé"
fi

# Désactivation du splash screen
disable_splash_screen

# Désactivation du Bluetooth
disable_bluetooth

# Personnalisation de l'interface
echo ""
echo "◦ Personnalisation de l'interface..."
log_info "Installation du fond d'écran personnalisé"

# Créer le répertoire des fonds d'écran
mkdir -p "$BG_IMAGE_DEST_DIR"

# Copier le fond d'écran avec ajout de version
if [ -f "$BG_IMAGE_SOURCE" ]; then
    add_version_to_image "$BG_IMAGE_SOURCE" "$BG_IMAGE_DEST"
    echo "  ↦ Fond d'écran installé ✓"
else
    echo "  ↦ Fond d'écran source non trouvé ⚠"
    log_warn "Fond d'écran source non trouvé: $BG_IMAGE_SOURCE"
fi

# Configuration bureau LXDE
if [ -d "$EFFECTIVE_USER_HOME/.config" ]; then
    mkdir -p "$EFFECTIVE_USER_HOME/.config/pcmanfm/LXDE-pi"
    
    cat > "$EFFECTIVE_USER_HOME/.config/pcmanfm/LXDE-pi/desktop-items-0.conf" << EOF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=$BG_IMAGE_DEST
desktop_bg=$DESKTOP_BG_COLOR
desktop_fg=$DESKTOP_FG_COLOR
desktop_shadow=$DESKTOP_SHADOW_COLOR
desktop_font=$DESKTOP_FONT
show_wm_menu=0
show_documents=0
show_trash=0
show_mounts=0
EOF
    
    chown -R $EFFECTIVE_USER:$EFFECTIVE_USER "$EFFECTIVE_USER_HOME/.config"
    echo "  ↦ Bureau configuré ✓"
    log_success "Configuration bureau LXDE appliquée"
fi

send_progress 90 "Configuration terminée"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 7 : FINALISATION
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 7 : FINALISATION"
echo "========================================================================"
echo ""

send_progress 95 "Finalisation..."

# Réactiver les mises à jour automatiques
echo "◦ Réactivation des mises à jour automatiques..."
systemctl start apt-daily.timer 2>/dev/null || true
systemctl start apt-daily-upgrade.timer 2>/dev/null || true
echo "  ↦ Services de mise à jour réactivés ✓"
log_info "Services de mise à jour réactivés"

# Restaurer l'état réseau
echo ""
echo "◦ Restauration de l'état réseau..."
restore_network_state
echo "  ↦ État réseau restauré ✓"

# Fonction pour obtenir les statistiques du cache
get_cache_stats() {
    if [ -f "$CACHE_STATUS_FILE" ]; then
        local total_size=$(jq -r '.total_size' "$CACHE_STATUS_FILE" 2>/dev/null || echo "N/A")
        local package_count=$(jq -r '.package_count' "$CACHE_STATUS_FILE" 2>/dev/null || echo "0")
        echo "  • Taille totale : $total_size"
        echo "  • Nombre de paquets : $package_count"
        echo "  • Dashboard : $([ -f "$DASHBOARD_ARCHIVE" ] && echo "Téléchargé ✓" || echo "Non disponible ✗")"
    fi
}

# MISE À JOUR DU STATUT DU SERVICE
if [ -n "$SERVICE_ID" ]; then
    echo ""
    echo "◦ Mise à jour du statut du service..."
    update_service_status "$SERVICE_ID" "active"
    echo "  ↦ Statut du service mis à jour ✓"
    log_info "Statut du service $SERVICE_ID mis à jour: active"
fi

send_progress 100 "Mise à jour terminée !"

echo ""
echo "◦ Mise à jour terminée avec succès !"
echo "  ↦ Version: v$MAXLINK_VERSION"
echo "  ↦ Système à jour et configuré"
echo "  ↦ Cache de paquets créé pour installation offline"
echo "  ↦ Dashboard V3 téléchargé"
echo "  ↦ Splash screen désactivé"
echo "  ↦ Bluetooth désactivé (réversible)"
log_success "Mise à jour système terminée - Version: v$MAXLINK_VERSION"

# Afficher le résumé du cache
echo ""
echo "◦ Résumé du cache créé :"
get_cache_stats

# Vérifier si on doit faire un reboot
if [ "$SKIP_REBOOT" != "true" ]; then
    echo ""
    echo "  ↦ Redémarrage du système prévu dans 15 secondes..."
    echo ""
    
    log_info "Redémarrage du système prévu dans 15 secondes"
    sleep 15
    
    log_info "Redémarrage du système"
    reboot
else
    echo ""
    echo "  ↦ Redémarrage différé (installation complète en cours)"
    echo ""
    log_info "Redémarrage différé - SKIP_REBOOT=true"
fi