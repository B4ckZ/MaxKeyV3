#!/bin/bash

# ===============================================================================
# MAXLINK - SYSTÈME D'ORCHESTRATION AVEC SYSTEMD (VERSION CORRIGÉE)
# Script d'installation avec mise à jour du statut et gestion SKIP_REBOOT
# Version modifiée avec configuration ACL pour l'utilisateur prod
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Installation de l'orchestrateur MaxLink" "install"

# Répertoire local pour les widgets
LOCAL_WIDGETS_DIR="/opt/maxlink/widgets"
LOCAL_WIDGETS_CONFIG="/opt/maxlink/config/widgets"

# Flags pour déterminer ce qui doit être fait
IS_FIRST_INSTALL=false
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

# Vérifier si c'est la première installation
check_first_install() {
    if [ ! -d "/opt/maxlink" ] || [ ! -f "/etc/systemd/system/maxlink-network.target" ]; then
        IS_FIRST_INSTALL=true
        echo "◦ Première installation détectée"
        log_info "Première installation de l'orchestrateur"
    else
        echo "◦ Mise à jour détectée"
        log_info "Mise à jour de l'orchestrateur"
    fi
}

# Configuration du module RTC sur la prise BAT du Raspberry Pi 5
setup_rtc_module() {
    echo ""
    echo "========================================================================"
    echo "CONFIGURATION DU MODULE RTC"
    echo "========================================================================"
    
    # Vérifier si on est sur un Raspberry Pi 5
    if ! grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
        echo "⚠ Pas un Raspberry Pi 5, configuration RTC ignorée"
        log_warning "Configuration RTC ignorée - pas un Raspberry Pi 5"
        return 0
    fi
    
    echo "◦ Détection du module RTC..."
    
    # Vérifier d'abord si un RTC est déjà configuré
    if [ -e "/dev/rtc0" ] || [ -e "/dev/rtc" ]; then
        echo "  ↦ Module RTC déjà configuré ✓"
        
        # Tester si le RTC fonctionne
        if hwclock --show &>/dev/null; then
            echo "  ↦ RTC fonctionnel : $(hwclock --show 2>/dev/null | cut -d' ' -f1-4)"
            RTC_FOUND=true
            
            # Essayer de déterminer le type depuis dmesg
            if dmesg | grep -qi "ds3231"; then
                RTC_TYPE="ds3231"
            elif dmesg | grep -qi "ds1307"; then
                RTC_TYPE="ds1307"
            elif dmesg | grep -qi "pcf8523"; then
                RTC_TYPE="pcf8523"
            elif dmesg | grep -qi "pcf8563"; then
                RTC_TYPE="pcf8563"
            else
                # Type par défaut pour les modules sur connecteur BAT du Pi 5
                RTC_TYPE="ds3231"
            fi
            
            echo "  ↦ Type détecté/supposé : $RTC_TYPE"
        else
            echo "  ⚠ RTC présent mais non fonctionnel"
            RTC_FOUND=false
        fi
    else
        # Si pas de RTC configuré, essayer la détection I2C
        echo "  ↦ Pas de RTC configuré, tentative de détection I2C..."
        
        # Activer l'interface I2C si nécessaire
        if ! lsmod | grep -q i2c_dev; then
            echo "  ↦ Activation de l'interface I2C..."
            modprobe i2c-dev
            echo "i2c-dev" >> /etc/modules
        fi
        
        RTC_FOUND=false
        RTC_TYPE=""
        
        # Scanner tous les bus I2C possibles (0-3 pour Pi 5)
        for bus in 0 1 2 3; do
            if [ -e "/dev/i2c-$bus" ]; then
                if i2cdetect -y $bus 2>/dev/null | grep -q " 68 "; then
                    RTC_TYPE="ds3231"  # Par défaut pour 0x68
                    RTC_FOUND=true
                    echo "  ↦ Module trouvé sur I2C-$bus à l'adresse 0x68"
                    break
                elif i2cdetect -y $bus 2>/dev/null | grep -q " 6f "; then
                    RTC_TYPE="pcf8523"
                    RTC_FOUND=true
                    echo "  ↦ Module trouvé sur I2C-$bus à l'adresse 0x6f"
                    break
                elif i2cdetect -y $bus 2>/dev/null | grep -q " 51 "; then
                    RTC_TYPE="pcf8563"
                    RTC_FOUND=true
                    echo "  ↦ Module trouvé sur I2C-$bus à l'adresse 0x51"
                    break
                fi
            fi
        done
        
        if [ "$RTC_FOUND" = false ]; then
            echo "⚠ Aucun module RTC détecté"
            log_warning "Module RTC non détecté"
            return 0
        fi
    fi
    
    echo "  ↦ Module RTC détecté : $RTC_TYPE ✓"
    log_info "Module RTC $RTC_TYPE détecté"
    
    # Configurer le device tree overlay
    echo "◦ Configuration du device tree overlay..."
    
    # Vérifier si l'overlay n'est pas déjà configuré
    if ! grep -q "dtoverlay=i2c-rtc,$RTC_TYPE" /boot/firmware/config.txt 2>/dev/null && \
       ! grep -q "dtoverlay=i2c-rtc,$RTC_TYPE" /boot/config.txt 2>/dev/null; then
        
        # Déterminer le fichier de configuration (Pi 5 utilise /boot/firmware/config.txt)
        CONFIG_FILE="/boot/firmware/config.txt"
        if [ ! -f "$CONFIG_FILE" ]; then
            CONFIG_FILE="/boot/config.txt"
        fi
        
        # Ajouter l'overlay
        echo "" >> "$CONFIG_FILE"
        echo "# Configuration RTC ajoutée par MaxLink" >> "$CONFIG_FILE"
        echo "dtoverlay=i2c-rtc,$RTC_TYPE" >> "$CONFIG_FILE"
        echo "  ↦ Overlay ajouté au fichier de configuration ✓"
        log_success "Overlay RTC configuré dans $CONFIG_FILE"
        
        # Le module aura besoin d'un redémarrage
        NEED_REBOOT=true
    else
        echo "  ↦ Overlay déjà configuré ✓"
    fi
    
    # Vérifier les outils nécessaires
    echo "◦ Vérification des outils RTC..."
    
    # hwclock devrait être présent (util-linux)
    if ! command -v hwclock &> /dev/null; then
        echo "  ⚠ hwclock manquant - installation non standard"
        log_warning "hwclock non trouvé sur le système"
        return 1
    fi
    
    # i2c-tools devrait être installé par update_install.sh
    if ! command -v i2cdetect &> /dev/null; then
        echo "  ⚠ i2c-tools manquant"
        echo "  ↦ i2c-tools aurait dû être installé lors de l'étape de mise à jour"
        log_error "i2c-tools non trouvé - vérifier l'installation des paquets système"
        return 1
    fi
    
    echo "  ↦ Outils RTC disponibles ✓"
    
    # Créer un service pour synchroniser l'heure au démarrage
    echo "◦ Création du service de synchronisation RTC..."
    
    cat > /etc/systemd/system/maxlink-rtc-sync.service << EOF
[Unit]
Description=MaxLink RTC Time Synchronization
DefaultDependencies=no
Before=time-sync.target sysinit.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/hwclock --hctosys
ExecStop=/sbin/hwclock --systohc

[Install]
WantedBy=basic.target
EOF

    systemctl daemon-reload
    systemctl enable maxlink-rtc-sync.service &>/dev/null
    echo "  ↦ Service de synchronisation créé ✓"
    log_success "Service RTC configuré"
    
    # Désactiver le service fake-hwclock s'il existe
    if systemctl list-unit-files | grep -q fake-hwclock; then
        echo "◦ Désactivation de fake-hwclock..."
        systemctl disable fake-hwclock &>/dev/null
        systemctl stop fake-hwclock &>/dev/null
        echo "  ↦ fake-hwclock désactivé ✓"
    fi
    
    # Désactiver les services NTP
    echo "◦ Désactivation des services NTP (serveur hors ligne)..."
    
    # Désactiver systemd-timesyncd
    if systemctl list-unit-files | grep -q systemd-timesyncd; then
        systemctl disable systemd-timesyncd &>/dev/null
        systemctl stop systemd-timesyncd &>/dev/null
        echo "  ↦ systemd-timesyncd désactivé ✓"
    fi
    
    # Désactiver ntp si installé
    if systemctl list-unit-files | grep -q "^ntp.service"; then
        systemctl disable ntp &>/dev/null
        systemctl stop ntp &>/dev/null
        echo "  ↦ ntp désactivé ✓"
    fi
    
    # Désactiver chrony si installé
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
    
    # S'assurer que prod peut lire/écrire tous les fichiers existants
    find /var/www -type f -exec setfacl -m u:prod:rw {} \; 2>/dev/null || true
    find /var/www -type d -exec setfacl -m u:prod:rwx {} \; 2>/dev/null || true
    
    echo "  ↦ Permissions ACL configurées ✓"
    
    # Ajuster aussi les permissions classiques pour être sûr
    chown -R www-data:www-data /var/www
    chmod -R 755 /var/www
    
    # Ajouter prod au groupe www-data
    usermod -a -G www-data prod 2>/dev/null || true
    
    # Créer un script de maintenance des permissions
    cat > /usr/local/bin/maxlink-fix-prod-permissions << 'EOF'
#!/bin/bash
# Script de maintenance des permissions pour l'utilisateur prod

echo "Réparation des permissions pour l'utilisateur prod..."

# Réappliquer les ACL
setfacl -R -m u:prod:rwx /var/www
setfacl -R -d -m u:prod:rwx /var/www

# S'assurer que tous les fichiers sont accessibles
find /var/www -type f -exec setfacl -m u:prod:rw {} \; 2>/dev/null || true
find /var/www -type d -exec setfacl -m u:prod:rwx {} \; 2>/dev/null || true

echo "Permissions réparées."
EOF
    
    chmod +x /usr/local/bin/maxlink-fix-prod-permissions
    
    echo "  ↦ Script de maintenance créé : /usr/local/bin/maxlink-fix-prod-permissions"
    
    # Vérifier les permissions
    echo ""
    echo "◦ Vérification des permissions..."
    if getfacl /var/www 2>/dev/null | grep -q "user:prod:rwx"; then
        echo "  ↦ Permissions ACL vérifiées ✓"
        log_success "Permissions SSH configurées pour l'utilisateur prod"
        return 0
    else
        echo "  ⚠ Problème détecté avec les permissions ACL"
        log_error "Problème avec les permissions ACL"
        return 1
    fi
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
        
        echo "  ↦ Fichiers de configuration créés ✓"
        
        # Définir les permissions
        chown -R root:root "$LOCAL_WIDGETS_DIR"
        chmod -R 755 "$LOCAL_WIDGETS_DIR"
        
        log_success "Widgets copiés vers $LOCAL_WIDGETS_DIR"
        return 0
    else
        echo "⚠ Répertoire des widgets non trouvé : $BASE_DIR/widgets"
        log_error "Répertoire widgets non trouvé"
        return 1
    fi
}

