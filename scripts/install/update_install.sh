#!/bin/bash

# ===============================================================================
# MAXLINK - SCRIPT DE MISE À JOUR DU SYSTÈME LINUX
# Version corrigée avec mise à jour du statut et retry dashboard
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
init_logging "Mise à jour système MaxLink"

# Variables pour le contrôle du processus
AP_WAS_ACTIVE=false
APT_CLEANUP_DONE=false

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Attente simple avec message
wait_with_message() {
    local seconds=$1
    local message=$2
    echo "  ↦ $message (${seconds}s)..."
    log_info "$message - attente ${seconds}s"
    sleep "$seconds"
}

# Attente simple silencieuse
wait_silently() {
    sleep "$1"
}

# Fonction pour attendre qu'APT soit libre
wait_for_apt() {
    local max_wait=300  # Maximum 5 minutes d'attente
    local waited=0
    
    echo "◦ Vérification de l'état d'APT..."
    log_info "Vérification de l'état d'APT"
    
    # Vérifier tous les verrous possibles
    while [ $waited -lt $max_wait ]; do
        # Vérifier si APT ou DPKG sont actifs
        if fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
           fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
           fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
           fuser /var/cache/apt/archives/lock >/dev/null 2>&1; then
            
            if [ $waited -eq 0 ]; then
                echo "  ↦ APT est occupé, attente qu'il termine..."
                log_info "APT occupé détecté, attente"
            fi
            
            # Afficher un point toutes les 10 secondes
            if [ $((waited % 10)) -eq 0 ] && [ $waited -gt 0 ]; then
                echo -n "."
            fi
            
            sleep 1
            ((waited++))
        else
            if [ $waited -gt 0 ]; then
                echo ""  # Nouvelle ligne après les points
                echo "  ↦ APT est maintenant libre ✓"
                log_info "APT libre après ${waited}s d'attente"
            else
                echo "  ↦ APT est libre ✓"
                log_info "APT libre immédiatement"
            fi
            return 0
        fi
    done
    
    echo ""
    echo "  ↦ Timeout: APT toujours occupé après ${max_wait}s ⚠"
    log_warn "Timeout APT après ${max_wait}s"
    return 1
}

