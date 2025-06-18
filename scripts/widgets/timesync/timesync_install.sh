#!/bin/bash

# ===============================================================================
# WIDGET TIME SYNCHRONIZATION - INSTALLATION SIMPLIFIÉE
# Synchronisation automatique uniquement
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

init_logging "Installation widget TimSync" "widgets"

WIDGET_NAME="timesync"
SERVICE_NAME="maxlink-widget-timesync"

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== INSTALLATION WIDGET TIMESYNC SIMPLIFIÉ =========="

echo ""
echo "========================================================================"
echo "Installation du widget Time Synchronization (Auto)"
echo "========================================================================"
echo ""

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "  ↦ Ce script doit être exécuté avec des privilèges root ✗"
    log_error "Privilèges root requis"
    exit 1
fi

# Installation standard du widget
echo "◦ Installation du widget TimSync..."
if widget_standard_install "$WIDGET_NAME"; then
    echo "  ↦ Installation réussie ✓"
    log_success "Widget TimSync installé"
else
    echo "  ↦ Erreur lors de l'installation ✗"
    log_error "Échec installation timesync"
    exit 1
fi

# ===============================================================================
# CONFIGURATION RTC (SI DISPONIBLE)
# ===============================================================================

echo ""
echo "◦ Configuration RTC..."

if [ -e "/dev/rtc1" ] || [ -e "/sys/class/rtc/rtc1" ]; then
    echo "  ↦ Module RTC détecté ✓"
    log_info "Module RTC configuré"
    
    # Service RTC simple
    cat > /etc/systemd/system/maxlink-rtc.service << 'EOF'
[Unit]
Description=MaxLink RTC Setup
Before=maxlink-widget-timesync.service

[Service]
Type=oneshot
ExecStart=/sbin/hwclock --hctosys --rtc=/dev/rtc1
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable maxlink-rtc.service 2>/dev/null || true
    echo "  ↦ RTC configuré ✓"
else
    echo "  ↦ Pas de module RTC - Fonctionnement système uniquement"
    log_info "Pas de RTC détecté"
fi

# ===============================================================================
# PERMISSIONS SUDO SIMPLIFIÉES
# ===============================================================================

echo ""
echo "◦ Configuration permissions..."

# Permissions sudo minimales
cat > "/etc/sudoers.d/maxlink-timesync" << 'EOF'
# MaxLink TimSync - Permissions minimales
maxlink ALL=(ALL) NOPASSWD: /usr/bin/timedatectl set-time *
maxlink ALL=(ALL) NOPASSWD: /usr/bin/timedatectl set-ntp *
EOF

# Vérifier la syntaxe
if visudo -c -f "/etc/sudoers.d/maxlink-timesync" >/dev/null 2>&1; then
    echo "  ↦ Permissions configurées ✓"
    log_info "Permissions sudo configurées"
else
    echo "  ↦ Erreur permissions ✗"
    log_error "Erreur configuration sudo"
    rm -f "/etc/sudoers.d/maxlink-timesync"
    exit 1
fi

# ===============================================================================
# FINALISATION
# ===============================================================================

echo ""
echo "◦ Finalisation..."

# Utilisateur maxlink
if ! id "maxlink" &>/dev/null; then
    useradd -r -s /bin/bash -d /opt/maxlink maxlink
    log_info "Utilisateur maxlink créé"
fi

usermod -a -G sudo maxlink 2>/dev/null || true

# Recharger systemd
systemctl daemon-reload

echo "  ↦ Installation finalisée ✓"

echo ""
echo "========================================================================"
echo "Installation terminée !"
echo "========================================================================"
echo ""
echo "◦ Widget TimSync configuré pour synchronisation automatique"
echo "◦ Service: $SERVICE_NAME"
echo "◦ Seuil décalage: 3 minutes"
echo "◦ Indicateur: Vert = OK, Rouge = Problème"
echo ""
echo "◦ Configuration sources de temps:"
echo "  Modifier widgets/wifistats/devices.json"
echo "  Ajouter 'time_source': true aux PC de référence"
echo ""

if [ -e "/dev/rtc1" ]; then
    echo "◦ Module RTC configuré - Fiabilité maximale ✓"
else
    echo "◦ Pour plus de fiabilité, installer un module RTC DS3231"
fi

echo ""

log_success "Installation TimSync simplifiée terminée"
exit 0