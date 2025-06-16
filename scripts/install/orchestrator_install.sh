#!/bin/bash

# ===============================================================================
# MAXLINK - SYSTÈME D'ORCHESTRATION AVEC SYSTEMD (VERSION CORRIGÉE)
# Script d'installation avec mise à jour du statut et gestion SKIP_REBOOT
# Ajout de la création du compte SSH administrateur
# Ajout de la correction WiFi pour compatibilité ESP32
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
    
    # Créer l'utilisateur seulement s'il n'existe pas
    if ! id "$SSH_ADMIN_USER" &>/dev/null; then
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
    else
        echo "◦ L'utilisateur $SSH_ADMIN_USER existe déjà"
        log_info "Configuration de l'utilisateur existant"
    fi
    
    # Définir/Redéfinir le mot de passe
    echo "◦ Configuration du mot de passe..."
    echo "$SSH_ADMIN_USER:$SSH_ADMIN_PASS" | chpasswd
    
    if [ $? -eq 0 ]; then
        echo "  ↦ Mot de passe configuré ✓"
        log_success "Mot de passe configuré pour $SSH_ADMIN_USER"
    else
        echo "  ↦ Erreur lors de la configuration du mot de passe ✗"
        log_error "Impossible de définir le mot de passe"
        return 1
    fi
    
    # Ajouter aux groupes système (y compris root pour accès complet)
    echo "◦ Configuration des groupes système..."
    
    # Ajouter au groupe sudo en premier (essentiel)
    usermod -aG sudo "$SSH_ADMIN_USER"
    
    # Ajouter aux autres groupes
    for group in $(echo $SSH_ADMIN_GROUPS | tr ',' ' '); do
        if getent group "$group" >/dev/null 2>&1; then
            usermod -aG "$group" "$SSH_ADMIN_USER" 2>/dev/null
            echo "  ↦ Ajouté au groupe $group ✓"
        fi
    done
    
    # Ajouter au groupe root pour accès complet
    usermod -aG root "$SSH_ADMIN_USER"
    echo "  ↦ Ajouté au groupe root pour accès complet ✓"
    
    log_success "Utilisateur ajouté aux groupes système"
    
    # Configuration sudo SANS mot de passe - IMPORTANT pour accès complet
    echo "◦ Configuration des privilèges sudo (accès complet)..."
    
    # Créer le fichier sudoers avec priorité élevée
    cat > "/etc/sudoers.d/00-$SSH_ADMIN_USER" <<EOF
# MaxLink SSH Admin - Accès complet sans restriction
$SSH_ADMIN_USER ALL=(ALL:ALL) NOPASSWD:ALL
EOF
    
    chmod 440 "/etc/sudoers.d/00-$SSH_ADMIN_USER"
    echo "  ↦ Privilèges sudo COMPLETS configurés (NOPASSWD) ✓"
    log_success "Accès superadmin configuré pour $SSH_ADMIN_USER"
    
    # Configuration SSH
    echo "◦ Configuration SSH..."
    
    # S'assurer que le service SSH accepte les connexions par mot de passe
    if [ -f /etc/ssh/sshd_config ]; then
        # Backup
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
        
        # Activer l'authentification par mot de passe
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/^#*UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
        
        # Supprimer toute configuration Match User existante pour notre utilisateur
        sed -i "/^Match User $SSH_ADMIN_USER/,/^Match\|^$/d" /etc/ssh/sshd_config
        
        # Configuration spécifique pour l'utilisateur avec accès complet
        cat >> /etc/ssh/sshd_config <<EOF

# MaxLink SSH Admin - Accès SuperAdmin complet
Match User $SSH_ADMIN_USER
    PasswordAuthentication yes
    PubkeyAuthentication yes
    AllowTcpForwarding yes
    X11Forwarding yes
    PermitTunnel yes
    AllowAgentForwarding yes
    PermitTTY yes
    ForceCommand none
    AllowStreamLocalForwarding yes
    PermitUserEnvironment yes