# Créer les scripts de vérification de santé
create_healthcheck_scripts() {
    echo ""
    echo "◦ Création des scripts de vérification..."
    
    # Script de vérification réseau
    cat > /usr/local/bin/maxlink-check-network.sh << 'EOF'
#!/bin/bash
# Vérification de la santé du réseau MaxLink

echo "=== Network Health Check ==="
echo -n "Hostapd: "
systemctl is-active hostapd || exit 1
echo -n "Dnsmasq: "
systemctl is-active dnsmasq || exit 1
echo -n "AP Interface: "
ip link show ap0 2>/dev/null | grep -q "state UP" && echo "UP" || exit 1
echo "Network: OK"
exit 0
EOF

    # Script de vérification MQTT
    cat > /usr/local/bin/maxlink-check-mqtt.sh << 'EOF'
#!/bin/bash
# Vérification de la santé MQTT

echo "=== MQTT Health Check ==="
echo -n "Mosquitto: "
systemctl is-active mosquitto || exit 1
echo -n "Port 1883: "
netstat -tlnp 2>/dev/null | grep -q ":1883" && echo "LISTENING" || exit 1
echo "MQTT: OK"
exit 0
EOF

    # Script de vérification des widgets
    cat > /usr/local/bin/maxlink-check-widgets.sh << 'EOF'
#!/bin/bash
# Vérification de la santé des widgets

echo "=== Widgets Health Check ==="
FAILED=0
for service in $(systemctl list-units 'maxlink-widget-*' --no-legend | awk '{print $1}'); do
    echo -n "${service}: "
    if systemctl is-active "$service" >/dev/null 2>&1; then
        echo "ACTIVE"
    else
        echo "FAILED"
        FAILED=$((FAILED + 1))
    fi
done

if [ $FAILED -eq 0 ]; then
    echo "Widgets: OK"
    exit 0
else
    echo "Widgets: $FAILED FAILED"
    exit 1
fi
EOF

    chmod +x /usr/local/bin/maxlink-check-*.sh
    echo "  ↦ Scripts de vérification créés ✓"
    log_success "Scripts healthcheck créés"
}

