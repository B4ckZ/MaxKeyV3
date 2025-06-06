#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION DE TOUS LES WIDGETS MQTT (VERSION CORRIGÉE)
# Installation avec mise à jour du statut
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"
source "$BASE_DIR/scripts/common/packages.sh"
source "$BASE_DIR/scripts/widgets/_core/widget_common.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Installation de tous les widgets MQTT" "install"

# Variables
WIDGETS_DIR="$BASE_DIR/scripts/widgets"
TOTAL_WIDGETS=0
INSTALLED_WIDGETS=0
FAILED_WIDGETS=0

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Découvrir tous les widgets disponibles
discover_widgets() {
    local widgets=()
    
    log_info "Découverte des widgets disponibles" >&2
    
    for widget_dir in "$WIDGETS_DIR"/*; do
        [ ! -d "$widget_dir" ] && continue
        
        local widget_name=$(basename "$widget_dir")
        [ "$widget_name" = "_core" ] && continue
        
        if widget_validate "$widget_name" >/dev/null 2>&1; then
            widgets+=("$widget_name")
            log_info "Widget trouvé: $widget_name" >&2
        else
            log_warn "Widget invalide ignoré: $widget_name" >&2
        fi
    done
    
    printf '%s\n' "${widgets[@]}"
}

# Installer les dépendances Python globales
install_python_dependencies() {
    log_info "Installation des dépendances Python"
    
    echo "◦ Vérification des paquets Python..."
    
    local python_packages="python3-psutil python3-paho-mqtt"
    
    local missing=""
    for pkg in $python_packages; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
            missing="$missing $pkg"
        fi
    done
    
    if [ -z "$missing" ]; then
        echo "  ↦ Toutes les dépendances Python sont installées ✓"
        return 0
    fi
    
    echo "  ↦ Installation des paquets manquants..."
    if install_packages_by_category "python"; then
        echo "  ↦ Dépendances Python installées ✓"
        return 0
    else
        if apt-get install -y $missing >/dev/null 2>&1; then
            echo "  ↦ Dépendances Python installées via apt ✓"
            return 0
        else
            echo "  ↦ Impossible d'installer les dépendances ✗"
            return 1
        fi
    fi
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION DES WIDGETS MQTT =========="

echo ""
echo "========================================================================"
echo "INSTALLATION DES WIDGETS MQTT (WGS)"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    log_error "Privilèges root requis"
    exit 1
fi

# Vérifier le broker MQTT
echo "◦ Vérification du broker MQTT..."
if ! systemctl is-active --quiet mosquitto; then
    echo "  ↦ Le broker MQTT n'est pas actif ✗"
    echo ""
    echo "Veuillez d'abord exécuter mqtt_install.sh"
    log_error "Broker MQTT non actif"
    exit 1
fi
echo "  ↦ Broker MQTT actif ✓"

send_progress 10 "Découverte des widgets..."

# Découvrir les widgets
echo ""
echo "◦ Recherche des widgets disponibles..."
widgets=()
while IFS= read -r widget; do
    widgets+=("$widget")
done < <(discover_widgets)
TOTAL_WIDGETS=${#widgets[@]}

if [ $TOTAL_WIDGETS -eq 0 ]; then
    echo "  ↦ Aucun widget trouvé ✗"
    log_error "Aucun widget valide trouvé"
    exit 1
fi

echo "  ↦ $TOTAL_WIDGETS widget(s) trouvé(s) ✓"
echo ""
echo "Widgets disponibles :"
for widget in "${widgets[@]}"; do
    if [ "$(widget_is_installed "$widget")" = "yes" ]; then
        echo "  • $widget (déjà installé)"
    else
        echo "  • $widget"
    fi
done

send_progress 20 "Installation des dépendances..."

# Installer les dépendances Python globales
echo ""
if ! install_python_dependencies; then
    echo "  ↦ Problème avec les dépendances Python ⚠"
    log_warn "Certaines dépendances Python manquantes"
fi

send_progress 30 "Installation des widgets..."

# Installer chaque widget
echo ""
echo "========================================================================"
echo "INSTALLATION DES WIDGETS"
echo "========================================================================"

progress_per_widget=$((60 / TOTAL_WIDGETS))
current_progress=30

for widget in "${widgets[@]}"; do
    if widget_standard_install "$widget"; then
        ((INSTALLED_WIDGETS++))
    else
        ((FAILED_WIDGETS++))
    fi
    
    current_progress=$((current_progress + progress_per_widget))
    send_progress $current_progress "Widget $widget traité"
    
    sleep 2
done

send_progress 90 "Vérification finale..."

# Vérification finale
echo ""
echo "========================================================================"
echo "VÉRIFICATION FINALE"
echo "========================================================================"
echo ""

echo "◦ État des services :"
for widget in "${widgets[@]}"; do
    if [ "$(widget_is_installed "$widget")" = "yes" ]; then
        service_name=$(widget_get_value "$WIDGETS_TRACKING_FILE" "$widget.service_name")
        if [ -n "$service_name" ] && systemctl is-active --quiet "$service_name"; then
            echo "  ↦ $widget : ✓ actif"
        else
            echo "  ↦ $widget : ✗ inactif"
        fi
    else
        echo "  ↦ $widget : - non installé"
    fi
done

# Test MQTT rapide
echo ""
echo "◦ Test de réception MQTT..."
if timeout 3 mosquitto_sub -h localhost -u "$MQTT_USER" -P "$MQTT_PASS" -t "rpi/+/+/+" -C 1 >/dev/null 2>&1; then
    echo "  ↦ Messages MQTT reçus ✓"
else
    echo "  ↦ Aucun message reçu (normal au démarrage) ⚠"
fi

# MISE À JOUR DU STATUT DU SERVICE
if [ -n "$SERVICE_ID" ]; then
    echo ""
    echo "◦ Mise à jour du statut du service..."
    if [ $FAILED_WIDGETS -eq 0 ]; then
        update_service_status "$SERVICE_ID" "active"
        echo "  ↦ Statut du service mis à jour : active ✓"
        log_info "Statut du service $SERVICE_ID mis à jour: active"
    else
        echo "  ↦ Statut non mis à jour (erreurs détectées) ⚠"
        log_warn "Statut non mis à jour à cause des erreurs"
    fi
fi

send_progress 100 "Installation terminée"

# Résumé final
echo ""
echo "========================================================================"
echo "RÉSUMÉ"
echo "========================================================================"
echo ""
echo "◦ Widgets trouvés    : $TOTAL_WIDGETS"
echo "◦ Widgets installés  : $INSTALLED_WIDGETS"
echo "◦ Widgets échoués    : $FAILED_WIDGETS"
echo ""

if [ $FAILED_WIDGETS -eq 0 ]; then
    echo "✓ Installation terminée avec succès !"
    log_success "Tous les widgets installés avec succès"
else
    echo "⚠ Installation terminée avec $FAILED_WIDGETS erreur(s)"
    log_warn "Installation partielle: $FAILED_WIDGETS erreurs"
fi

echo "Commandes utiles :"
echo "  • Voir tous les logs    : journalctl -u 'maxlink-widget-*' -f"
echo "  • Voir tous les topics  : mosquitto_sub -h localhost -u $MQTT_USER -P $MQTT_PASS -t '#' -v"
echo "  • État des services     : systemctl status 'maxlink-widget-*'"
echo ""

log_info "Installation terminée - Installés: $INSTALLED_WIDGETS/$TOTAL_WIDGETS"

if [ $FAILED_WIDGETS -ne 0 ]; then
    exit $FAILED_WIDGETS
fi

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