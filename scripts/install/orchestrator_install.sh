#!/bin/bash

# ===============================================================================
# MAXLINK - SYSTÈME D'ORCHESTRATION AVEC SYSTEMD (VERSION CORRIGÉE)
# Script d'installation avec mise à jour du statut et gestion SKIP_REBOOT
# Ajout de la création du compte SSH administrateur
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

# Copier tous les widgets depuis la clé USB vers local
copy_widgets_to_local() {
    echo ""
    echo "◦ Copie des widgets vers le système local..."
    log_info "Copie des widgets depuis $BASE_DIR/scripts/widgets vers /opt/maxlink"
    
    # Créer les répertoires si nécessaire
    mkdir -p "$LOCAL_WIDGETS_DIR"
    mkdir -p "$LOCAL_WIDGETS_CONFIG"
    
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
# FONCTION : CRÉATION DU COMPTE SSH ADMINISTRATEUR
# ===============================================================================

setup_ssh_admin_account() {
    echo ""
    echo "========================================================================"
    echo "CRÉATION DU COMPTE SSH ADMINISTRATEUR"
    echo "========================================================================"
    
    send_progress 35 "Création du compte SSH administrateur..."
    
    # Vérifier si l'utilisateur existe déjà
    if id "$SSH_ADMIN_USER" &>/dev/null; then
        echo "◦ L'utilisateur $SSH_ADMIN_USER existe déjà"
        log_info "Utilisateur $SSH_ADMIN_USER existe déjà, mise à jour..."
        
        # Supprimer l'utilisateur pour le recréer proprement
        echo "  ↦ Suppression de l'ancien compte..."
        userdel -r "$SSH_ADMIN_USER" 2>/dev/null || true
        wait_silently 1
    fi
    
    # Créer l'utilisateur avec home directory
    echo "◦ Création de l'utilisateur $SSH_ADMIN_USER..."
    useradd -m -d "$SSH_ADMIN_HOME" -s "$SSH_ADMIN_SHELL" -c "MaxLink SSH Admin" "$SSH_ADMIN_USER"
    
    if [ $? -eq 0 ]; then
        echo "  ↦ Utilisateur créé ✓"
        log_success "Utilisateur $SSH_ADMIN_USER créé"
    else
        echo "  ↦ Erreur lors de la création de l'utilisateur ✗"
        log_error "Impossible de créer l'utilisateur $SSH_ADMIN_USER"
        return 1
    fi
    
    # Définir le mot de passe
    echo "◦ Configuration du mot de passe..."
    echo "$SSH_ADMIN_USER:$SSH_ADMIN_PASS" | chpasswd
    
    if [ $? -eq 0 ]; then
        echo "  ↦ Mot de passe configuré ✓"
        log_success "Mot de passe configuré pour $SSH_ADMIN_USER"
    else
        echo "  ↦ Erreur lors de la configuration du mot de passe ✗"
        log_error "Impossible de configurer le mot de passe"
        return 1
    fi
    
    # Ajouter aux groupes nécessaires
    echo "◦ Ajout aux groupes système..."
    for group in $(echo $SSH_ADMIN_GROUPS | tr ',' ' '); do
        usermod -a -G "$group" "$SSH_ADMIN_USER" 2>/dev/null && \
            echo "  ↦ Ajouté au groupe $group ✓" || \
            echo "  ↦ Groupe $group ignoré (n'existe pas)"
    done
    log_success "Utilisateur ajouté aux groupes: $SSH_ADMIN_GROUPS"
    
    # Configuration sudo sans mot de passe
    echo "◦ Configuration des privilèges sudo..."
    cat > "/etc/sudoers.d/50-$SSH_ADMIN_USER" <<EOF
# MaxLink SSH Admin - Full sudo access without password
$SSH_ADMIN_USER ALL=(ALL) NOPASSWD: ALL
EOF
    chmod 440 "/etc/sudoers.d/50-$SSH_ADMIN_USER"
    echo "  ↦ Privilèges sudo configurés (NOPASSWD) ✓"
    log_success "Privilèges sudo configurés pour $SSH_ADMIN_USER"
    
    # Créer le répertoire de logs
    if [ "$SSH_ADMIN_ENABLE_LOGGING" = true ]; then
        echo "◦ Configuration du logging SSH..."
        mkdir -p "$SSH_ADMIN_LOG_DIR"
        touch "$SSH_ADMIN_LOG_FILE"
        touch "$SSH_ADMIN_AUDIT_FILE"
        chmod 750 "$SSH_ADMIN_LOG_DIR"
        chown root:adm "$SSH_ADMIN_LOG_DIR"
        chmod 640 "$SSH_ADMIN_LOG_FILE" "$SSH_ADMIN_AUDIT_FILE"
        chown root:adm "$SSH_ADMIN_LOG_FILE" "$SSH_ADMIN_AUDIT_FILE"
        echo "  ↦ Répertoire de logs créé ✓"
        log_success "Logging SSH configuré dans $SSH_ADMIN_LOG_DIR"
    fi
    
    # Configurer le logging des connexions SSH
    if [ "$SSH_ADMIN_ENABLE_LOGGING" = true ]; then
        echo "◦ Configuration du logging des connexions..."
        
        # Ajouter au .bashrc pour logger les connexions
        cat >> "$SSH_ADMIN_HOME/.bashrc" <<'EOF'

# MaxLink SSH Admin Logging
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SSH Login: $USER from ${SSH_CLIENT%% *} (TTY: $(tty))" >> /var/log/maxlink/ssh_admin/access.log
fi

# Activer l'historique des commandes avec timestamp
export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "
export HISTFILE="$HOME/.bash_history"
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend
EOF
        chown "$SSH_ADMIN_USER:$SSH_ADMIN_USER" "$SSH_ADMIN_HOME/.bashrc"
        echo "  ↦ Logging des connexions configuré ✓"
    fi
    
    # Configurer l'audit des commandes sudo
    if [ "$SSH_ADMIN_ENABLE_AUDIT" = true ]; then
        echo "◦ Configuration de l'audit sudo..."
        
        # Créer un wrapper pour sudo avec logging
        cat > "/usr/local/bin/sudo-audit" <<'EOF'
#!/bin/bash
# MaxLink Sudo Audit Wrapper

AUDIT_LOG="/var/log/maxlink/ssh_admin/audit.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
REAL_USER="${SUDO_USER:-$USER}"
COMMAND="$@"

# Logger la commande
echo "[$TIMESTAMP] User: $REAL_USER | Command: sudo $COMMAND" >> "$AUDIT_LOG"

# Exécuter la vraie commande sudo
/usr/bin/sudo "$@"
EOF
        
        chmod 755 /usr/local/bin/sudo-audit
        
        # Ajouter l'alias dans .bashrc
        echo 'alias sudo="/usr/local/bin/sudo-audit"' >> "$SSH_ADMIN_HOME/.bashrc"
        
        echo "  ↦ Audit des commandes sudo configuré ✓"
        log_success "Audit sudo configuré"
    fi
    
    # Configuration SSH pour s'assurer que l'authentification par mot de passe est activée
    echo "◦ Configuration du service SSH..."
    
    # Backup de la config SSH
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    
    # S'assurer que l'authentification par mot de passe est activée
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    
    # Ajouter une configuration spécifique pour notre utilisateur
    if ! grep -q "Match User $SSH_ADMIN_USER" /etc/ssh/sshd_config; then
        cat >> /etc/ssh/sshd_config <<EOF

# MaxLink SSH Admin Configuration
Match User $SSH_ADMIN_USER
    PasswordAuthentication yes
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTunnel no
EOF
    fi
    
    echo "  ↦ Configuration SSH mise à jour ✓"
    
    # Redémarrer le service SSH
    systemctl restart ssh || systemctl restart sshd
    echo "  ↦ Service SSH redémarré ✓"
    log_success "Service SSH configuré et redémarré"
    
    # Créer un fichier .ssh/authorized_keys vide pour futures clés
    mkdir -p "$SSH_ADMIN_HOME/.ssh"
    touch "$SSH_ADMIN_HOME/.ssh/authorized_keys"
    chmod 700 "$SSH_ADMIN_HOME/.ssh"
    chmod 600 "$SSH_ADMIN_HOME/.ssh/authorized_keys"
    chown -R "$SSH_ADMIN_USER:$SSH_ADMIN_USER" "$SSH_ADMIN_HOME/.ssh"
    
    # Définir les permissions sur les répertoires importants
    echo "◦ Configuration des permissions..."
    
    # Dashboard nginx
    usermod -a -G www-data "$SSH_ADMIN_USER"
    setfacl -R -m u:$SSH_ADMIN_USER:rwx "$NGINX_DASHBOARD_DIR" 2>/dev/null || \
        chmod -R 775 "$NGINX_DASHBOARD_DIR"
    
    # Répertoire MaxLink
    setfacl -R -m u:$SSH_ADMIN_USER:rwx /opt/maxlink 2>/dev/null || \
        chmod -R 775 /opt/maxlink
    
    # Logs
    setfacl -R -m u:$SSH_ADMIN_USER:r /var/log 2>/dev/null || true
    
    echo "  ↦ Permissions configurées ✓"
    
    # Créer un script de test de connexion
    cat > "/usr/local/bin/test-ssh-admin" <<EOF
#!/bin/bash
echo "Test de connexion SSH pour $SSH_ADMIN_USER"
echo "=================================="
echo "Utilisateur: $SSH_ADMIN_USER"
echo "Mot de passe: $SSH_ADMIN_PASS"
echo "Connexion SSH: ssh $SSH_ADMIN_USER@\$(hostname -I | awk '{print \$1}')"
echo "Connexion SFTP: sftp://$SSH_ADMIN_USER@\$(hostname -I | awk '{print \$1}')"
echo ""
echo "Répertoires accessibles:"
echo "  - Dashboard: $NGINX_DASHBOARD_DIR"
echo "  - MaxLink: /opt/maxlink"
echo "  - Logs: $SSH_ADMIN_LOG_DIR"
echo ""
echo "Groupes: \$(groups $SSH_ADMIN_USER | cut -d: -f2)"
echo "=================================="
EOF
    chmod 755 /usr/local/bin/test-ssh-admin
    
    echo ""
    echo "========================================================================"
    echo "✓ COMPTE SSH ADMINISTRATEUR CRÉÉ AVEC SUCCÈS"
    echo "========================================================================"
    echo "Utilisateur: $SSH_ADMIN_USER"
    echo "Mot de passe: $SSH_ADMIN_PASS"
    echo "Accès: SSH/SFTP avec privilèges sudo complets (NOPASSWD)"
    echo "Logs: $SSH_ADMIN_LOG_DIR"
    echo ""
    echo "Pour tester: sudo /usr/local/bin/test-ssh-admin"
    echo "========================================================================"
    
    log_success "Compte SSH administrateur $SSH_ADMIN_USER créé avec succès"
    
    # Créer une entrée de log initiale
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Compte SSH Admin créé par l'installation MaxLink" > "$SSH_ADMIN_LOG_FILE"
    
    return 0
}

# ===============================================================================
# FONCTIONS EXISTANTES (inchangées)
# ===============================================================================

# Créer les scripts de healthcheck
create_healthcheck_scripts() {
    echo ""
    echo "◦ Création des scripts de vérification..."
    
    # Script pour vérifier la connectivité réseau
    cat > /usr/local/bin/maxlink-check-network <<'EOF'
#!/bin/bash
# Vérifier si le réseau est prêt (interface wlan0 up avec une IP)
if ip addr show wlan0 | grep -q "state UP" && ip addr show wlan0 | grep -q "inet "; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x /usr/local/bin/maxlink-check-network
    echo "  ↦ Script de vérification réseau créé ✓"
    
    # Script pour vérifier MQTT
    cat > /usr/local/bin/maxlink-check-mqtt <<'EOF'
#!/bin/bash
# Vérifier si Mosquitto est actif et répond
if systemctl is-active --quiet mosquitto && mosquitto_sub -h localhost -t '$SYS/#' -C 1 -W 2 >/dev/null 2>&1; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x /usr/local/bin/maxlink-check-mqtt
    echo "  ↦ Script de vérification MQTT créé ✓"
    
    # Script pour vérifier que tous les widgets sont prêts
    cat > /usr/local/bin/maxlink-check-widgets <<'EOF'
#!/bin/bash
# Vérifier que tous les services de widgets sont actifs
WIDGET_SERVICES=$(systemctl list-units --type=service --all | grep -E "maxlink.*widget.*\.service" | awk '{print $1}')

if [ -z "$WIDGET_SERVICES" ]; then
    # Pas de widgets, considérer comme prêt
    exit 0
fi

for service in $WIDGET_SERVICES; do
    if ! systemctl is-active --quiet "$service"; then
        exit 1
    fi
done
exit 0
EOF
    chmod +x /usr/local/bin/maxlink-check-widgets
    echo "  ↦ Script de vérification widgets créé ✓"
    
    log_success "Scripts de healthcheck créés"
}

# Créer les services systemd de notification
create_systemd_services() {
    echo ""
    echo "◦ Création des services de notification..."
    
    # Service pour notifier quand le réseau est prêt
    cat > /etc/systemd/system/maxlink-network-ready.service <<EOF
[Unit]
Description=MaxLink Network Ready Notification
After=network-online.target hostapd.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'until /usr/local/bin/maxlink-check-network; do sleep 2; done'
ExecStart=/bin/bash -c 'echo "MaxLink: Network is ready"'
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Service network-ready créé ✓"
    
    # Service pour notifier quand MQTT est prêt
    cat > /etc/systemd/system/maxlink-mqtt-ready.service <<EOF
[Unit]
Description=MaxLink MQTT Ready Notification
After=mosquitto.service maxlink-network-ready.service
Wants=mosquitto.service
Requires=maxlink-network-ready.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'until /usr/local/bin/maxlink-check-mqtt; do sleep 2; done'
ExecStart=/bin/bash -c 'echo "MaxLink: MQTT broker is ready"'
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Service mqtt-ready créé ✓"
    
    # Service pour notifier quand tous les widgets sont prêts
    cat > /etc/systemd/system/maxlink-widgets-ready.service <<EOF
[Unit]
Description=MaxLink Widgets Ready Notification
After=maxlink-mqtt-ready.service
Requires=maxlink-mqtt-ready.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/bin/bash -c 'until /usr/local/bin/maxlink-check-widgets; do sleep 2; done'
ExecStart=/bin/bash -c 'echo "MaxLink: All widgets are ready"'
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Service widgets-ready créé ✓"
    
    # Service de monitoring global
    cat > /etc/systemd/system/maxlink-health-monitor.service <<EOF
[Unit]
Description=MaxLink Health Monitor
After=maxlink-widgets-ready.service
Wants=maxlink-widgets-ready.service

[Service]
Type=simple
Restart=always
RestartSec=30
ExecStart=/bin/bash -c 'while true; do \
    if /usr/local/bin/maxlink-check-network && \
       /usr/local/bin/maxlink-check-mqtt && \
       /usr/local/bin/maxlink-check-widgets; then \
        echo "MaxLink: System healthy"; \
    else \
        echo "MaxLink: System degraded"; \
    fi; \
    sleep 60; \
done'

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Service health-monitor créé ✓"
    
    log_success "Services systemd créés"
}

# Créer les targets systemd pour l'orchestration
create_systemd_targets() {
    echo ""
    echo "◦ Création des targets systemd..."
    
    # Target pour les services réseau de base
    cat > /etc/systemd/system/maxlink-network.target <<EOF
[Unit]
Description=MaxLink Network Services
After=network-online.target
Wants=hostapd.service nginx.service
Requires=network-online.target

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Target network créé ✓"
    
    # Target pour les services core (MQTT)
    cat > /etc/systemd/system/maxlink-core.target <<EOF
[Unit]
Description=MaxLink Core Services
After=maxlink-network.target maxlink-network-ready.service
Wants=mosquitto.service
Requires=maxlink-network.target

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Target core créé ✓"
    
    # Target pour tous les widgets
    cat > /etc/systemd/system/maxlink-widgets.target <<EOF
[Unit]
Description=MaxLink Widget Services
After=maxlink-core.target maxlink-mqtt-ready.service
Requires=maxlink-core.target maxlink-mqtt-ready.service

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Target widgets créé ✓"
    
    log_success "Targets systemd créés"
}

# Configurer les overrides pour les services existants
setup_service_overrides() {
    echo ""
    echo "◦ Configuration des dépendances des services..."
    
    # Override pour hostapd
    mkdir -p /etc/systemd/system/hostapd.service.d
    cat > /etc/systemd/system/hostapd.service.d/maxlink.conf <<EOF
[Unit]
PartOf=maxlink-network.target
Before=maxlink-network-ready.service

[Service]
Restart=always
RestartSec=5
EOF
    echo "  ↦ Override hostapd configuré ✓"
    
    # Override pour mosquitto
    mkdir -p /etc/systemd/system/mosquitto.service.d
    cat > /etc/systemd/system/mosquitto.service.d/maxlink.conf <<EOF
[Unit]
PartOf=maxlink-core.target
After=maxlink-network-ready.service
Before=maxlink-mqtt-ready.service

[Service]
Restart=always
RestartSec=5
EOF
    echo "  ↦ Override mosquitto configuré ✓"
    
    # Override pour nginx
    mkdir -p /etc/systemd/system/nginx.service.d
    cat > /etc/systemd/system/nginx.service.d/maxlink.conf <<EOF
[Unit]
PartOf=maxlink-network.target
After=network-online.target

[Service]
Restart=always
RestartSec=5
EOF
    echo "  ↦ Override nginx configuré ✓"
    
    log_success "Overrides de services configurés"
}

# Recharger et activer tous les services
enable_orchestration_services() {
    echo ""
    echo "◦ Activation des services d'orchestration..."
    
    # Recharger systemd
    systemctl daemon-reload
    
    # Activer les targets
    systemctl enable maxlink-network.target
    systemctl enable maxlink-core.target
    systemctl enable maxlink-widgets.target
    echo "  ↦ Targets activés ✓"
    
    # Activer les services de notification
    systemctl enable maxlink-network-ready.service
    systemctl enable maxlink-mqtt-ready.service
    systemctl enable maxlink-widgets-ready.service
    systemctl enable maxlink-health-monitor.service
    echo "  ↦ Services de notification activés ✓"
    
    log_success "Services d'orchestration activés"
}

# Créer le script de gestion
create_management_script() {
    echo ""
    echo "◦ Création du script de gestion..."
    
    cat > /usr/local/bin/maxlink-orchestrator <<'EOF'
#!/bin/bash

case "$1" in
    status)
        echo "=== MaxLink System Status ==="
        echo ""
        echo "Network Services:"
        systemctl status maxlink-network.target --no-pager | grep -E "Active:|● "
        echo ""
        echo "Core Services:"
        systemctl status maxlink-core.target --no-pager | grep -E "Active:|● "
        echo ""
        echo "Widget Services:"
        systemctl status maxlink-widgets.target --no-pager | grep -E "Active:|● "
        echo ""
        echo "Health Monitor:"
        systemctl status maxlink-health-monitor.service --no-pager | grep "Active:"
        ;;
        
    check)
        echo "=== MaxLink Health Check ==="
        echo -n "Network: "
        /usr/local/bin/maxlink-check-network && echo "OK" || echo "FAILED"
        echo -n "MQTT: "
        /usr/local/bin/maxlink-check-mqtt && echo "OK" || echo "FAILED"
        echo -n "Widgets: "
        /usr/local/bin/maxlink-check-widgets && echo "OK" || echo "FAILED"
        ;;
        
    restart-all)
        echo "Redémarrage de tous les services MaxLink..."
        systemctl restart maxlink-network.target
        sleep 5
        systemctl restart maxlink-core.target
        sleep 5
        systemctl restart maxlink-widgets.target
        echo "Redémarrage terminé."
        ;;
        
    restart-widgets)
        echo "Redémarrage des widgets..."
        systemctl restart maxlink-widgets.target
        echo "Widgets redémarrés."
        ;;
        
    logs)
        case "$2" in
            mqtt)
                journalctl -u mosquitto -f
                ;;
            widgets)
                journalctl -u "maxlink-*-widget.service" -f
                ;;
            network)
                journalctl -u hostapd -u nginx -f
                ;;
            all|*)
                journalctl -u "maxlink-*" -u mosquitto -u hostapd -u nginx -f
                ;;
        esac
        ;;
        
    enable)
        echo "Activation de l'orchestrateur..."
        systemctl enable maxlink-network.target
        systemctl enable maxlink-core.target
        systemctl enable maxlink-widgets.target
        systemctl enable maxlink-health-monitor.service
        systemctl enable maxlink-widgets-ready.service
        systemctl enable maxlink-mqtt-ready.service
        systemctl enable maxlink-network-ready.service
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
    echo "⚠ Problème lors de la copie des widgets, mais on continue..."
    log_warn "Copie des widgets incomplète, poursuite de l'installation"