EOF
        
        # Redémarrer SSH
        systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null
        echo "  ↦ Service SSH configuré et redémarré ✓"
    fi
    
    # Créer le répertoire .ssh
    mkdir -p "$SSH_ADMIN_HOME/.ssh"
    touch "$SSH_ADMIN_HOME/.ssh/authorized_keys"
    chmod 700 "$SSH_ADMIN_HOME/.ssh"
    chmod 600 "$SSH_ADMIN_HOME/.ssh/authorized_keys"
    chown -R "$SSH_ADMIN_USER:$SSH_ADMIN_USER" "$SSH_ADMIN_HOME/.ssh"
    
    # Configuration des permissions pour accès complet au dashboard et système
    echo "◦ Configuration des permissions d'accès..."
    
    # Dashboard NGINX - Accès complet en lecture/écriture
    if [ -n "$NGINX_DASHBOARD_DIR" ] && [ -d "$NGINX_DASHBOARD_DIR" ]; then
        # Ajouter l'utilisateur au groupe www-data si pas déjà fait
        usermod -aG www-data "$SSH_ADMIN_USER" 2>/dev/null
        
        # Permissions récursives sur le dashboard
        chown -R www-data:www-data "$NGINX_DASHBOARD_DIR"
        chmod -R 775 "$NGINX_DASHBOARD_DIR"
        
        # S'assurer que les nouveaux fichiers héritent des permissions du groupe
        find "$NGINX_DASHBOARD_DIR" -type d -exec chmod g+s {} \; 2>/dev/null
        
        # Utiliser ACL si disponible pour garantir l'accès
        if command -v setfacl >/dev/null 2>&1; then
            setfacl -R -m u:$SSH_ADMIN_USER:rwx "$NGINX_DASHBOARD_DIR" 2>/dev/null
            setfacl -R -d -m u:$SSH_ADMIN_USER:rwx "$NGINX_DASHBOARD_DIR" 2>/dev/null
        fi
        
        echo "  ↦ Accès complet au dashboard configuré ✓"
    else
        echo "  ↦ Dashboard non trouvé, sera configuré plus tard"
    fi
    
    # Répertoire MaxLink - Accès complet
    if [ -d "/opt/maxlink" ]; then
        chmod -R 775 /opt/maxlink
        # Permettre à l'utilisateur de modifier
        if command -v setfacl >/dev/null 2>&1; then
            setfacl -R -m u:$SSH_ADMIN_USER:rwx /opt/maxlink 2>/dev/null
            setfacl -R -d -m u:$SSH_ADMIN_USER:rwx /opt/maxlink 2>/dev/null
        fi
        echo "  ↦ Accès complet à /opt/maxlink configuré ✓"
    fi
    
    # Créer un lien symbolique vers le dashboard dans le home si possible
    if [ -n "$NGINX_DASHBOARD_DIR" ] && [ -d "$NGINX_DASHBOARD_DIR" ]; then
        ln -sf "$NGINX_DASHBOARD_DIR" "$SSH_ADMIN_HOME/dashboard" 2>/dev/null
        chown -h "$SSH_ADMIN_USER:$SSH_ADMIN_USER" "$SSH_ADMIN_HOME/dashboard" 2>/dev/null
        echo "  ↦ Lien symbolique vers dashboard créé ✓"
    fi
    
    # Accès aux logs
    usermod -aG adm "$SSH_ADMIN_USER" 2>/dev/null
    usermod -aG systemd-journal "$SSH_ADMIN_USER" 2>/dev/null
    echo "  ↦ Accès aux logs système configuré ✓"
    
    # Créer les répertoires de logs MaxLink si configurés
    if [ "$SSH_ADMIN_ENABLE_LOGGING" = true ]; then
        mkdir -p "$SSH_ADMIN_LOG_DIR"
        touch "$SSH_ADMIN_LOG_FILE"
        touch "$SSH_ADMIN_AUDIT_FILE"
        chmod 750 "$SSH_ADMIN_LOG_DIR"
        chmod 640 "$SSH_ADMIN_LOG_FILE" "$SSH_ADMIN_AUDIT_FILE"
        chown -R "$SSH_ADMIN_USER:adm" "$SSH_ADMIN_LOG_DIR"
        echo "  ↦ Logs SSH configurés ✓"
    fi
    
