#!/bin/bash

# ===============================================================================
# MAXLINK - MISE À JOUR SYSTÈME ET CRÉATION DU CACHE (VERSION CORRIGÉE)
# Installation avec mise à jour du statut et vérification dashboard
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$SCRIPT_DIR/../common/variables.sh"
source "$SCRIPT_DIR/../common/logging.sh"
source "$SCRIPT_DIR/../common/packages.sh"
source "$SCRIPT_DIR/../common/wifi_helper.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Mise à jour système et création du cache" "install"

# Configuration réseau
ORIGINAL_CONNECTION=""
BACKUP_CONNECTION="MaxLink-Setup-Temp"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Attente silencieuse
wait_silently() {
    sleep "$1"
}

# Attente avec message
wait_with_message() {
    local seconds=$1
    local message=$2
    echo -n "  ↦ $message"
    for ((i=$seconds; i>0; i--)); do
        echo -n "."
        sleep 1
    done
    echo " ✓"
}

# Sauvegarder l'état réseau actuel
save_network_state() {
    log_info "Sauvegarde de l'état réseau actuel"
    
    # Sauvegarder la connexion WiFi active
    ORIGINAL_CONNECTION=$(nmcli -t -f NAME connection show --active | grep -v "^lo$" | head -n1)
    
    if [ -n "$ORIGINAL_CONNECTION" ]; then
        log_info "Connexion active sauvegardée: $ORIGINAL_CONNECTION"
    else
        log_warn "Aucune connexion active à sauvegarder"
    fi
}

# Restaurer l'état réseau
restore_network_state() {
    log_info "Restauration de l'état réseau"
    
    # Désactiver AP si actif
    if nmcli con show --active | grep -q "$AP_SSID"; then
        log_info "Désactivation de l'AP temporaire"
        nmcli con down "$AP_SSID" >/dev/null 2>&1 || true
    fi
    
    # Restaurer la connexion originale si elle existait
    if [ -n "$ORIGINAL_CONNECTION" ]; then
        log_info "Restauration de la connexion: $ORIGINAL_CONNECTION"
        nmcli con up "$ORIGINAL_CONNECTION" >/dev/null 2>&1 || true
        wait_silently 3
    fi
}