fi

# ===============================================================================
# ÉTAPE 2 : CRÉATION DU COMPTE SSH ADMINISTRATEUR
# ===============================================================================

send_progress 30 "Création du compte SSH administrateur..."

if ! setup_ssh_admin_account; then
    echo "⚠ Problème lors de la création du compte SSH, mais on continue..."
    log_warn "Création du compte SSH incomplète, poursuite de l'installation"
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
            
            echo ""
            echo "◦ Installation du widget $widget_name ($CURRENT_WIDGET/$WIDGET_COUNT)..."
            
            if [ -f "$install_script" ]; then
                # Exécuter depuis le répertoire local
                cd "$widget_dir"
                if bash "$install_script"; then
                    echo "  ↦ Widget $widget_name installé ✓"
                    log_success "Widget $widget_name installé"
                else
                    echo "  ↦ Échec de l'installation du widget $widget_name ✗"
                    log_error "Échec installation widget $widget_name"
                fi
                cd - >/dev/null
            else
                echo "  ↦ Script d'installation manquant pour $widget_name"
                log_warn "Script installation manquant: $install_script"
            fi
            
            send_progress $WIDGET_PROGRESS "Widget $widget_name traité..."
        fi
    done
fi

# ===============================================================================
# ÉTAPE 4 : INFRASTRUCTURE D'ORCHESTRATION
# ===============================================================================

