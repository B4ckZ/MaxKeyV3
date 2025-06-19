#!/bin/bash

# ===============================================================================
# WIDGET REBOOT BUTTON - INSTALLATION
# Version simplifiée avec privilèges root
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_DIR="$SCRIPT_DIR"
WIDGETS_DIR="$(dirname "$WIDGET_DIR")"
SCRIPTS_DIR="$(dirname "$WIDGETS_DIR")"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"
source "$BASE_DIR/scripts/widgets/_core/widget_common.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

init_logging "Installation widget Reboot Button" "widgets"

WIDGET_NAME="rebootbutton"
SERVICE_NAME="maxlink-widget-rebootbutton"

# ===============================================================================
# CONFIGURATION SUDO
# ===============================================================================

configure_sudo_reboot() {
    log_info "Configuration des privilèges sudo pour le redémarrage"
    
    local SUDOERS_FILE="/etc/sudoers.d/maxlink-reboot"
    local SUDO_CONTENT="# MaxLink - Autoriser le redémarrage sans mot de passe
# Généré automatiquement par rebootbutton_install.sh
mosquitto ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/shutdown, /usr/bin/systemctl reboot
root ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/shutdown, /usr/bin/systemctl reboot
"
    
    # Créer le fichier sudoers
    echo "$SUDO_CONTENT" | sudo tee "$SUDOERS_FILE" > /dev/null
    
    # Vérifier la syntaxe
    if sudo visudo -c -f "$SUDOERS_FILE" >/dev/null 2>&1; then
        log_success "Configuration sudo créée avec succès"
        sudo chmod 0440 "$SUDOERS_FILE"
        return 0
    else
        log_error "Erreur dans la configuration sudo"
        sudo rm -f "$SUDOERS_FILE"
        return 1
    fi
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== INSTALLATION WIDGET REBOOT BUTTON =========="

echo ""
echo "========================================================================"
echo "Installation du widget Reboot Button"
echo "========================================================================"
echo ""

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "  ↦ Ce script doit être exécuté avec des privilèges root ✗"
    log_error "Privilèges root requis"
    exit 1
fi

# Configuration sudo pour le redémarrage
echo "◦ Configuration des privilèges de redémarrage..."
if configure_sudo_reboot; then
    echo "  ↦ Privilèges sudo configurés ✓"
else
    echo "  ↦ Impossible de configurer sudo ⚠"
    echo "    Le widget fonctionnera mais nécessitera une configuration manuelle"
fi

# Installation standard du widget
echo ""
echo "◦ Installation du widget Reboot Button..."
if widget_standard_install "$WIDGET_NAME"; then
    echo "  ↦ Installation réussie ✓"
    log_success "Widget Reboot Button installé"
else
    echo "  ↦ Erreur lors de l'installation ✗"
    log_error "Échec installation rebootbutton"
    exit 1
fi

# ===============================================================================
# FINALISATION
# ===============================================================================

echo ""
echo "========================================================================"
echo "Installation terminée avec succès !"
echo "========================================================================"
echo ""
echo "Le widget Reboot Button est maintenant installé et actif."
echo ""
echo "Le service écoute les commandes de redémarrage sur le topic MQTT :"
echo "  → maxlink/system/reboot"
echo ""
echo "IMPORTANT : Pour que le redémarrage fonctionne correctement,"
echo "les privilèges sudo ont été configurés automatiquement."
echo ""

log_success "Installation widget Reboot Button terminée"
exit 0