# Vérifier et télécharger le dashboard avec retry
download_dashboard_with_retry() {
    local max_attempts=3
    local attempt=1
    local success=false
    
    DASHBOARD_CACHE_DIR="/var/cache/maxlink/dashboard"
    DASHBOARD_ARCHIVE="$DASHBOARD_CACHE_DIR/dashboard.tar.gz"
    
    # Créer le répertoire de cache pour le dashboard
    mkdir -p "$DASHBOARD_CACHE_DIR"
    
    # Supprimer l'ancienne archive si elle existe
    rm -f "$DASHBOARD_ARCHIVE"
    
    # Construire l'URL de téléchargement
    GITHUB_ARCHIVE_URL="${GITHUB_REPO_URL}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"
    
    echo ""
    echo "◦ Téléchargement du dashboard MaxLink V3..."
    echo "  ↦ URL: $GITHUB_ARCHIVE_URL"
    log_info "Téléchargement du dashboard V3 depuis GitHub"
    
    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        echo ""
        echo "  ↦ Tentative $attempt/$max_attempts..."
        
        # Essayer avec curl d'abord
        if command -v curl >/dev/null 2>&1; then
            echo "  ↦ Utilisation de curl..."
            if curl -L -f -o "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL" 2>/dev/null; then
                success=true
                log_success "Dashboard téléchargé avec curl (tentative $attempt)"
            else
                log_warn "Échec curl tentative $attempt"
            fi
        # Sinon essayer avec wget
        elif command -v wget >/dev/null 2>&1; then
            echo "  ↦ Utilisation de wget..."
            if wget -O "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL" 2>/dev/null; then
                success=true
                log_success "Dashboard téléchargé avec wget (tentative $attempt)"
            else
                log_warn "Échec wget tentative $attempt"
            fi
        else
            echo "  ↦ ERREUR: Ni curl ni wget disponibles ✗"
            log_error "Aucun outil de téléchargement disponible"
            return 1
        fi
        
        # Si échec, attendre avant de réessayer
        if [ "$success" = false ] && [ $attempt -lt $max_attempts ]; then
            echo "  ↦ Échec, nouvelle tentative dans 5 secondes..."
            wait_silently 5
            ((attempt++))
        elif [ "$success" = false ]; then
            ((attempt++))
        fi
    done
    
    # Vérifier le résultat final
    if [ "$success" = true ]; then
        echo ""
        echo "  ↦ Téléchargement réussi ✓"
        
        # Vérifier que le fichier existe et n'est pas vide
        if [ -f "$DASHBOARD_ARCHIVE" ]; then
            local file_size=$(stat -c%s "$DASHBOARD_ARCHIVE" 2>/dev/null || stat -f%z "$DASHBOARD_ARCHIVE" 2>/dev/null || echo "0")
            
            if [ "$file_size" -gt 1000 ]; then
                echo "  ↦ Taille du fichier: $(( file_size / 1024 )) KB"
                
                # Vérifier l'intégrité de l'archive
                if tar -tzf "$DASHBOARD_ARCHIVE" >/dev/null 2>&1; then
                    echo "  ↦ Archive valide ✓"
                    log_success "Archive dashboard valide"
                    
                    # Créer les métadonnées
                    cat > "$DASHBOARD_CACHE_DIR/metadata.json" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "$MAXLINK_VERSION",
    "branch": "$GITHUB_BRANCH",
    "url": "$GITHUB_ARCHIVE_URL",
    "size": $file_size
}
EOF
                    return 0
                else
                    echo "  ↦ ERREUR: Archive corrompue ✗"
                    log_error "Archive dashboard corrompue"
                    rm -f "$DASHBOARD_ARCHIVE"
                    return 1
                fi
            else
                echo "  ↦ ERREUR: Fichier trop petit (${file_size} bytes) ✗"
                log_error "Fichier dashboard trop petit"
                rm -f "$DASHBOARD_ARCHIVE"
                return 1
            fi
        else
            echo "  ↦ ERREUR: Fichier non créé ✗"
            log_error "Fichier dashboard non créé"
            return 1
        fi
    else
        echo ""
        echo "  ↦ ERREUR: Échec du téléchargement après $max_attempts tentatives ✗"
        log_error "Échec définitif du téléchargement du dashboard"
        
        # Proposer une solution alternative
        echo ""
        echo "========================================================================"
        echo "SOLUTION ALTERNATIVE"
        echo "========================================================================"
        echo ""
        echo "Le dashboard n'a pas pu être téléchargé automatiquement."
        echo ""
        echo "Options disponibles :"
        echo ""
        echo "1. Vérifier votre connexion Internet :"
        echo "   - ping -c 3 github.com"
        echo "   - curl -I https://github.com"
        echo ""
        echo "2. Télécharger manuellement sur un PC avec Internet :"
        echo "   - URL: $GITHUB_ARCHIVE_URL"
        echo "   - Copier sur la clé USB dans : cache/dashboard.tar.gz"
        echo ""
        echo "3. Puis copier sur le Raspberry Pi :"
        echo "   sudo cp /media/prod/WERIT/cache/dashboard.tar.gz $DASHBOARD_ARCHIVE"
        echo ""
        echo "4. Relancer nginx_install.sh après avoir copié le fichier"
        echo ""
        echo "========================================================================"
        
        return 1
    fi
}

