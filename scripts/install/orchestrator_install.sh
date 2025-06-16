#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION DE L'ORCHESTRATEUR
# ===============================================================================

# Déterminer le répertoire de base du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Charger les configurations et fonctions communes
source "$BASE_DIR/scripts/common/init_script.sh"

# Initialiser le logging
init_logging "Installation de l'orchestrateur MaxLink" "install"

# ===============================================================================
# VARIABLES LOCALES
# ===============================================================================

LOCAL_WIDGETS_DIR="/opt/maxlink/widgets"
LOCAL_WIDGETS_CONFIG="/opt/maxlink/widgets_config"
ORCHESTRATOR_SERVICE="maxlink-orchestrator"
FIRST_INSTALL_FLAG="/opt/maxlink/.first_install_completed"
NEED_REBOOT=false

# ===============================================================================
# FONCTION : VÉRIFICATION DE LA PREMIÈRE INSTALLATION
# ===============================================================================

check_first_install() {
    if [ ! -f "$FIRST_INSTALL_FLAG" ]; then
        log_info "Première installation détectée"
        NEED_REBOOT=true
        touch "$FIRST_INSTALL_FLAG"
        chown root:root "$FIRST_INSTALL_FLAG"
        chmod 644 "$FIRST_INSTALL_FLAG"
    else
        log_info "Installation existante détectée - mise à jour"
    fi
}

# ===============================================================================
# FONCTION : COPIE DES WIDGETS VERS LE SYSTÈME
# ===============================================================================

copy_widgets_to_local() {
    echo ""
    echo "◦ Copie des widgets vers le système..."
    
    # Créer les répertoires s'ils n'existent pas
    mkdir -p "$LOCAL_WIDGETS_DIR"
    mkdir -p "$LOCAL_WIDGETS_CONFIG"
    
    # Vérifier l'existence du répertoire source
    if [ ! -d "$BASE_DIR/scripts/widgets" ]; then
        echo "  ⚠ Répertoire des widgets introuvable"
        log_error "Répertoire widgets introuvable: $BASE_DIR/scripts/widgets"
        return 1
    fi
    
    # Copier tous les widgets
    cp -r "$BASE_DIR/scripts/widgets/"* "$LOCAL_WIDGETS_DIR/" 2>/dev/null || {
        echo "  ⚠ Aucun widget à copier"
        log_warn "Aucun widget trouvé dans $BASE_DIR/scripts/widgets"
        return 0
    }
    
    # Copier les configurations JSON spécifiquement
    find "$LOCAL_WIDGETS_DIR" -name "*_widget.json" -exec cp {} "$LOCAL_WIDGETS_CONFIG/" \; 2>/dev/null
    
    echo "  ↦ Widgets copiés avec succès ✓"
    log_success "Widgets copiés vers /opt/maxlink"
    
    # Définir les permissions
    chown -R root:root /opt/maxlink
    chmod -R 755 /opt/maxlink
    
    return 0
}

# ===============================================================================
# FONCTION : CORRECTION WIFI POUR ESP32
# ===============================================================================

fix_wifi_for_esp32() {
    echo ""
    echo "========================================================================"
    echo "CORRECTION DE LA CONFIGURATION WIFI POUR ESP32"
    echo "========================================================================"
    
    send_progress 40 "Correction WiFi pour compatibilité ESP32..."
    
    # Vérifier que la connexion AP existe
    echo "◦ Vérification de la connexion AP..."
    if ! nmcli connection show "AP-MaxLink" >/dev/null 2>&1; then
        echo "  ⚠ Connexion AP-MaxLink non trouvée"
        log_error "Connexion AP-MaxLink introuvable"
        return 1
    fi
    
    echo "◦ Application des paramètres ESP32..."
    
    # Désactiver WPA3 et forcer WPA2
    nmcli connection modify "AP-MaxLink" \
        802-11-wireless-security.key-mgmt wpa-psk \
        802-11-wireless-security.proto rsn \
        802-11-wireless-security.pairwise ccmp \
        802-11-wireless-security.group ccmp
    
    # Configuration de la bande 2.4GHz
    nmcli connection modify "AP-MaxLink" \
        802-11-wireless.band bg \
        802-11-wireless.channel 6
    
    # Désactiver les fonctionnalités 802.11n qui peuvent poser problème
    nmcli connection modify "AP-MaxLink" \
        802-11-wireless.powersave 2
    
    # Redémarrer la connexion
    echo "◦ Redémarrage du point d'accès..."
    nmcli connection down "AP-MaxLink" 2>/dev/null
    sleep 2
    nmcli connection up "AP-MaxLink"
    
    if [ $? -eq 0 ]; then
        echo "  ↦ Configuration WiFi ESP32 appliquée ✓"
        log_success "WiFi configuré pour compatibilité ESP32"
    else
        echo "  ↦ Erreur lors du redémarrage de l'AP ✗"
        log_error "Impossible de redémarrer l'AP"
        return 1
    fi
    
    return 0
}