# Configuration du shell (.bashrc)
    echo "◦ Configuration de l'environnement utilisateur..."
    
    # S'assurer que le .bashrc existe
    if [ ! -f "$SSH_ADMIN_HOME/.bashrc" ]; then
        cp /etc/skel/.bashrc "$SSH_ADMIN_HOME/.bashrc" 2>/dev/null || touch "$SSH_ADMIN_HOME/.bashrc"
    fi
    
    # Supprimer toute configuration MaxLink existante
    sed -i '/# MaxLink SSH Admin Configuration/,/# End MaxLink Configuration/d' "$SSH_ADMIN_HOME/.bashrc" 2>/dev/null
    
    # Ajouter la nouvelle configuration MaxLink
    cat >> "$SSH_ADMIN_HOME/.bashrc" <<'EOF'

# MaxLink SSH Admin Configuration
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export EDITOR=nano

# Variables d'environnement MaxLink
export MAXLINK_HOME="/opt/maxlink"
export DASHBOARD_DIR="/var/www/html/dashboard"

# Alias utiles
alias ll='ls -la'
alias maxlink-status='sudo maxlink-orchestrator status'
alias maxlink-logs='sudo journalctl -u "maxlink-*" -f'
alias dashboard='cd $DASHBOARD_DIR 2>/dev/null || cd /var/www/html'
alias maxlink='cd $MAXLINK_HOME'

# Fonctions utiles
restart-ap() {
    echo "Redémarrage du point d'accès WiFi..."
    sudo systemctl restart hostapd
    sudo nmcli con up "MaxLink-NETWORK"
}

# Message de bienvenue
if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
    echo "=================================================="
    echo " Bienvenue sur MaxLink System"
    echo " Utilisateur: $USER (Accès SuperAdmin)"
    echo "=================================================="
    echo ""
    echo "Commandes rapides:"
    echo "  • dashboard    : Aller au répertoire dashboard"
    echo "  • maxlink      : Aller au répertoire MaxLink"
    echo "  • maxlink-status : État du système"
    echo "  • maxlink-logs : Logs en temps réel"
    echo ""
fi

# Historique amélioré
export HISTTIMEFORMAT="[%Y-%m-%d %H:%M:%S] "
export HISTSIZE=10000
export HISTFILESIZE=20000
shopt -s histappend

# Auto-complétion améliorée
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# End MaxLink Configuration
EOF
    
    chown "$SSH_ADMIN_USER:$SSH_ADMIN_USER" "$SSH_ADMIN_HOME/.bashrc"
    chmod 644 "$SSH_ADMIN_HOME/.bashrc"
    
    # Créer un script de test/info
    cat > /usr/local/bin/test-ssh-admin <<EOF