# Créer les services systemd
create_systemd_services() {
    echo ""
    echo "◦ Création des services systemd..."
    
    # Service de vérification réseau
    cat > /etc/systemd/system/maxlink-network-ready.service << EOF
[Unit]
Description=MaxLink Network Ready Check
After=hostapd.service dnsmasq.service
Wants=hostapd.service dnsmasq.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/maxlink-check-network.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Service de vérification MQTT
    cat > /etc/systemd/system/maxlink-mqtt-ready.service << EOF
[Unit]
Description=MaxLink MQTT Ready Check
After=mosquitto.service maxlink-network-ready.service
Requires=mosquitto.service maxlink-network-ready.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/maxlink-check-mqtt.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Service de vérification des widgets
    cat > /etc/systemd/system/maxlink-widgets-ready.service << EOF
[Unit]
Description=MaxLink Widgets Ready Check
After=maxlink-mqtt-ready.service
Requires=maxlink-mqtt-ready.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/sleep 30
ExecStart=/usr/local/bin/maxlink-check-widgets.sh
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Service de monitoring global
    cat > /etc/systemd/system/maxlink-health-monitor.service << EOF
[Unit]
Description=MaxLink Health Monitor
After=maxlink-widgets-ready.service
Requires=maxlink-widgets-ready.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /usr/local/bin/maxlink-check-network.sh && /usr/local/bin/maxlink-check-mqtt.sh && /usr/local/bin/maxlink-check-widgets.sh; sleep 300; done'
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Services de supervision créés ✓"
    log_success "Services systemd créés"
}