# Fonction pour ajouter la version sur l'image
add_version_to_image() {
    local source_image="$1"
    local dest_image="$2"
    
    if [ ! -f "$source_image" ]; then
        log_error "Image source non trouvée: $source_image"
        return 1
    fi
    
    log_info "Ajout de la version sur l'image de fond"
    
    # Vérifier si ImageMagick est disponible
    if ! command -v convert >/dev/null 2>&1; then
        log_warn "ImageMagick non disponible, copie simple de l'image"
        cp "$source_image" "$dest_image"
        return 0
    fi
    
    # Si l'overlay est désactivé, copier simplement l'image
    if [ "$VERSION_OVERLAY_ENABLED" != "true" ]; then
        log_info "Overlay désactivé, copie simple de l'image"
        cp "$source_image" "$dest_image"
        return 0
    fi
    
    # Ajouter la version sur l'image
    local text="${VERSION_OVERLAY_PREFIX} v${MAXLINK_VERSION}"
    local font_size="${VERSION_OVERLAY_FONT_SIZE:-14}"
    local font_color="${VERSION_OVERLAY_FONT_COLOR:-#FFFFFF}"
    local shadow_color="${VERSION_OVERLAY_SHADOW_COLOR:-#000000}"
    local margin_right="${VERSION_OVERLAY_MARGIN_RIGHT:-20}"
    local margin_bottom="${VERSION_OVERLAY_MARGIN_BOTTOM:-20}"
    
    # Construire la commande convert
    local convert_cmd="convert '$source_image'"
    
    # Ajouter l'ombre si configurée
    if [ -n "$shadow_color" ]; then
        convert_cmd="$convert_cmd -gravity southeast -fill '$shadow_color' -pointsize $font_size"
        convert_cmd="$convert_cmd -annotate +$((margin_right+1))+$((margin_bottom-1)) '$text'"
    fi
    
    # Ajouter le texte principal
    convert_cmd="$convert_cmd -gravity southeast -fill '$font_color' -pointsize $font_size"
    
    # Gras si demandé
    if [ "$VERSION_OVERLAY_FONT_BOLD" = "true" ]; then
        convert_cmd="$convert_cmd -weight Bold"
    fi
    
    convert_cmd="$convert_cmd -annotate +${margin_right}+${margin_bottom} '$text' '$dest_image'"
    
    # Exécuter la commande
    if eval "$convert_cmd" 2>/dev/null; then
        log_success "Version ajoutée sur l'image"
    else
        cp "$source_image" "$dest_image"
        log_info "Image copiée sans modification"
    fi
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

# Stabilisation initiale
echo "◦ Stabilisation du système après démarrage..."
echo "  ↦ Initialisation des services réseau..."
log_info "Stabilisation du système - attente 10s pour OS frais"
wait_silently 10

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
    wait_silently 3
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
if ! connect_to_wifi; then
    echo "  ↦ Impossible de se connecter au WiFi ✗"
    log_error "Échec de connexion WiFi"
    restore_network_state
    exit 1
fi

echo "  ↦ Connexion établie ✓"
log_success "Connexion WiFi établie"

send_progress 25 "Réseau connecté"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 3 : MISE À JOUR DES SOURCES APT
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 3 : MISE À JOUR DES SOURCES APT"
echo "========================================================================"
echo ""

send_progress 30 "Mise à jour des sources..."

echo "◦ Configuration temporaire du DNS..."
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
echo "  ↦ DNS configuré ✓"
log_info "DNS configuré pour la mise à jour"

echo ""
echo "◦ Mise à jour de la liste des paquets..."
echo "  ↦ Cette opération peut prendre quelques minutes..."

if retry_apt_update; then
    echo "  ↦ Sources APT mises à jour ✓"
    log_success "Mise à jour APT réussie"
else
    echo "  ↦ Échec de la mise à jour APT ✗"
    log_error "Impossible de mettre à jour les sources APT"
    restore_network_state
    exit 1
fi

send_progress 40 "Sources mises à jour"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 4 : INSTALLATION DES PAQUETS ESSENTIELS
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 4 : INSTALLATION DES PAQUETS ESSENTIELS"
echo "========================================================================"
echo ""

send_progress 45 "Installation des paquets..."

# Installer les paquets essentiels en ligne
echo "◦ Installation des paquets de base..."

ESSENTIAL_PACKAGES="curl wget git htop iotop net-tools dnsutils rfkill wireless-tools python3-pip python3-pil"

for package in $ESSENTIAL_PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        echo "  ↦ Installation de $package..."
        if apt-get install -y $package >/dev/null 2>&1; then
            echo "    → $package installé ✓"
            log_success "Paquet installé: $package"
        else
            echo "    → $package échec ⚠"
            log_warn "Échec installation: $package"
        fi
    else
        echo "  ↦ $package déjà installé ✓"
    fi
done

send_progress 55 "Paquets installés"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 5 : CRÉATION DU CACHE OFFLINE
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 5 : CRÉATION DU CACHE POUR MODE OFFLINE"
echo "========================================================================"
echo ""

send_progress 60 "Création du cache..."

# Initialiser le cache de paquets
echo "◦ Initialisation du cache de paquets..."
if init_package_cache; then
    echo "  ↦ Cache initialisé ✓"
    log_success "Cache initialisé avec succès"
else
    echo "  ↦ Erreur d'initialisation du cache ✗"
    log_error "Échec de l'initialisation du cache"
fi

# Attendre avant de télécharger
wait_with_message 3 "Préparation du téléchargement"

# Télécharger tous les paquets définis dans packages.list
echo ""
echo "◦ Téléchargement de tous les paquets MaxLink..."
echo "  ↦ Cette opération peut prendre quelques minutes..."

if download_all_packages; then
    echo ""
    echo "  ↦ Cache de paquets créé avec succès ✓"
    log_success "Tous les paquets ont été téléchargés"
    
    # Afficher les statistiques
    get_cache_stats
else
    echo ""
    echo "  ↦ Certains paquets n'ont pas pu être téléchargés ⚠"
    log_warn "Cache créé partiellement"
fi

# TÉLÉCHARGEMENT DU DASHBOARD V3 AVEC VÉRIFICATION
if ! download_dashboard_with_retry; then
    echo ""
    echo "========================================================================"
    echo "⚠ ATTENTION: Le dashboard n'a pas pu être téléchargé"
    echo "========================================================================"
    echo ""
    echo "L'installation peut continuer mais nginx_install.sh échouera."
    echo "Suivez les instructions ci-dessus pour résoudre ce problème."
    echo ""
    log_error "Dashboard non téléchargé - nginx_install.sh échouera"
    
    # Demander si on continue
    read -p "Continuer malgré l'absence du dashboard ? (o/N) : " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Oo]$ ]]; then
        echo "Installation annulée."
        restore_network_state
        exit 1
    fi
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

