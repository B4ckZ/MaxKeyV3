#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION DE L'ORCHESTRATEUR
# Version corrigée sans init_script.sh
# ===============================================================================

# Déterminer le répertoire de base du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Charger les configurations et fonctions communes
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"

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
    if [ ! -d "$BASE_DIR/widgets" ]; then
        echo "  ⚠ Répertoire widgets source non trouvé : $BASE_DIR/widgets"
        log_warn "Répertoire widgets non trouvé, installation sans widgets"
        return 0
    fi
    
    # Copier le répertoire _core
    if [ -d "$BASE_DIR/widgets/_core" ]; then
        echo "  ↦ Copie du core des widgets..."
        cp -r "$BASE_DIR/widgets/_core" "$LOCAL_WIDGETS_DIR/"
        echo "  ↦ Core copié ✓"
    fi
    
    # Lister et copier tous les widgets
    local widget_count=0
    log_info "Découverte des widgets disponibles"
    
    for widget_dir in "$BASE_DIR/widgets"/*; do
        if [ -d "$widget_dir" ] && [ "$(basename "$widget_dir")" != "_core" ]; then
            local widget_name=$(basename "$widget_dir")
            log_info "Widget trouvé: $widget_name"
            
            # Copier le widget
            echo "  ↦ Copie du widget $widget_name..."
            cp -r "$widget_dir" "$LOCAL_WIDGETS_DIR/"
            
            # Copier la configuration si elle existe
            local config_file="$widget_dir/${widget_name}_widget.json"
            if [ -f "$config_file" ]; then
                cp "$config_file" "$LOCAL_WIDGETS_CONFIG/"
            fi
            
            ((widget_count++))
        fi
    done
    
    echo "  ↦ $widget_count widgets copiés ✓"
    log_info "$widget_count widgets installés dans $LOCAL_WIDGETS_DIR"
    
    # Définir les permissions
    chown -R root:root "$LOCAL_WIDGETS_DIR"
    chmod -R 755 "$LOCAL_WIDGETS_DIR"
    
    chown -R root:root "$LOCAL_WIDGETS_CONFIG"
    chmod -R 755 "$LOCAL_WIDGETS_CONFIG"
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION ORCHESTRATEUR =========="

echo ""
echo "========================================================================"
echo "INSTALLATION DE L'ORCHESTRATEUR MAXLINK"
echo "========================================================================"

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    log_error "Privilèges root requis"
    exit 1
fi
log_info "Privilèges root confirmés"

# Vérifier si c'est une première installation
check_first_install

# ===============================================================================
# ÉTAPE 1 : COPIE DES WIDGETS
# ===============================================================================

send_progress 20 "Copie des widgets..."

echo ""
echo "========================================================================"
echo "COPIE DES WIDGETS VERS LE SYSTÈME"
echo "========================================================================"

copy_widgets_to_local

# ===============================================================================
# ÉTAPE 2 : INSTALLATION DES DÉPENDANCES WIDGETS
# ===============================================================================

send_progress 40 "Installation des dépendances widgets..."

echo ""
echo "========================================================================"
echo "INSTALLATION DES DÉPENDANCES WIDGETS"
echo "========================================================================"

# Installer les dépendances Python spécifiques
echo "◦ Installation des modules Python requis..."

# Vérifier si pip3 est installé
if ! command -v pip3 &> /dev/null; then
    echo "  ↦ Installation de pip3..."
    apt-get update -qq && apt-get install -y python3-pip
fi

# Modules Python requis par les widgets
PYTHON_MODULES="psutil paho-mqtt"

for module in $PYTHON_MODULES; do
    echo "  ↦ Vérification du module $module..."
    if ! python3 -c "import $module" 2>/dev/null; then
        echo "    • Installation de $module..."
        pip3 install "$module" --quiet
    else
        echo "    • $module déjà installé ✓"
    fi
done

# ===============================================================================
# ÉTAPE 3 : CONFIGURATION DES WIDGETS
# ===============================================================================

send_progress 60 "Configuration des widgets..."

echo ""
echo "========================================================================"
echo "CONFIGURATION DES WIDGETS"
echo "========================================================================"

# Créer le registre des widgets si nécessaire
WIDGETS_REGISTRY_DIR="/var/lib/maxlink/widgets"
mkdir -p "$WIDGETS_REGISTRY_DIR"

echo "◦ Registre des widgets créé dans : $WIDGETS_REGISTRY_DIR"
echo "  ↦ Les widgets s'enregistreront automatiquement lors de leur installation"

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