# Créer les targets systemd
create_systemd_targets() {
    echo ""
    echo "◦ Création des targets systemd..."
    
    # Target réseau
    cat > /etc/systemd/system/maxlink-network.target << EOF
[Unit]
Description=MaxLink Network Services
Requires=hostapd.service dnsmasq.service maxlink-network-ready.service
After=hostapd.service dnsmasq.service maxlink-network-ready.service

[Install]
WantedBy=multi-user.target
EOF

    # Target core (MQTT + Nginx)
    cat > /etc/systemd/system/maxlink-core.target << EOF
[Unit]
Description=MaxLink Core Services
Requires=maxlink-network.target mosquitto.service nginx.service maxlink-mqtt-ready.service
After=maxlink-network.target mosquitto.service nginx.service maxlink-mqtt-ready.service

[Install]
WantedBy=multi-user.target
EOF

    # Target widgets
    cat > /etc/systemd/system/maxlink-widgets.target << EOF
[Unit]
Description=MaxLink Widget Services
Requires=maxlink-core.target maxlink-widgets-ready.service
After=maxlink-core.target maxlink-widgets-ready.service

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Targets systemd créés ✓"
    log_success "Targets systemd créés"
}

# Configurer les overrides pour les services existants
setup_service_overrides() {
    echo ""
    echo "◦ Configuration des dépendances des services existants..."
    
    # Override pour Mosquitto
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat > /etc/systemd/system/mosquitto.service.d/maxlink.conf << EOF
[Unit]
PartOf=maxlink-core.target
After=maxlink-network-ready.service

[Service]
Restart=always
RestartSec=10
EOF

    # Override pour Nginx
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/maxlink.conf << EOF
[Unit]
PartOf=maxlink-core.target
After=maxlink-network-ready.service

[Service]
Restart=always
RestartSec=10
EOF

    # Override pour les widgets (exemple avec system-stats)
    if [ -f /etc/systemd/system/maxlink-widget-system-stats.service ]; then
        mkdir -p /etc/systemd/system/maxlink-widget-system-stats.service.d
        cat > /etc/systemd/system/maxlink-widget-system-stats.service.d/maxlink.conf << EOF
[Unit]
PartOf=maxlink-widgets.target
After=maxlink-mqtt-ready.service
Requires=maxlink-mqtt-ready.service

[Service]
Restart=always
RestartSec=30
EOF
    fi

    echo "  ↦ Dépendances configurées ✓"
    log_success "Overrides systemd configurés"
}