# ===============================================================================
# FONCTION : INSTALLATION DES WIDGETS
# ===============================================================================

install_widgets() {
    local widget_dir="$1"
    local widget_name=$(basename "$widget_dir")
    local install_script="$widget_dir/${widget_name}_install.sh"
    
    echo ""
    echo "  ◦ Installation du widget : $widget_name"
    
    if [ -f "$install_script" ]; then
        echo "    → Exécution du script d'installation..."
        
        # Rendre le script exécutable
        chmod +x "$install_script"
        
        # Exécuter avec capture des erreurs
        if bash "$install_script"; then
            echo "    → Installation réussie ✓"
            log_success "Widget $widget_name installé"
            
            # Marquer le widget comme installé
            touch "$widget_dir/.installed"
            
            return 0
        else
            echo "    → Échec de l'installation ✗"
            log_error "Échec installation widget $widget_name"
            return 1
        fi
    else
        echo "    → Pas de script d'installation"
        log_info "Pas de script d'installation pour $widget_name"
        return 0
    fi
}

# ===============================================================================
# MAIN : EXÉCUTION PRINCIPALE
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION ORCHESTRATEUR =========="

echo ""
echo "========================================================================"
echo "MAXLINK - INSTALLATION DE L'ORCHESTRATEUR"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    log_error "Privilèges root requis"
    exit 1
fi

# Vérifier si c'est la première installation
check_first_install

# ===============================================================================
# ÉTAPE 1 : COPIE DES WIDGETS
# ===============================================================================

send_progress 20 "Copie des widgets..."

echo ""
echo "========================================================================"
echo "ÉTAPE 1 : COPIE DES WIDGETS VERS LE SYSTÈME"
echo "========================================================================"

if ! copy_widgets_to_local; then
    echo "⚠ Problème lors de la copie des widgets, mais on continue..."
    log_warn "Copie des widgets incomplète, poursuite de l'installation"
fi

# ===============================================================================
# ÉTAPE 2 : CORRECTION WIFI POUR ESP32
# ===============================================================================

send_progress 40 "Correction WiFi pour ESP32..."

if ! fix_wifi_for_esp32; then
    echo "⚠ Problème lors de la correction WiFi, mais on continue..."
    log_warn "Correction WiFi incomplète, poursuite de l'installation"
fi

# ===============================================================================
# ÉTAPE 3 : INSTALLATION DES WIDGETS
# ===============================================================================

send_progress 50 "Installation des widgets..."

echo ""
echo "========================================================================"
echo "INSTALLATION DES WIDGETS"
echo "========================================================================"

# Compter les widgets
WIDGET_COUNT=$(find /opt/maxlink/widgets -maxdepth 1 -type d -name "*_widget" 2>/dev/null | wc -l)

if [ "$WIDGET_COUNT" -eq 0 ]; then
    echo "◦ Aucun widget à installer"
    log_info "Aucun widget trouvé à installer"