#!/bin/bash
echo "========================================"
echo "INFORMATIONS COMPTE SSH ADMINISTRATEUR"
echo "========================================"
echo ""
echo "Utilisateur : $SSH_ADMIN_USER"
echo "Mot de passe : $SSH_ADMIN_PASS"
echo "Home : $SSH_ADMIN_HOME"
echo ""
echo "Connexions :"
echo "  • SSH : ssh $SSH_ADMIN_USER@$AP_IP"
echo "  • SFTP : sftp://$SSH_ADMIN_USER@$AP_IP"
echo "  • FileZilla : Hôte=$AP_IP, User=$SSH_ADMIN_USER, Pass=$SSH_ADMIN_PASS, Port=22"
echo ""
echo "Permissions :"
echo "  • Accès sudo complet (NOPASSWD)"
echo "  • Dashboard : $NGINX_DASHBOARD_DIR (lecture/écriture)"
echo "  • MaxLink : /opt/maxlink (lecture/écriture)"
echo "  • Logs : /var/log (lecture)"
echo ""
echo "Groupes : \$(groups $SSH_ADMIN_USER)"
echo ""
echo "État SSH : \$(systemctl is-active ssh || systemctl is-active sshd)"
echo "========================================"
EOF
    chmod 755 /usr/local/bin/test-ssh-admin
    
    # Afficher le résumé
    echo ""
    echo "========================================================================"
    echo "✓ COMPTE SSH ADMINISTRATEUR CRÉÉ AVEC SUCCÈS"
    echo "========================================================================"
    echo ""
    echo "ACCÈS SUPERADMIN COMPLET CONFIGURÉ !"
    echo ""
    echo "Connexion SSH/SFTP :"
    echo "  • Utilisateur : $SSH_ADMIN_USER"
    echo "  • Mot de passe : $SSH_ADMIN_PASS"
    echo "  • Adresse : $AP_IP"
    echo ""
    echo "FileZilla :"
    echo "  • Protocole : SFTP"
    echo "  • Hôte : $AP_IP"
    echo "  • Port : 22"
    echo "  • Type : Normal"
    echo ""
    echo "Permissions complètes sur :"
    echo "  • $NGINX_DASHBOARD_DIR (Dashboard)"
    echo "  • /opt/maxlink (Système)"
    echo "  • Accès sudo sans mot de passe"
    echo ""
    echo "Test : sudo test-ssh-admin"
    echo "========================================================================"
    
    log_success "Compte SSH administrateur configuré avec accès COMPLET"
    
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
    if ! nmcli con show "$AP_SSID" &>/dev/null; then
        echo "  ⚠ Connexion AP '$AP_SSID' non trouvée"
        log_warn "Connexion AP non trouvée, correction ignorée"
        return 0
    fi
    
    echo "  ↦ Connexion AP trouvée ✓"
    log_info "Configuration de la connexion AP pour compatibilité ESP32"
    
    # Forcer la configuration WPA2
    echo "◦ Application de la configuration WPA2..."
    
    # Configurer le mode de gestion des clés
    if nmcli connection modify "$AP_SSID" 802-11-wireless-security.key-mgmt wpa-psk 2>/dev/null; then
        echo "  ↦ Mode de gestion des clés configuré ✓"
        log_success "key-mgmt configuré en wpa-psk"
    else
        echo "  ⚠ Erreur lors de la configuration key-mgmt"
        log_error "Impossible de configurer key-mgmt"
    fi
    
    # Configurer le protocole RSN (WPA2)
    if nmcli connection modify "$AP_SSID" 802-11-wireless-security.proto rsn 2>/dev/null; then
        echo "  ↦ Protocole RSN (WPA2) configuré ✓"
        log_success "Protocole configuré en RSN (WPA2)"
    else
        echo "  ⚠ Erreur lors de la configuration du protocole"
        log_error "Impossible de configurer le protocole RSN"
    fi
    
    # Redémarrer la connexion si elle est active
    if nmcli con show --active | grep -q "$AP_SSID"; then
        echo "◦ Redémarrage de la connexion AP..."
        nmcli con down "$AP_SSID" 2>/dev/null
        wait_silently 2
        nmcli con up "$AP_SSID" 2>/dev/null
        echo "  ↦ Connexion AP redémarrée ✓"
        log_info "Connexion AP redémarrée avec la nouvelle configuration"
    fi
    
    echo ""
    echo "✓ Configuration WiFi corrigée pour compatibilité ESP32"
    echo ""
    log_success "Configuration WiFi ESP32 terminée"
    
    return 0
}

# ===============================================================================
# FONCTIONS D'INFRASTRUCTURE D'ORCHESTRATION
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
WIDGET_SERVICES=$(systemctl list-units --type=service --all | grep -E "maxlink.*widget.service" | awk '{print $1}')
if [ -z "$WIDGET_SERVICES" ]; then
    # Pas de widgets, c'est OK
    exit 0
fi

ALL_ACTIVE=true
for service in $WIDGET_SERVICES; do
    if ! systemctl is-active --quiet "$service"; then
        ALL_ACTIVE=false
        break
    fi
done

if [ "$ALL_ACTIVE" = true ]; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x /usr/local/bin/maxlink-check-widgets
    echo "  ↦ Script de vérification widgets créé ✓"
    
    log_success "Scripts de healthcheck créés"
}