# Créer le script de gestion
create_management_script() {
    echo ""
    echo "◦ Création du script de gestion..."
    
    cat > /usr/local/bin/maxlink-orchestrator << 'EOF'
#!/bin/bash
# Script de gestion de l'orchestrateur MaxLink

case "$1" in
    status)
        echo "=== MaxLink Orchestrator Status ==="
        echo ""
        echo "Targets:"
        systemctl status maxlink-network.target --no-pager | grep "Active:"
        systemctl status maxlink-core.target --no-pager | grep "Active:"
        systemctl status maxlink-widgets.target --no-pager | grep "Active:"
        echo ""
        echo "Services:"
        systemctl status mosquitto --no-pager | grep "Active:"
        systemctl status nginx --no-pager | grep "Active:"
        echo ""
        echo "Widgets:"
        systemctl list-units 'maxlink-widget-*' --no-pager
        ;;
        
    check)
        echo "=== MaxLink Health Check ==="
        /usr/local/bin/maxlink-check-network.sh
        /usr/local/bin/maxlink-check-mqtt.sh
        /usr/local/bin/maxlink-check-widgets.sh
        ;;
        
    restart-all)
        echo "Redémarrage complet de MaxLink..."
        systemctl restart maxlink-network.target
        sleep 2
        systemctl restart maxlink-core.target
        sleep 2
        systemctl restart maxlink-widgets.target
        echo "Redémarrage terminé."
        ;;
        
    restart-widgets)
        echo "Redémarrage des widgets uniquement..."
        systemctl restart maxlink-widgets.target
        echo "Widgets redémarrés."
        ;;
        
    logs)
        case "$2" in
            mqtt)
                journalctl -u mosquitto -u maxlink-mqtt-ready -f
                ;;
            widgets)
                journalctl -u 'maxlink-widget-*' -f
                ;;
            network)
                journalctl -u hostapd -u dnsmasq -u maxlink-network-ready -f
                ;;
            all|*)
                journalctl -u maxlink-* -u mosquitto -u nginx -u hostapd -u dnsmasq -f
                ;;
        esac
        ;;
        
    enable)
        echo "Activation de l'orchestrateur..."
        systemctl enable maxlink-health-monitor.service
        systemctl enable maxlink-widgets-ready.service
        systemctl enable maxlink-mqtt-ready.service
        systemctl enable maxlink-network-ready.service
        systemctl enable maxlink-widgets.target
        systemctl enable maxlink-core.target
        systemctl enable maxlink-network.target
        echo "Orchestrateur activé."
        ;;
        
    disable)
        echo "Désactivation de l'orchestrateur..."
        systemctl disable maxlink-health-monitor.service
        systemctl disable maxlink-widgets-ready.service
        systemctl disable maxlink-mqtt-ready.service
        systemctl disable maxlink-network-ready.service
        systemctl disable maxlink-widgets.target
        systemctl disable maxlink-core.target
        systemctl disable maxlink-network.target
        echo "Orchestrateur désactivé."
        ;;
        
    *)
        echo "MaxLink Orchestrator Control"
        echo ""
        echo "Usage: $0 {status|check|restart-all|restart-widgets|logs|enable|disable}"
        echo ""
        echo "  status          - Afficher l'état de tous les services"
        echo "  check           - Vérifier la santé du système"
        echo "  restart-all     - Redémarrer tous les services dans l'ordre"
        echo "  restart-widgets - Redémarrer uniquement les widgets"
        echo "  logs [service]  - Afficher les logs (mqtt|widgets|network|all)"
        echo "  enable          - Activer l'orchestrateur au démarrage"
        echo "  disable         - Désactiver l'orchestrateur"
        echo ""
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/maxlink-orchestrator
    echo "  ↦ Script de gestion créé ✓"
    log_success "Script de gestion créé"
}