send_progress 85 "Configuration de l'orchestration..."

if [ "$IS_FIRST_INSTALL" = true ]; then
    setup_orchestration_infrastructure
else
    echo ""
    echo "◦ Infrastructure d'orchestration déjà en place"
    log_info "Infrastructure d'orchestration existante conservée"
fi

# ===============================================================================
# ÉTAPE 5 : ACTIVATION DES SERVICES
# ===============================================================================

send_progress 95 "Activation des services..."

if [ "$IS_FIRST_INSTALL" = true ]; then
    enable_orchestration_services
else
    echo ""
    echo "◦ Rechargement de la configuration systemd..."
    systemctl daemon-reload
    echo "  ↦ Configuration rechargée ✓"
    log_info "Configuration systemd rechargée"
fi

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

# Mettre à jour le statut du service
update_service_status "orchestrator" "active" "Installation réussie"

echo ""
echo "========================================================================"
echo "✓ INSTALLATION DE L'ORCHESTRATEUR TERMINÉE"
echo "========================================================================"
echo ""

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "L'orchestrateur MaxLink a été installé avec succès."
    echo ""
    echo "Composants installés :"
    echo "  • Scripts de vérification (healthcheck)"
    echo "  • Services systemd de notification"
    echo "  • Targets systemd pour l'orchestration"
    echo "  • Script de gestion : /usr/local/bin/maxlink-orchestrator"
    echo "  • Compte SSH Admin : $SSH_ADMIN_USER (mot de passe: $SSH_ADMIN_PASS)"
    echo ""
    echo "Les services seront orchestrés automatiquement au prochain démarrage."
else
    echo "L'orchestrateur MaxLink a été mis à jour."
    echo ""
    echo "Modifications appliquées :"
    echo "  • Widgets mis à jour"
    echo "  • Configuration rechargée"
    if id "$SSH_ADMIN_USER" &>/dev/null; then
        echo "  • Compte SSH Admin mis à jour"
    else
        echo "  • Compte SSH Admin créé : $SSH_ADMIN_USER"
    fi
fi

echo ""
echo "Commandes disponibles :"
echo "  • sudo maxlink-orchestrator status    - État du système"
echo "  • sudo maxlink-orchestrator check     - Vérification santé"
echo "  • sudo maxlink-orchestrator logs all  - Voir tous les logs"
echo "  • sudo test-ssh-admin                 - Infos compte SSH"
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