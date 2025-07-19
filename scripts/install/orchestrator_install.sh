#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION DE L'ORCHESTRATEUR
# Gestion centralisée des services et configuration finale
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$SCRIPT_DIR/../common/variables.sh"
source "$SCRIPT_DIR/../common/logging.sh"

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Répertoires locaux pour les widgets
LOCAL_WIDGETS_DIR="/var/lib/maxlink/widgets"
LOCAL_WIDGETS_CONFIG="/etc/maxlink/widgets"

# Configuration targets systemd
EARLY_TARGET="maxlink-early.target"
PRE_NETWORK_TARGET="maxlink-pre-network.target"
NETWORK_TARGET="maxlink-network.target"
POST_NETWORK_TARGET="maxlink-post-network.target"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Configuration des permissions ACL pour l'utilisateur prod
setup_prod_user_permissions() {
    echo ""
    echo "========================================================================"
    echo "CONFIGURATION DES PERMISSIONS SSH POUR L'UTILISATEUR PROD"
    echo "========================================================================"
    
    # Vérifier que l'utilisateur prod existe
    if ! id "prod" &>/dev/null; then
        echo "⚠ L'utilisateur 'prod' n'existe pas. Création en cours..."
        useradd -m -s /bin/bash prod
        echo "  ↦ Utilisateur 'prod' créé ✓"
        log_info "Utilisateur prod créé"
    fi
    
    # Installer ACL si nécessaire
    if ! command -v setfacl &> /dev/null; then
        echo "◦ Installation du paquet ACL..."
        apt-get update -qq
        apt-get install -y acl &>/dev/null
        echo "  ↦ Paquet ACL installé ✓"
    fi
    
    # S'assurer que le système de fichiers supporte les ACL
    if ! mount | grep -E "/ |/var " | grep -q acl; then
        echo "◦ Activation du support ACL sur le système de fichiers..."
        mount -o remount,acl /
        echo "  ↦ ACL activé ✓"
    fi
    
    # Créer les répertoires nécessaires s'ils n'existent pas
    mkdir -p /var/www/html
    mkdir -p /var/www/.ssh
    
    # Configuration des ACL pour /var/www
    echo "◦ Configuration des permissions ACL pour l'utilisateur prod..."
    
    # Permissions complètes sur /var/www et tous les sous-répertoires
    setfacl -R -m u:prod:rwx /var/www
    setfacl -R -d -m u:prod:rwx /var/www
    
    # IMPORTANT : Réinitialiser le masque ACL pour permettre toutes les permissions
    echo "◦ Réinitialisation du masque ACL..."
    setfacl -R -m mask::rwx /var/www
    echo "  ↦ Masque ACL réinitialisé à rwx ✓"
    
    # S'assurer que prod peut lire/écrire tous les fichiers existants
    find /var/www -type f -exec setfacl -m u:prod:rw {} \; 2>/dev/null || true
    find /var/www -type d -exec setfacl -m u:prod:rwx {} \; 2>/dev/null || true
    
    echo "  ↦ Permissions ACL configurées ✓"
    
    # Ajuster aussi les permissions classiques pour être sûr
    chown -R www-data:www-data /var/www
    chmod -R 755 /var/www
    
    # Ajouter prod au groupe www-data
    usermod -a -G www-data prod 2>/dev/null || true
    
    # Créer un script de maintenance des permissions AMÉLIORÉ
    cat > /usr/local/bin/maxlink-fix-prod-permissions << 'EOF'
#!/bin/bash
# Script de maintenance des permissions pour l'utilisateur prod

echo "Réparation des permissions pour l'utilisateur prod..."

# Réappliquer les ACL
setfacl -R -m u:prod:rwx /var/www
setfacl -R -d -m u:prod:rwx /var/www

# IMPORTANT : Réinitialiser le masque pour permettre toutes les permissions
setfacl -R -m mask::rwx /var/www

# S'assurer que tous les fichiers sont accessibles
find /var/www -type f -exec setfacl -m u:prod:rw {} \; 2>/dev/null || true
find /var/www -type d -exec setfacl -m u:prod:rwx {} \; 2>/dev/null || true

echo "Permissions réparées."
echo ""
echo "Vérification du masque ACL:"
getfacl /var/www/maxlink-dashboard 2>/dev/null | grep -E "(mask|user:prod)" || true
EOF
    
    chmod +x /usr/local/bin/maxlink-fix-prod-permissions
    
    echo "  ↦ Script de maintenance créé : /usr/local/bin/maxlink-fix-prod-permissions"
    
    # Vérifier les permissions
    echo ""
    echo "◦ Vérification des permissions..."
    if getfacl /var/www 2>/dev/null | grep -q "user:prod:rwx"; then
        echo "  ↦ Permissions ACL vérifiées ✓"
        
        # Vérifier aussi le masque
        MASK=$(getfacl /var/www 2>/dev/null | grep "^mask::" | cut -d: -f3)
        if [ "$MASK" = "rwx" ]; then
            echo "  ↦ Masque ACL correct (rwx) ✓"
        else
            echo "  ⚠ Masque ACL incorrect ($MASK), correction..."
            setfacl -R -m mask::rwx /var/www
            echo "  ↦ Masque corrigé ✓"
        fi
        
        log_success "Permissions SSH configurées pour l'utilisateur prod"
        return 0
    else
        echo "  ⚠ Problème détecté avec les permissions ACL"
        log_error "Problème avec les permissions ACL"
        return 1
    fi
}