# Créer l'infrastructure d'orchestration
setup_orchestration_infrastructure() {
    echo ""
    echo "========================================================================"
    echo "INSTALLATION DE L'INFRASTRUCTURE D'ORCHESTRATION"
    echo "========================================================================"
    create_healthcheck_scripts
    create_systemd_services
    create_systemd_targets
    setup_service_overrides
    create_management_script
    NEED_REBOOT=true
}

# ===============================================================================
# VÉRIFICATIONS
# ===============================================================================

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "⚠ Ce script doit être exécuté avec des privilèges root"
    log_error "Privilèges root requis"
    exit 1
fi

echo ""
echo "========================================================================"
echo "ORCHESTRATEUR MAXLINK - INSTALLATION"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier si c'est la première installation
check_first_install

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
# ÉTAPE 6 : ACTIVATION DES SERVICES
# ===============================================================================

send_progress 90 "Activation des services..."

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
    echo "L'infrastructure d'orchestration suivante a été mise en place :"
    echo "  • Scripts de vérification de santé"
    echo "  • Services systemd pour la supervision"
    echo "  • Targets systemd pour l'organisation des services"
    echo "  • Script de gestion : maxlink-orchestrator"
    echo "  • Permissions SSH complètes pour l'utilisateur 'prod' dans /var/www/"
    echo "  • Module RTC configuré (si détecté)"
    echo "  • Services NTP désactivés (fonctionnement hors ligne)"
    echo ""
    echo "Les widgets ont été copiés vers : /opt/maxlink/widgets/"
    echo ""
    log_success "Installation de l'orchestrateur terminée"
else
    echo "✓ L'orchestrateur MaxLink a été mis à jour avec succès !"
    echo ""
    echo "  • Les widgets ont été mis à jour"
    echo "  • L'infrastructure existante a été conservée"
    echo "  • Permissions SSH configurées pour l'utilisateur 'prod'"
    echo "  • Configuration RTC vérifiée"
    echo ""
    log_success "Mise à jour de l'orchestrateur terminée"
fi

echo "Commandes disponibles :"
echo "  • sudo maxlink-orchestrator status    - État du système"
echo "  • sudo maxlink-orchestrator check     - Vérification de santé"
echo "  • sudo maxlink-orchestrator logs all  - Voir tous les logs"
echo ""

# Gestion du redémarrage
if [ "$NEED_REBOOT" = true ] && [ -z "$SKIP_REBOOT" ]; then
    echo "⚠ Un redémarrage est nécessaire pour finaliser l'installation"
    echo ""
    echo "Le système sera redémarré automatiquement dans 10 secondes..."
    echo "Pour annuler : Ctrl+C"
    echo ""
    
    for i in {10..1}; do
        echo -ne "\rRedémarrage dans $i secondes... "
        sleep 1
    done
    echo ""
    
    log_info "Redémarrage du système pour finalisation"
    systemctl reboot
elif [ "$NEED_REBOOT" = true ] && [ -n "$SKIP_REBOOT" ]; then
    echo "⚠ Un redémarrage est nécessaire mais a été ignoré (SKIP_REBOOT actif)"
    echo "  Pensez à redémarrer manuellement plus tard."
    log_warning "Redémarrage nécessaire mais ignoré (SKIP_REBOOT)"
fi

echo "========================================================================"