# Créer les services systemd de notification
create_systemd_services() {
    echo ""
    echo "◦ Création des services de notification..."
    
    # Service de notification network ready
    cat > /etc/systemd/system/maxlink-network-ready.service <<'EOF'
[Unit]
Description=MaxLink Network Ready Notification
After=network-online.target hostapd.service
Wants=network-online.target
ConditionPathExists=/usr/local/bin/maxlink-check-network

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 5
ExecStart=/usr/local/bin/maxlink-check-network
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-network.target
EOF
    echo "  ↦ Service network-ready créé ✓"
    
    # Service de notification MQTT ready
    cat > /etc/systemd/system/maxlink-mqtt-ready.service <<'EOF'
[Unit]
Description=MaxLink MQTT Ready Notification
After=mosquitto.service
Requires=mosquitto.service
ConditionPathExists=/usr/local/bin/maxlink-check-mqtt

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/bin/maxlink-check-mqtt
Restart=on-failure
RestartSec=5
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-core.target
EOF
    echo "  ↦ Service mqtt-ready créé ✓"
    
    # Service de notification widgets ready
    cat > /etc/systemd/system/maxlink-widgets-ready.service <<'EOF'
[Unit]
Description=MaxLink Widgets Ready Notification
After=maxlink-mqtt-ready.service
Wants=maxlink-mqtt-ready.service
ConditionPathExists=/usr/local/bin/maxlink-check-widgets

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 10
ExecStart=/usr/local/bin/maxlink-check-widgets
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-widgets.target
EOF
    echo "  ↦ Service widgets-ready créé ✓"
    
    # Service de monitoring de santé
    cat > /etc/systemd/system/maxlink-health-monitor.service <<'EOF'
[Unit]
Description=MaxLink Health Monitor
After=maxlink-widgets.target
Wants=maxlink-widgets.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do echo "[$(date)] Health Check: Network=$(/usr/local/bin/maxlink-check-network && echo OK || echo FAIL), MQTT=$(/usr/local/bin/maxlink-check-mqtt && echo OK || echo FAIL), Widgets=$(/usr/local/bin/maxlink-check-widgets && echo OK || echo FAIL)"; sleep 300; done'
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Service health-monitor créé ✓"
    
    log_success "Services systemd créés"
}

# Créer les targets systemd pour l'orchestration
create_systemd_targets() {
    echo ""
    echo "◦ Création des targets d'orchestration..."
    
    # Target network (hostapd, nginx, etc.)
    cat > /etc/systemd/system/maxlink-network.target <<'EOF'
[Unit]
Description=MaxLink Network Services
After=network-online.target
Wants=network-online.target

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Target network créé ✓"
    
    # Target core (mosquitto, etc.)
    cat > /etc/systemd/system/maxlink-core.target <<'EOF'
[Unit]
Description=MaxLink Core Services
After=maxlink-network.target maxlink-network-ready.service
Requires=maxlink-network.target
Wants=maxlink-network-ready.service

[Install]
WantedBy=multi-user.target
EOF
    echo "  ↦ Target core créé ✓"
    
    # Target widgets
    cat > /etc/systemd/system/maxlink-widgets.target <<'EOF'
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
    cat > /etc/systemd/system/hostapd.service.d/maxlink.conf <<'EOF'
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
    cat > /etc/systemd/system/mosquitto.service.d/maxlink.conf <<'EOF'
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
    cat > /etc/systemd/system/nginx.service.d/maxlink.conf <<'EOF'
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
# PROGRAMME PRINCIPAL
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
# ÉTAPE 2 : CRÉATION DU COMPTE SSH ADMINISTRATEUR
# ===============================================================================

send_progress 30 "Création du compte SSH administrateur..."

if ! setup_ssh_admin_account; then
    echo "⚠ Problème lors de la création du compte SSH, mais on continue..."
    log_warn "Création du compte SSH incomplète, poursuite de l'installation"
fi

# ===============================================================================
# ÉTAPE 3 : CORRECTION WIFI POUR ESP32
# ===============================================================================

send_progress 40 "Correction WiFi pour ESP32..."

if ! fix_wifi_for_esp32; then
    echo "⚠ Problème lors de la correction WiFi, mais on continue..."
    log_warn "Correction WiFi incomplète, poursuite de l'installation"
fi

# ===============================================================================
# ÉTAPE 4 : INSTALLATION DES WIDGETS
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
# ÉTAPE 5 : INFRASTRUCTURE D'ORCHESTRATION
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
# ÉTAPE 6 : ACTIVATION DES SERVICES
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