# Nouvelle fonction pour corriger les permissions après toutes les installations
fix_permissions_after_install() {
    echo ""
    echo "========================================================================"
    echo "CORRECTION FINALE DES PERMISSIONS"
    echo "========================================================================"
    
    echo "◦ Correction du masque ACL après les installations..."
    
    # Le script nginx_install a peut-être modifié les permissions
    if [ -d "/var/www/maxlink-dashboard" ]; then
        echo "  ↦ Dashboard détecté, correction des permissions..."
        
        # Réappliquer les ACL pour prod
        setfacl -R -m u:prod:rwx /var/www/maxlink-dashboard
        setfacl -R -d -m u:prod:rwx /var/www/maxlink-dashboard
        
        # Corriger le masque ACL
        setfacl -R -m mask::rwx /var/www/maxlink-dashboard
        
        echo "  ↦ Permissions du dashboard corrigées ✓"
        log_success "Permissions du dashboard corrigées après installation"
    fi
    
    # Corriger tout /var/www pour être sûr
    setfacl -R -m mask::rwx /var/www 2>/dev/null || true
    
    echo "  ↦ Masque ACL global corrigé ✓"
    
    # Afficher l'état final
    echo ""
    echo "◦ État final des permissions:"
    getfacl /var/www/maxlink-dashboard 2>/dev/null | grep -E "(owner|group|user:prod|mask)" | head -10 || true
    
    return 0
}