# Chercher le fichier config.txt dans plusieurs emplacements possibles
CONFIG_LOCATIONS=("/boot/config.txt" "/boot/firmware/config.txt")
CONFIG_FILE=""

for loc in "${CONFIG_LOCATIONS[@]}"; do
    if [ -f "$loc" ]; then
        CONFIG_FILE="$loc"
        break
    fi
done

if [ -n "$CONFIG_FILE" ]; then
    if ! grep -q "dtparam=fan_temp0" "$CONFIG_FILE"; then
        {
            echo ""
            echo "# Configuration ventilateur MaxLink"
            echo "dtparam=fan_temp0=$FAN_TEMP_MIN"
            echo "dtparam=fan_temp0_hyst=2"
            echo "dtparam=fan_temp1=$FAN_TEMP_ACTIVATE"
            echo "dtparam=fan_temp1_hyst=2"
            echo "dtparam=fan_temp2=$FAN_TEMP_MAX"
            echo "dtparam=fan_temp2_hyst=5"
        } >> "$CONFIG_FILE"
        echo "  ↦ Configuration ajoutée dans $CONFIG_FILE ✓"
        log_success "Configuration ventilateur ajoutée"
    else
        echo "  ↦ Configuration existante ✓"
        log_info "Configuration ventilateur déjà présente"
    fi
else
    echo "  ↦ Fichier config.txt non trouvé ⚠"
    log_warn "Fichier config.txt non trouvé dans les emplacements standards"
fi

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
    echo "  ↦ Image source non trouvée ⚠"
    log_warn "Image source non trouvée: $BG_IMAGE_SOURCE"
fi

# Configuration du bureau pour l'utilisateur
if [ -n "$EFFECTIVE_USER" ] && [ -d "$EFFECTIVE_USER_HOME" ]; then
    echo ""
    echo "◦ Configuration du bureau pour $EFFECTIVE_USER..."
    
    # Créer le répertoire de config si nécessaire
    DESKTOP_CONFIG_DIR="$EFFECTIVE_USER_HOME/.config/pcmanfm/LXDE-pi"
    mkdir -p "$DESKTOP_CONFIG_DIR"
    chown -R $EFFECTIVE_USER:$EFFECTIVE_USER "$EFFECTIVE_USER_HOME/.config"
    
    # Configurer le fond d'écran
    DESKTOP_CONFIG="$DESKTOP_CONFIG_DIR/desktop-items-0.conf"
    if [ -f "$BG_IMAGE_DEST" ]; then
        cat > "$DESKTOP_CONFIG" << EOF
[*]
wallpaper_mode=crop
wallpaper_common=1
wallpaper=$BG_IMAGE_DEST
desktop_bg=$DESKTOP_BG_COLOR
desktop_fg=$DESKTOP_FG_COLOR
desktop_shadow=$DESKTOP_SHADOW_COLOR
desktop_font=Sans 10
show_wm_menu=0
sort_order=0
show_documents=0
show_trash=0
show_mounts=0
EOF
        chown $EFFECTIVE_USER:$EFFECTIVE_USER "$DESKTOP_CONFIG"
        echo "  ↦ Bureau configuré ✓"
        log_success "Configuration bureau appliquée"
    fi
fi

send_progress 90 "Système configuré"
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

# Restaurer l'état réseau initial
echo "◦ Restauration de la configuration réseau..."
restore_network_state
echo "  ↦ Configuration réseau restaurée ✓"

# Réactiver les mises à jour automatiques
echo ""
echo "◦ Réactivation des services système..."
systemctl start apt-daily.timer 2>/dev/null || true
systemctl start apt-daily-upgrade.timer 2>/dev/null || true
echo "  ↦ Services réactivés ✓"

# Résumé final
echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE AVEC SUCCÈS"
echo "========================================================================"
echo ""

# Vérifier spécifiquement le dashboard
if [ -f "$DASHBOARD_ARCHIVE" ]; then
    echo "✓ Système mis à jour"
    echo "✓ Cache de paquets créé"
    echo "✓ Dashboard téléchargé et vérifié"
    echo "✓ Personnalisation appliquée"
    log_success "Installation complète avec dashboard"
else
    echo "✓ Système mis à jour"
    echo "✓ Cache de paquets créé"
    echo "⚠ Dashboard NON téléchargé - nginx_install.sh échouera"
    echo "✓ Personnalisation appliquée"
    log_warn "Installation sans dashboard - nginx échouera"
fi

echo ""
echo "Le système est prêt pour l'installation offline des composants."
echo ""

send_progress 100 "Installation terminée"
log_success "Mise à jour système terminée"

# Retourner un code d'erreur si le dashboard n'est pas téléchargé
if [ ! -f "$DASHBOARD_ARCHIVE" ]; then
    exit 2  # Code spécial pour indiquer succès partiel
fi

exit 0