else
    echo "◦ $WIDGET_COUNT widget(s) trouvé(s)"
    log_info "$WIDGET_COUNT widgets à installer"
    
    # Installer chaque widget
    CURRENT_WIDGET=0
    for widget_dir in /opt/maxlink/widgets/*_widget; do
        if [ -d "$widget_dir" ]; then
            widget_name=$(basename "$widget_dir")
            install_script="$widget_dir/${widget_name}_install.sh"
            
            ((CURRENT_WIDGET++))
            WIDGET_PROGRESS=$((50 + (CURRENT_WIDGET * 30 / WIDGET_COUNT)))
            
            send_progress $WIDGET_PROGRESS "Installation widget $widget_name..."
            
            if install_widgets "$widget_dir"; then
                update_service_status "widget_$widget_name" "active" "Widget installé avec succès"
            else
                update_service_status "widget_$widget_name" "inactive" "Échec de l'installation"
            fi
        fi
    done
fi

# ===============================================================================
# ÉTAPE 4 : INSTALLATION DES SCRIPTS SYSTÈME
# ===============================================================================

send_progress 80 "Installation des scripts système..."

echo ""
echo "========================================================================"
echo "INSTALLATION DES SCRIPTS SYSTÈME"
echo "========================================================================"

# Installer les scripts de vérification santé
echo "◦ Installation des scripts de vérification..."

# Script principal de vérification
if [ -f "$BASE_DIR/scripts/system/maxlink_healthcheck.sh" ]; then
    cp "$BASE_DIR/scripts/system/maxlink_healthcheck.sh" /usr/local/bin/
    chmod 755 /usr/local/bin/maxlink_healthcheck.sh
    echo "  ↦ Script healthcheck installé ✓"
else
    echo "  ⚠ Script healthcheck non trouvé"
fi

# Script de gestion de l'orchestrateur
if [ -f "$BASE_DIR/scripts/system/maxlink_orchestrator.sh" ]; then
    cp "$BASE_DIR/scripts/system/maxlink_orchestrator.sh" /usr/local/bin/
    mv /usr/local/bin/maxlink_orchestrator.sh /usr/local/bin/maxlink-orchestrator
    chmod 755 /usr/local/bin/maxlink-orchestrator
    echo "  ↦ Script orchestrateur installé ✓"
else
    echo "  ⚠ Script orchestrateur non trouvé"
fi

# ===============================================================================
# ÉTAPE 5 : CONFIGURATION DES SERVICES SYSTEMD
# ===============================================================================

send_progress 90 "Configuration des services systemd..."

echo ""
echo "========================================================================"
echo "CONFIGURATION DES SERVICES SYSTEMD"
echo "========================================================================"

# Services de notification
echo "◦ Installation des services de notification..."

for notify_service in "$BASE_DIR"/services/notify-*.service; do
    if [ -f "$notify_service" ]; then
        service_name=$(basename "$notify_service")
        cp "$notify_service" /etc/systemd/system/
        echo "  ↦ Service $service_name installé"
    fi
done

# Services targets
echo "◦ Installation des targets systemd..."

for target_file in "$BASE_DIR"/services/*.target; do
    if [ -f "$target_file" ]; then
        target_name=$(basename "$target_file")
        cp "$target_file" /etc/systemd/system/
        echo "  ↦ Target $target_name installé"
    fi
done

# Service principal orchestrateur
if [ -f "$BASE_DIR/services/${ORCHESTRATOR_SERVICE}.service" ]; then
    cp "$BASE_DIR/services/${ORCHESTRATOR_SERVICE}.service" /etc/systemd/system/
    echo "  ↦ Service orchestrateur installé ✓"
fi

# Recharger systemd
echo "◦ Rechargement de systemd..."
systemctl daemon-reload

# Activer les services essentiels
echo "◦ Activation des services..."
systemctl enable maxlink-notify-starting.service 2>/dev/null
systemctl enable maxlink-notify-ready.service 2>/dev/null
systemctl enable maxlink-notify-failed.service 2>/dev/null
systemctl enable maxlink-orchestrator.service 2>/dev/null

echo "  ↦ Services systemd configurés ✓"

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "✓ INSTALLATION DE L'ORCHESTRATEUR TERMINÉE"
echo "========================================================================"

# Afficher le résumé selon le type d'installation
if [ "$NEED_REBOOT" = true ]; then
    echo ""
    echo "Installation initiale de l'orchestrateur MaxLink terminée avec succès !"
    echo ""
    echo "Composants installés :"
    echo "  • Scripts de vérification (healthcheck)"
    echo "  • Services systemd de notification"
    echo "  • Targets systemd pour l'orchestration"
    echo "  • Script de gestion : /usr/local/bin/maxlink-orchestrator"
    echo ""
    echo "Les services seront orchestrés automatiquement au prochain démarrage."
else
    echo "L'orchestrateur MaxLink a été mis à jour."
    echo ""
    echo "Modifications appliquées :"
    echo "  • Widgets mis à jour"
    echo "  • Configuration rechargée"
fi

echo ""
echo "Commandes disponibles :"
echo "  • sudo maxlink-orchestrator status    - État du système"
echo "  • sudo maxlink-orchestrator check     - Vérification santé"
echo "  • sudo maxlink-orchestrator logs all  - Voir tous les logs"
echo ""

log_success "Installation orchestrateur terminée"

# Déterminer si un redémarrage est nécessaire
if [ "$SKIP_REBOOT" != "true" ] && [ "$NEED_REBOOT" = true ]; then
    echo "========================================================================"
    echo "REDÉMARRAGE REQUIS"
    echo "========================================================================"
    echo ""
    echo "Un redémarrage est nécessaire pour activer l'orchestration complète."
    echo ""
    echo "  ↦ Redémarrage automatique dans 15 secondes..."
    echo ""
    log_info "Redémarrage système programmé pour finaliser l'installation"
    sleep 15
    reboot
else
    if [ "$SKIP_REBOOT" = "true" ]; then
        echo ""
        echo "Mode installation complète : redémarrage géré par le script parent."
    fi
fi

exit 0