# Nettoyer proprement APT
clean_apt_properly() {
    echo "◦ Nettoyage sécurisé du système de paquets..."
    log_info "Début du nettoyage APT sécurisé"
    
    # 1. D'abord, attendre qu'APT soit libre
    if ! wait_for_apt; then
        echo "  ↦ Forçage du nettoyage APT..."
        log_warn "Forçage du nettoyage APT nécessaire"
        
        # Arrêter les services qui pourraient utiliser APT
        systemctl stop unattended-upgrades.service 2>/dev/null || true
        systemctl stop apt-daily.service 2>/dev/null || true
        systemctl stop apt-daily-upgrade.service 2>/dev/null || true
        
        wait_silently 3
    fi
    
    # 2. Nettoyer les processus zombies s'il y en a
    echo "  ↦ Nettoyage des processus zombies..."
    log_info "Nettoyage des processus zombies"
    
    # Terminer proprement (SIGTERM) au lieu de tuer brutalement (SIGKILL)
    pkill -15 apt 2>/dev/null || true
    pkill -15 dpkg 2>/dev/null || true
    
    # Attendre un peu pour la terminaison propre
    wait_silently 2
    
    # 3. Supprimer les verrous uniquement s'ils sont orphelins
    echo "  ↦ Vérification des verrous orphelins..."
    log_info "Vérification des verrous orphelins"
    
    for lock in /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
        if [ -f "$lock" ] && ! fuser "$lock" >/dev/null 2>&1; then
            echo "    • Suppression du verrou orphelin: $lock"
            log_info "Suppression verrou orphelin: $lock"
            rm -f "$lock"
        fi
    done
    
    # 4. Reconfigurer dpkg si nécessaire
    echo "  ↦ Reconfiguration de dpkg..."
    log_command "dpkg --configure -a" "Configuration dpkg"
    
    # 5. Nettoyer le cache APT si corrompu
    if [ -d "/var/lib/apt/lists/partial" ]; then
        local partial_files=$(ls -1 /var/lib/apt/lists/partial 2>/dev/null | wc -l)
        if [ $partial_files -gt 0 ]; then
            echo "  ↦ Nettoyage des fichiers partiels corrompus ($partial_files fichiers)..."
            log_info "Nettoyage de $partial_files fichiers partiels"
            rm -rf /var/lib/apt/lists/*
            APT_CLEANUP_DONE=true
        fi
    fi
    
    echo "  ↦ Système de paquets nettoyé ✓"
    log_success "Nettoyage APT terminé"
    
    # Pause de sécurité
    wait_silently 2
}

# Mise à jour APT sécurisée avec retry
safe_apt_update() {
    local max_attempts=3
    local attempt=1
    
    echo "◦ Mise à jour de la liste des paquets..."
    log_info "Début de la mise à jour APT"
    
    while [ $attempt -le $max_attempts ]; do
        echo "  ↦ Tentative $attempt/$max_attempts..."
        log_info "Tentative APT update $attempt/$max_attempts"
        
        # Si on a nettoyé les listes, on doit tout retélécharger
        if [ "$APT_CLEANUP_DONE" = true ]; then
            echo "    • Reconstruction complète du cache APT..."
            log_info "Reconstruction complète du cache APT"
        fi
        
        if apt-get update -y 2>&1 | tee /tmp/apt_update.log; then
            # Vérifier qu'il n'y a pas d'erreurs dans la sortie
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

# Télécharger le dashboard avec retry
download_dashboard_with_retry() {
    local max_attempts=3
    local attempt=1
    local success=false
    
    DASHBOARD_CACHE_DIR="/var/cache/maxlink/dashboard"
    DASHBOARD_ARCHIVE="$DASHBOARD_CACHE_DIR/dashboard.tar.gz"
    
    # Créer le répertoire de cache pour le dashboard
    mkdir -p "$DASHBOARD_CACHE_DIR"
    
    # Construire l'URL de téléchargement
    GITHUB_ARCHIVE_URL="${GITHUB_REPO_URL}/archive/refs/heads/${GITHUB_BRANCH}.tar.gz"
    
    echo "◦ Téléchargement du dashboard MaxLink V3..."
    log_info "Début du téléchargement du dashboard V3"
    
    while [ $attempt -le $max_attempts ] && [ "$success" = false ]; do
        echo "  ↦ Tentative $attempt/$max_attempts..."
        log_info "Tentative téléchargement dashboard $attempt/$max_attempts"
        
        # Supprimer l'ancienne archive si elle existe
        rm -f "$DASHBOARD_ARCHIVE"
        
        # Télécharger avec curl ou wget
        if command -v curl >/dev/null 2>&1; then
            if curl -L -o "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL" 2>/tmp/dashboard_download.log; then
                echo "    • Téléchargement terminé (curl)"
                log_info "Téléchargement curl terminé"
            else
                echo "    • Erreur lors du téléchargement (curl) ⚠"
                log_warn "Erreur téléchargement curl: $(cat /tmp/dashboard_download.log 2>/dev/null)"
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -O "$DASHBOARD_ARCHIVE" "$GITHUB_ARCHIVE_URL" 2>/tmp/dashboard_download.log; then
                echo "    • Téléchargement terminé (wget)"
                log_info "Téléchargement wget terminé"
            else
                echo "    • Erreur lors du téléchargement (wget) ⚠"
                log_warn "Erreur téléchargement wget: $(cat /tmp/dashboard_download.log 2>/dev/null)"
            fi
        else
            echo "  ↦ Ni curl ni wget disponibles ✗"
            log_error "Aucun outil de téléchargement disponible"
            return 1
        fi
        
        # Vérifier que l'archive existe et a une taille raisonnable
        if [ -f "$DASHBOARD_ARCHIVE" ]; then
            local file_size=$(stat -c%s "$DASHBOARD_ARCHIVE" 2>/dev/null || echo "0")
            echo "    • Taille du fichier: $(( file_size / 1024 )) KB"
            
            if [ $file_size -lt 1000 ]; then
                echo "    • Fichier trop petit, probablement corrompu ⚠"
                log_warn "Fichier dashboard trop petit: $file_size octets"
            else
                # Vérifier que l'archive est valide
                echo "    • Vérification de l'archive..."
                if tar -tzf "$DASHBOARD_ARCHIVE" >/dev/null 2>&1; then
                    echo "  ↦ Archive dashboard valide ✓"
                    log_success "Archive dashboard valide"
                    success=true
                    
                    # Créer les métadonnées
                    cat > "$DASHBOARD_CACHE_DIR/metadata.json" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "$MAXLINK_VERSION",
    "branch": "$GITHUB_BRANCH",
    "url": "$GITHUB_ARCHIVE_URL",
    "size": $file_size,
    "attempts": $attempt
}
EOF
                else
                    echo "    • Archive corrompue ⚠"
                    log_warn "Archive dashboard corrompue"
                    rm -f "$DASHBOARD_ARCHIVE"
                fi
            fi
        else
            echo "    • Fichier non créé ⚠"
            log_warn "Fichier dashboard non créé"
        fi
        
        # Si échec et pas la dernière tentative
        if [ "$success" = false ] && [ $attempt -lt $max_attempts ]; then
            echo "  ↦ Nouvelle tentative dans 15 secondes..."
            log_info "Attente avant nouvelle tentative dashboard"
            wait_silently 15
        fi
        
        ((attempt++))
    done
    
    # Nettoyer les fichiers temporaires
    rm -f /tmp/dashboard_download.log
    
    if [ "$success" = true ]; then
        echo "  ↦ Dashboard téléchargé avec succès ✓"
        log_success "Dashboard téléchargé après $((attempt-1)) tentative(s)"
        return 0
    else
        echo "  ↦ Impossible de télécharger le dashboard après $max_attempts tentatives ✗"
        log_error "Échec définitif du téléchargement dashboard"
        return 1
    fi
}

# Ajouter la version sur l'image de fond avec configuration avancée
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
    
    # Script Python avec configuration avancée
    python3 << EOF
import sys
import os
from PIL import Image, ImageDraw, ImageFont

def hex_to_rgb(hex_color):
    """Convertir une couleur hex en RGB"""
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

try:
    # Charger l'image
    img = Image.open("$source_image")
    
    # Si l'image n'a pas de canal alpha, la convertir en RGBA
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Créer un overlay transparent pour le texte
    txt_layer = Image.new('RGBA', img.size, (255, 255, 255, 0))
    draw = ImageDraw.Draw(txt_layer)
    
    # Configuration
    font_size = $VERSION_OVERLAY_FONT_SIZE
    margin_right = $VERSION_OVERLAY_MARGIN_RIGHT
    margin_bottom = $VERSION_OVERLAY_MARGIN_BOTTOM
    text_color = hex_to_rgb("$VERSION_OVERLAY_FONT_COLOR")
    shadow_color = hex_to_rgb("$VERSION_OVERLAY_SHADOW_COLOR")
    shadow_opacity = $VERSION_OVERLAY_SHADOW_OPACITY
    is_bold = "$VERSION_OVERLAY_FONT_BOLD" == "true"
    
    # Essayer de charger une police système
    font = None
    font_paths = [
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if is_bold else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if is_bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf" if is_bold else "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
    ]
    
    for font_path in font_paths:
        if os.path.exists(font_path):
            try:
                font = ImageFont.truetype(font_path, font_size)
                break
            except:
                pass
    
    # Si aucune police trouvée, utiliser la police par défaut
    if font is None:
        font = ImageFont.load_default()
        print("Utilisation de la police par défaut")
    
    # Obtenir la taille du texte
    if font != ImageFont.load_default():
        bbox = draw.textbbox((0, 0), "$version_text", font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
    else:
        # Pour la police par défaut, estimation
        text_width = len("$version_text") * 10
        text_height = 15
    
    # Calculer la position (ancrage coin bas-droit)
    x = img.width - margin_right - text_width
    y = img.height - margin_bottom - text_height
    
    # Dessiner l'ombre avec opacité
    shadow_offset = max(2, int(font_size / 20))
    if font != ImageFont.load_default():
        # Ombre avec transparence
        for offset_x in range(-shadow_offset, shadow_offset + 1):
            for offset_y in range(-shadow_offset, shadow_offset + 1):
                if offset_x != 0 or offset_y != 0:
                    draw.text(
                        (x + offset_x, y + offset_y), 
                        "$version_text", 
                        font=font, 
                        fill=shadow_color + (shadow_opacity,)
                    )
    
    # Dessiner le texte principal
    draw.text((x, y), "$version_text", font=font, fill=text_color + (255,))
    
    # Composer l'image finale
    out = Image.alpha_composite(img, txt_layer)
    
    # Sauvegarder (convertir en RGB si nécessaire pour JPEG)
    if dest_image.lower().endswith('.jpg') or dest_image.lower().endswith('.jpeg'):
        out = out.convert('RGB')
    
    out.save("$dest_image", quality=95)
    print("Version ajoutée avec succès")
    
except Exception as e:
    print(f"Erreur: {e}")
    import shutil
    shutil.copy2("$source_image", "$dest_image")
EOF
    
    if [ $? -eq 0 ]; then
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
if ! ensure_internet_connection; then
    echo "  ↦ Impossible d'établir la connexion ✗"
    log_error "Échec de la connexion réseau"
    exit 1
fi

# Attendre que la connexion soit stable
wait_with_message 5 "Stabilisation de la connexion"

send_progress 30 "Connexion établie"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 3 : SYNCHRONISATION DE L'HORLOGE
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 3 : SYNCHRONISATION HORLOGE"
echo "========================================================================"
echo ""

send_progress 35 "Synchronisation de l'horloge..."

echo "◦ Synchronisation de l'horloge système..."
log_info "Synchronisation NTP"

if command -v timedatectl >/dev/null 2>&1; then
    log_command "timedatectl set-ntp true" "Activation NTP"
    
    echo "  ↦ Attente de la synchronisation NTP..."
    log_info "Attente synchronisation NTP - 15s"
    wait_silently 15  # Plus de temps pour la synchro
    
    # Vérifier plusieurs fois
    local sync_attempts=0
    while [ $sync_attempts -lt 3 ]; do
        if timedatectl status | grep -q "synchronized: yes"; then
            echo "  ↦ Horloge synchronisée ✓"
            log_success "Synchronisation NTP confirmée"
            break
        else
            echo "  ↦ Synchronisation en cours... (tentative $((sync_attempts+1))/3)"
            log_info "Attente supplémentaire pour NTP"
            wait_silently 5
            ((sync_attempts++))
        fi
    done
    
    echo "  ↦ Date/Heure: $(date '+%d/%m/%Y %H:%M:%S')"
    log_info "Heure synchronisée: $(date)"
else
    echo "  ↦ timedatectl non disponible ⚠"
    log_warn "timedatectl non disponible"
fi

send_progress 40 "Horloge synchronisée"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 4 : MISE À JOUR DE SÉCURITÉ
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 4 : MISE À JOUR DE SÉCURITÉ"
echo "========================================================================"
echo ""

send_progress 45 "Préparation des mises à jour..."

# Nettoyer APT proprement
clean_apt_properly

# Attendre un peu après le nettoyage
wait_with_message 3 "Stabilisation après nettoyage"

# Mise à jour des dépôts avec retry
if ! safe_apt_update; then
    echo "  ↦ Impossible de mettre à jour les dépôts ✗"
    echo "  ↦ Continuation sans mises à jour de sécurité ⚠"
    log_error "APT update impossible, continuation sans mises à jour"
fi

send_progress 55 "Installation des mises à jour critiques..."

# Installation des mises à jour de sécurité critiques uniquement
echo ""
echo "◦ Installation des mises à jour de sécurité critiques..."
log_info "Installation des paquets critiques uniquement"

# Liste des paquets critiques
CRITICAL_PACKAGES="openssl libssl* sudo systemd apt dpkg libc6 libpam* ca-certificates tzdata"

# Installer uniquement les mises à jour critiques avec gestion d'erreur
if log_command "DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade --allow-unauthenticated $CRITICAL_PACKAGES" "Mise à jour sécurité"; then
    echo "  ↦ Mises à jour de sécurité installées ✓"
    log_success "Mises à jour de sécurité installées"
else
    echo "  ↦ Certaines mises à jour ont échoué ⚠"
    log_warn "Certaines mises à jour ont échoué"
    
    # Essayer de réparer
    echo "  ↦ Tentative de réparation..."
    dpkg --configure -a
    apt-get install -f -y
fi

# Pause après les mises à jour
wait_with_message 5 "Stabilisation après mises à jour"

send_progress 65 "Création du cache de paquets..."

# ===============================================================================
# ÉTAPE 5 : CRÉATION DU CACHE COMPLET
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : CRÉATION DU CACHE DE PAQUETS"
echo "========================================================================"
echo ""

echo "◦ Initialisation du système de cache..."
log_info "Initialisation du cache de paquets"

# Initialiser le cache
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

# TÉLÉCHARGEMENT DU DASHBOARD V3 AVEC RETRY
echo ""
if ! download_dashboard_with_retry; then
    echo "  ↦ Le dashboard devra être téléchargé ultérieurement ⚠"
    log_warn "Dashboard non disponible dans le cache"
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
if [ -f "$DASHBOARD_CACHE_DIR/dashboard.tar.gz" ]; then
    echo "  ↦ Dashboard V3 téléchargé"
else
    echo "  ↦ Dashboard V3 non disponible (téléchargement manuel requis)"
fi
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