# Copier les widgets vers le répertoire local
copy_widgets_to_local() {
    echo ""
    echo "========================================================================"
    echo "COPIE DES WIDGETS"
    echo "========================================================================"
    
    # Créer les répertoires si nécessaire
    mkdir -p "$LOCAL_WIDGETS_DIR"
    mkdir -p "$LOCAL_WIDGETS_CONFIG"
    
    # Copier les widgets
    if [ -d "$BASE_DIR/widgets" ]; then
        echo "◦ Copie des widgets depuis $BASE_DIR/widgets..."
        
        # Copier tous les widgets
        cp -r "$BASE_DIR/widgets/"* "$LOCAL_WIDGETS_DIR/" 2>/dev/null || true
        
        # Compter les widgets copiés
        WIDGET_COUNT=$(find "$LOCAL_WIDGETS_DIR" -name "*.py" -type f | wc -l)
        echo "  ↦ $WIDGET_COUNT widgets copiés ✓"
        
        # Créer les fichiers de configuration par défaut si nécessaire
        for widget in "$LOCAL_WIDGETS_DIR"/*; do
            if [ -d "$widget" ]; then
                widget_name=$(basename "$widget")
                config_file="$LOCAL_WIDGETS_CONFIG/${widget_name}.json"
                
                if [ ! -f "$config_file" ]; then
                    echo "{}" > "$config_file"
                fi
            fi
        done
        
        log_success "Widgets copiés vers $LOCAL_WIDGETS_DIR"
        return 0
    else
        echo "⚠ Répertoire des widgets non trouvé : $BASE_DIR/widgets"
        log_error "Répertoire widgets non trouvé"
        return 1
    fi
}

# Configuration du module RTC
setup_rtc_module() {
    echo ""
    echo "========================================================================"
    echo "CONFIGURATION DU MODULE RTC"
    echo "========================================================================"
    
    # Détection du module RTC
    echo "◦ Détection du module RTC..."
    
    # Vérifier si un RTC est déjà configuré
    if hwclock -r &>/dev/null; then
        echo "  ↦ Module RTC déjà configuré ✓"
        RTC_TIME=$(hwclock -r)
        echo "  ↦ RTC fonctionnel : $RTC_TIME"
        
        # Essayer de détecter le type
        if dmesg | grep -i "rtc.*ds3231" &>/dev/null || i2cdetect -y 1 2>/dev/null | grep -q "68"; then
            RTC_TYPE="ds3231"
        elif dmesg | grep -i "rtc.*ds1307" &>/dev/null; then
            RTC_TYPE="ds1307"
        elif dmesg | grep -i "rtc.*pcf8523" &>/dev/null; then
            RTC_TYPE="pcf8523"
        else
            RTC_TYPE="ds3231"  # Par défaut
        fi
        echo "  ↦ Type détecté/supposé : $RTC_TYPE"
    else
        # Pas de RTC configuré, essayer de détecter via I2C
        if command -v i2cdetect &>/dev/null; then
            if i2cdetect -y 1 2>/dev/null | grep -q "68"; then
                RTC_TYPE="ds3231"
            elif i2cdetect -y 1 2>/dev/null | grep -q "51"; then
                RTC_TYPE="pcf8523"
            else
                RTC_TYPE="ds3231"  # Par défaut
            fi
        else
            RTC_TYPE="ds3231"  # Par défaut si i2cdetect non disponible
        fi
    fi
    
    echo "  ↦ Module RTC détecté : $RTC_TYPE ✓"
    log_info "Module RTC $RTC_TYPE détecté"
    
    # Configuration du device tree overlay
    echo "◦ Configuration du device tree overlay..."
    
    if [ -f "$CONFIG_FILE" ]; then
        # Vérifier si l'overlay est déjà configuré
        if grep -q "dtoverlay=i2c-rtc" "$CONFIG_FILE"; then
            echo "  ↦ Overlay RTC déjà configuré ✓"
        else
            # Ajouter l'overlay
            echo "" >> "$CONFIG_FILE"
            echo "# Configuration RTC MaxLink" >> "$CONFIG_FILE"
            echo "dtoverlay=i2c-rtc,$RTC_TYPE" >> "$CONFIG_FILE"
            echo "  ↦ Overlay ajouté au fichier de configuration ✓"
        fi
    else
        echo "  ⚠ Fichier de configuration non trouvé : $CONFIG_FILE"
        log_warning "Fichier config.txt non trouvé"
    fi
    
    log_success "Overlay RTC configuré dans $CONFIG_FILE"
    
    # Vérifier les outils RTC
    echo "◦ Vérification des outils RTC..."
    if command -v hwclock &>/dev/null; then
        echo "  ↦ Outils RTC disponibles ✓"
    else
        echo "  ⚠ hwclock non trouvé, installation peut être nécessaire"
        log_warning "hwclock non disponible"
    fi
    
    # Créer un service de synchronisation RTC
    echo "◦ Création du service de synchronisation RTC..."
    
    cat > /etc/systemd/system/maxlink-rtc-sync.service << EOF
[Unit]
Description=MaxLink RTC Time Synchronization
DefaultDependencies=no
Before=basic.target
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/hwclock -s

[Install]
WantedBy=sysinit.target
EOF
    
    systemctl enable maxlink-rtc-sync.service &>/dev/null
    echo "  ↦ Service de synchronisation créé ✓"
    log_success "Service RTC configuré"
    
    # Désactiver fake-hwclock s'il est présent
    echo "◦ Désactivation de fake-hwclock..."
    if systemctl list-unit-files | grep -q fake-hwclock; then
        systemctl disable fake-hwclock &>/dev/null
        systemctl stop fake-hwclock &>/dev/null
        echo "  ↦ fake-hwclock désactivé ✓"
    else
        echo "  ↦ fake-hwclock non présent ✓"
    fi
    
    # Désactiver les services NTP pour un serveur hors ligne
    echo "◦ Désactivation des services NTP (serveur hors ligne)..."
    
    # systemd-timesyncd
    if systemctl list-unit-files | grep -q systemd-timesyncd; then
        systemctl disable systemd-timesyncd &>/dev/null
        systemctl stop systemd-timesyncd &>/dev/null
        echo "  ↦ systemd-timesyncd désactivé ✓"
    fi
    
    # ntp
    if systemctl list-unit-files | grep -q "^ntp.service"; then
        systemctl disable ntp &>/dev/null
        systemctl stop ntp &>/dev/null
        echo "  ↦ ntp désactivé ✓"
    fi
    
    # chrony
    if systemctl list-unit-files | grep -q chrony; then
        systemctl disable chrony &>/dev/null
        systemctl stop chrony &>/dev/null
        echo "  ↦ chrony désactivé ✓"
    fi
    
    # Masquer time-sync.target pour empêcher tout service de synchronisation
    systemctl mask time-sync.target &>/dev/null
    echo "  ↦ Synchronisation temps réseau complètement désactivée ✓"
    
    echo ""
    echo "✓ Configuration RTC terminée"
    echo "  Module : $RTC_TYPE"
    echo "  Service : maxlink-rtc-sync.service"
    echo "  Services NTP : désactivés"
    
    log_success "Configuration RTC complète pour module $RTC_TYPE avec NTP désactivé"
    
    return 0
}

# Création de l'infrastructure d'orchestration
setup_orchestration_infrastructure() {
    echo ""
    echo "========================================================================"
    echo "INFRASTRUCTURE D'ORCHESTRATION"
    echo "========================================================================"
    
    # Créer les répertoires nécessaires
    mkdir -p /var/lib/maxlink/{status,logs}
    mkdir -p /etc/maxlink/orchestrator
    
    # Créer les scripts de healthcheck
    echo "◦ Création des scripts de vérification..."
    
    # Script de healthcheck pour l'AP
    cat > /usr/local/bin/maxlink-check-ap << 'EOF'
#!/bin/bash
# Vérification du point d'accès
nmcli con show --active | grep -q "MaxLink-AP" && exit 0 || exit 1
EOF
    chmod +x /usr/local/bin/maxlink-check-ap
    
    # Script de healthcheck pour Nginx
    cat > /usr/local/bin/maxlink-check-nginx << 'EOF'
#!/bin/bash
# Vérification de Nginx
systemctl is-active nginx >/dev/null && curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200" && exit 0 || exit 1
EOF
    chmod +x /usr/local/bin/maxlink-check-nginx
    
    # Script de healthcheck pour MQTT
    cat > /usr/local/bin/maxlink-check-mqtt << 'EOF'
#!/bin/bash
# Vérification de MQTT
systemctl is-active mosquitto >/dev/null && mosquitto_sub -h localhost -u mosquitto -P mqtt -t '$SYS/broker/version' -C 1 -W 2 >/dev/null 2>&1 && exit 0 || exit 1
EOF
    chmod +x /usr/local/bin/maxlink-check-mqtt
    
    echo "  ↦ Scripts de vérification créés ✓"
    log_success "Scripts healthcheck créés"
    
    # Créer les services systemd
    echo "◦ Création des services systemd..."
    
    # Service de monitoring
    cat > /etc/systemd/system/maxlink-monitor.service << EOF
[Unit]
Description=MaxLink System Monitor
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/maxlink-monitor
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    echo "  ↦ Services systemd créés ✓"
    log_success "Services systemd créés"
    
    # Créer les targets systemd personnalisés
    echo "◦ Création des targets systemd..."
    
    # Early target (services critiques au démarrage)
    cat > /etc/systemd/system/$EARLY_TARGET << EOF
[Unit]
Description=MaxLink Early Boot Services
DefaultDependencies=no
Conflicts=shutdown.target
After=sysinit.target
Before=basic.target

[Install]
WantedBy=basic.target
EOF
    
    # Pre-network target
    cat > /etc/systemd/system/$PRE_NETWORK_TARGET << EOF
[Unit]
Description=MaxLink Pre-Network Services
DefaultDependencies=no
After=$EARLY_TARGET
Before=network.target
Conflicts=shutdown.target

[Install]
WantedBy=network.target
EOF
    
    # Network target
    cat > /etc/systemd/system/$NETWORK_TARGET << EOF
[Unit]
Description=MaxLink Network Services
After=network.target
Before=network-online.target
Wants=network-online.target

[Install]
WantedBy=multi-user.target
EOF
    
    # Post-network target
    cat > /etc/systemd/system/$POST_NETWORK_TARGET << EOF
[Unit]
Description=MaxLink Post-Network Services
After=$NETWORK_TARGET network-online.target
Wants=$NETWORK_TARGET

[Install]
WantedBy=multi-user.target
EOF
    
    echo "  ↦ Targets systemd créés ✓"
    log_success "Targets systemd créés"
    
    # Créer les overrides pour les services existants
    echo "◦ Configuration des dépendances des services..."
    
    # NetworkManager dans early
    mkdir -p /etc/systemd/system/NetworkManager.service.d
    cat > /etc/systemd/system/NetworkManager.service.d/maxlink.conf << EOF
[Unit]
After=$EARLY_TARGET
Wants=$EARLY_TARGET

[Install]
WantedBy=$PRE_NETWORK_TARGET
EOF
    
    # Nginx dans network
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/maxlink.conf << EOF
[Unit]
After=$NETWORK_TARGET
Wants=$NETWORK_TARGET

[Install]
WantedBy=$POST_NETWORK_TARGET
EOF
    
    # Mosquitto dans post-network
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat > /etc/systemd/system/mosquitto.service.d/maxlink.conf << EOF
[Unit]
After=$POST_NETWORK_TARGET nginx.service
Wants=$POST_NETWORK_TARGET

[Install]
WantedBy=$POST_NETWORK_TARGET
EOF
    
    echo "  ↦ Dépendances configurées ✓"
    log_success "Overrides systemd configurés"
    
    # Créer le script principal de l'orchestrateur
    echo "◦ Création du script orchestrateur..."
    
    cat > /usr/local/bin/maxlink-orchestrator << 'EOF'
#!/bin/bash

# MaxLink Orchestrator - Gestion centralisée

COMMAND="$1"
LOG_FILE="/var/log/maxlink-orchestrator.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

case "$COMMAND" in
    start)
        log "Démarrage de l'orchestrateur MaxLink..."
        systemctl start maxlink-early.target
        sleep 2
        systemctl start maxlink-pre-network.target
        sleep 2
        systemctl start maxlink-network.target
        sleep 2
        systemctl start maxlink-post-network.target
        log "Orchestrateur démarré"
        ;;
    stop)
        log "Arrêt de l'orchestrateur MaxLink..."
        systemctl stop maxlink-post-network.target
        systemctl stop maxlink-network.target
        systemctl stop maxlink-pre-network.target
        systemctl stop maxlink-early.target
        log "Orchestrateur arrêté"
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    status)
        echo "=== MaxLink Orchestrator Status ==="
        echo ""
        echo "Targets:"
        systemctl status maxlink-*.target --no-pager | grep -E "(●|Active:)" || true
        echo ""
        echo "Services:"
        systemctl status NetworkManager nginx mosquitto maxlink-widget-* --no-pager | grep -E "(●|Active:)" || true
        ;;
    enable)
        log "Activation des services MaxLink..."
        systemctl enable maxlink-early.target
        systemctl enable maxlink-pre-network.target
        systemctl enable maxlink-network.target
        systemctl enable maxlink-post-network.target
        log "Services activés"
        ;;
    disable)
        log "Désactivation des services MaxLink..."
        systemctl disable maxlink-early.target
        systemctl disable maxlink-pre-network.target
        systemctl disable maxlink-network.target
        systemctl disable maxlink-post-network.target
        log "Services désactivés"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|enable|disable}"
        exit 1
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/maxlink-orchestrator
    echo "  ↦ Script orchestrateur créé ✓"
    log_success "Script de gestion créé"
    
    return 0
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

# Initialiser le logging
init_logging "Installation de l'orchestrateur MaxLink" "install"

echo ""
echo "========================================================================"
echo "ORCHESTRATEUR MAXLINK - INSTALLATION"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier si c'est une première installation ou une mise à jour
if [ -f "/usr/local/bin/maxlink-orchestrator" ]; then
    echo "◦ Mise à jour de l'orchestrateur détectée"
    log_info "Mise à jour de l'orchestrateur"
    IS_FIRST_INSTALL=false
else
    echo "◦ Première installation détectée"
    log_info "Première installation de l'orchestrateur"
    IS_FIRST_INSTALL=true
fi

# ===============================================================================
# ÉTAPE 1 : COPIE DES WIDGETS
# ===============================================================================

send_progress 10 "Copie des widgets..."

if ! copy_widgets_to_local; then
    echo "⚠ Erreur lors de la copie des widgets"
    log_error "Échec de la copie des widgets"
fi

send_progress 20 "Widgets copiés"

# ===============================================================================
# ÉTAPE 2 : CONFIGURATION DES PERMISSIONS SSH POUR PROD
# ===============================================================================

send_progress 25 "Configuration des permissions SSH..."

if ! setup_prod_user_permissions; then
    echo "⚠ Erreur lors de la configuration des permissions pour l'utilisateur prod"
    log_error "Échec de la configuration des permissions ACL"
fi

send_progress 30 "Permissions SSH configurées"

# ===============================================================================
# ÉTAPE 3 : CONFIGURATION DU MODULE RTC
# ===============================================================================

send_progress 35 "Configuration du module RTC..."

if ! setup_rtc_module; then
    echo "⚠ Erreur lors de la configuration du module RTC"
    log_error "Échec de la configuration du module RTC"
fi

send_progress 40 "Module RTC configuré"

# ===============================================================================
# ÉTAPE 4 : INFRASTRUCTURE D'ORCHESTRATION
# ===============================================================================

send_progress 45 "Installation de l'orchestrateur..."

if [ "$IS_FIRST_INSTALL" = true ]; then
    setup_orchestration_infrastructure
else
    echo ""
    echo "◦ Infrastructure d'orchestration déjà présente"
    log_info "Mise à jour - infrastructure existante conservée"
fi

send_progress 65 "Orchestrateur installé"

# ===============================================================================
# ÉTAPE 5 : RECHARGEMENT SYSTEMD
# ===============================================================================

send_progress 75 "Configuration systemd..."

echo ""
echo "========================================================================"
echo "CONFIGURATION SYSTEMD"
echo "========================================================================"

echo "◦ Rechargement de la configuration systemd..."
systemctl daemon-reload
echo "  ↦ Configuration rechargée ✓"
log_success "Systemd daemon-reload effectué"

send_progress 85 "Systemd configuré"

# ===============================================================================
# ÉTAPE 6 : CORRECTION FINALE DES PERMISSIONS
# ===============================================================================

send_progress 88 "Correction finale des permissions..."

# Appeler la nouvelle fonction de correction
fix_permissions_after_install

send_progress 90 "Permissions corrigées"

# ===============================================================================
# ÉTAPE 7 : ACTIVATION DES SERVICES
# ===============================================================================

send_progress 92 "Activation des services..."

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo ""
    echo "========================================================================"
    echo "ACTIVATION DE L'ORCHESTRATEUR"
    echo "========================================================================"
    
    /usr/local/bin/maxlink-orchestrator enable
    log_success "Services de l'orchestrateur activés"
else
    echo ""
    echo "◦ Services déjà configurés, pas de modification"
    log_info "Mise à jour - services existants conservés"
fi

send_progress 95 "Services activés"

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE"
echo "========================================================================"
echo ""

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "✓ L'orchestrateur MaxLink a été installé avec succès !"
    echo ""
    echo "Commandes disponibles :"
    echo "  maxlink-orchestrator start    - Démarrer tous les services"
    echo "  maxlink-orchestrator stop     - Arrêter tous les services"
    echo "  maxlink-orchestrator status   - Voir l'état des services"
    echo "  maxlink-orchestrator restart  - Redémarrer tous les services"
    echo ""
    echo "Script de maintenance des permissions :"
    echo "  /usr/local/bin/maxlink-fix-prod-permissions"
else
    echo "✓ L'orchestrateur MaxLink a été mis à jour avec succès !"
    echo ""
    echo "Les services existants ont été conservés."
fi

log_success "Installation de l'orchestrateur terminée"

# Indiquer que le script s'est terminé avec succès
exit 0