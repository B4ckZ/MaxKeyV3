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

# Configuration des permissions ACL pour l'utilisateur prod
setup_prod_user_permissions() {
    echo ""
    echo "========================================================================"
    echo "CONFIGURATION DES PERMISSIONS SSH POUR L'UTILISATEUR PROD"
    echo "========================================================================"
    
    # Vérifier que l'utilisateur prod existe
    if ! id "prod" &>/dev/null; then
        echo "⚠ L'utilisateur 'prod' n'existe pas. Création de l'utilisateur..."
        log_warning "Utilisateur prod non trouvé, création en cours"
        
        # Créer l'utilisateur prod
        useradd -m -s /bin/bash prod
        echo "  ↦ Utilisateur 'prod' créé ✓"
        log_success "Utilisateur prod créé"
    else
        echo "◦ L'utilisateur 'prod' existe déjà ✓"
        log_info "Utilisateur prod trouvé"
    fi
    
    # Vérifier que ACL est disponible
    echo ""
    echo "◦ Vérification de la disponibilité des ACL..."
    if command -v setfacl &>/dev/null && command -v getfacl &>/dev/null; then
        echo "  ↦ Commandes ACL disponibles ✓"
        log_info "ACL disponible sur le système"
    else
        echo "  ↦ ERREUR: ACL non disponible sur le système ✗"
        log_error "ACL non disponible"
        return 1
    fi
    
    # Appliquer les ACL sur /var/www/
    echo ""
    echo "◦ Application des permissions ACL sur /var/www/..."
    
    # Créer /var/www si nécessaire
    if [ ! -d "/var/www" ]; then
        mkdir -p /var/www
        echo "  ↦ Répertoire /var/www créé ✓"
        log_info "Répertoire /var/www créé"
    fi
    
    # Appliquer les ACL récursives pour l'utilisateur prod
    echo "  ↦ Application des ACL pour lecture, écriture et exécution..."
    setfacl -R -m u:prod:rwx /var/www/
    if [ $? -eq 0 ]; then
        echo "    • Permissions actuelles appliquées ✓"
        log_success "ACL appliquées sur les fichiers existants"
    else
        echo "    • ERREUR lors de l'application des permissions ✗"
        log_error "Échec de l'application des ACL"
        return 1
    fi
    
    # Configurer les ACL par défaut pour les nouveaux fichiers/dossiers
    echo "  ↦ Configuration des ACL par défaut pour les nouveaux fichiers..."
    setfacl -R -d -m u:prod:rwx /var/www/
    if [ $? -eq 0 ]; then
        echo "    • Permissions par défaut configurées ✓"
        log_success "ACL par défaut configurées"
    else
        echo "    • ERREUR lors de la configuration des permissions par défaut ✗"
        log_error "Échec de la configuration des ACL par défaut"
        return 1
    fi
    
    # Vérifier les permissions
    echo ""
    echo "◦ Vérification des permissions appliquées..."
    echo "  ↦ Permissions sur /var/www/ :"
    getfacl /var/www/ | grep -E "user:prod|default:user:prod" | head -5
    
    # Test de création d'un fichier
    echo ""
    echo "◦ Test des permissions..."
    TEST_FILE="/var/www/test_prod_permissions_$$.txt"
    su - prod -c "echo 'Test permissions' > $TEST_FILE 2>/dev/null"
    if [ -f "$TEST_FILE" ]; then
        echo "  ↦ Test d'écriture réussi ✓"
        log_success "L'utilisateur prod peut écrire dans /var/www/"
        rm -f "$TEST_FILE"
    else
        echo "  ↦ ATTENTION: Test d'écriture échoué ⚠"
        log_warning "L'utilisateur prod ne peut pas écrire dans /var/www/"
    fi
    
    # Afficher un résumé
    echo ""
    echo "========================================================================"
    echo "RÉSUMÉ DES PERMISSIONS"
    echo "========================================================================"
    echo "  • Utilisateur : prod"
    echo "  • Répertoire : /var/www/ et tous ses sous-dossiers"
    echo "  • Permissions : Lecture, écriture et exécution complètes (rwx)"
    echo "  • ACL par défaut : Configurées pour les nouveaux fichiers/dossiers"
    echo ""
    echo "L'utilisateur 'prod' peut maintenant accéder via SSH/SFTP avec des"
    echo "permissions complètes dans /var/www/ sans affecter le fonctionnement"
    echo "des services web existants."
    echo "========================================================================"
    
    log_info "Configuration des permissions SSH pour prod terminée"
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
        echo "  ↦ ERREUR: Dossier source des widgets non trouvé ✗"
        log_error "Dossier $BASE_DIR/scripts/widgets non trouvé"
        return 1
    fi
    
    # Compter les widgets
    WIDGET_COUNT=$(find "$BASE_DIR/scripts/widgets" -name "*.sh" -type f | wc -l)
    echo "  ↦ $WIDGET_COUNT widgets trouvés"
    log_info "$WIDGET_COUNT widgets à copier"
    
    # Copier tous les widgets
    cp -r "$BASE_DIR/scripts/widgets"/* "$LOCAL_WIDGETS_DIR/" 2>/dev/null || true
    
    # Copier les configurations si elles existent
    if [ -d "$BASE_DIR/config/widgets" ]; then
        cp -r "$BASE_DIR/config/widgets"/* "$LOCAL_WIDGETS_CONFIG/" 2>/dev/null || true
        echo "  ↦ Configurations des widgets copiées ✓"
    fi
    
    # Rendre les widgets exécutables
    chmod +x "$LOCAL_WIDGETS_DIR"/*.sh 2>/dev/null || true
    
    echo "  ↦ Widgets copiés avec succès ✓"
    log_success "Widgets copiés vers /opt/maxlink"
}

# Créer les scripts de vérification de santé
create_healthcheck_scripts() {
    echo ""
    echo "◦ Création des scripts de vérification..."
    
    # Script de vérification réseau
    cat > /usr/local/bin/maxlink-check-network.sh << 'EOF'
#!/bin/bash
# Vérification de la connectivité réseau
if nmcli networking connectivity | grep -q "full\|limited\|portal"; then
    echo "Network connectivity OK"
    exit 0
else
    echo "Network connectivity FAILED"
    exit 1
fi
EOF
    
    # Script de vérification MQTT
    cat > /usr/local/bin/maxlink-check-mqtt.sh << 'EOF'
#!/bin/bash
# Vérification que Mosquitto est actif
if systemctl is-active mosquitto >/dev/null 2>&1; then
    echo "MQTT broker is running"
    exit 0
else
    echo "MQTT broker is not running"
    exit 1
fi
EOF
    
    # Script de vérification des widgets
    cat > /usr/local/bin/maxlink-check-widgets.sh << 'EOF'
#!/bin/bash
# Vérification qu'au moins un widget est actif
ACTIVE_WIDGETS=$(systemctl list-units --type=service --state=active | grep -c "maxlink-widget-")
if [ "$ACTIVE_WIDGETS" -gt 0 ]; then
    echo "$ACTIVE_WIDGETS widget(s) active"
    exit 0
else
    echo "No active widgets found"
    exit 1
fi
EOF
    
    # Script de monitoring global
    cat > /usr/local/bin/maxlink-health-monitor.sh << 'EOF'
#!/bin/bash
# Monitoring de santé MaxLink
while true; do
    # Vérifier l'état des services critiques
    NETWORK_OK=$(systemctl is-active maxlink-network-ready.service 2>/dev/null)
    MQTT_OK=$(systemctl is-active mosquitto 2>/dev/null)
    NGINX_OK=$(systemctl is-active nginx 2>/dev/null)
    
    # Logger l'état
    logger -t maxlink-health "Network: $NETWORK_OK, MQTT: $MQTT_OK, Nginx: $NGINX_OK"
    
    # Si un service critique est down, tenter de le relancer
    if [ "$MQTT_OK" != "active" ]; then
        logger -t maxlink-health "Attempting to restart MQTT"
        systemctl restart mosquitto
    fi
    
    if [ "$NGINX_OK" != "active" ]; then
        logger -t maxlink-health "Attempting to restart Nginx"
        systemctl restart nginx
    fi
    
    sleep 60
done
EOF
    
    # Rendre tous les scripts exécutables
    chmod +x /usr/local/bin/maxlink-check-*.sh
    chmod +x /usr/local/bin/maxlink-health-monitor.sh
    
    echo "  ↦ Scripts de vérification créés ✓"
    log_success "Scripts de healthcheck créés"
}

# Créer les services systemd
create_systemd_services() {
    echo ""
    echo "◦ Création des services systemd..."
    
    # Service de vérification réseau
    cat > /etc/systemd/system/maxlink-network-ready.service << EOF
[Unit]
Description=MaxLink Network Ready Check
After=NetworkManager.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maxlink-check-network.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-network.target
EOF

    # Service de vérification MQTT
    cat > /etc/systemd/system/maxlink-mqtt-ready.service << EOF
[Unit]
Description=MaxLink MQTT Ready Check
After=mosquitto.service
Requires=mosquitto.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maxlink-check-mqtt.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal
Restart=on-failure
RestartSec=10

[Install]
WantedBy=maxlink-core.target
EOF

    # Service de vérification des widgets
    cat > /etc/systemd/system/maxlink-widgets-ready.service << EOF
[Unit]
Description=MaxLink Widgets Ready Check
After=maxlink-widget-system-stats.service
Wants=maxlink-widget-system-stats.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/maxlink-check-widgets.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-widgets.target
EOF

    # Service de monitoring de santé
    cat > /etc/systemd/system/maxlink-health-monitor.service << EOF
[Unit]
Description=MaxLink Health Monitor
After=maxlink-widgets.target
Wants=maxlink-widgets.target

[Service]
Type=simple
ExecStart=/usr/local/bin/maxlink-health-monitor.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Services systemd créés ✓"
    log_success "Services systemd créés"
}

# Créer les targets systemd
create_systemd_targets() {
    echo ""
    echo "◦ Création des targets systemd..."
    
    # Target pour le réseau
    cat > /etc/systemd/system/maxlink-network.target << EOF
[Unit]
Description=MaxLink Network Stack
Wants=NetworkManager.service
After=network-online.target

[Install]
WantedBy=multi-user.target
EOF

    # Target pour les services core
    cat > /etc/systemd/system/maxlink-core.target << EOF
[Unit]
Description=MaxLink Core Services
Requires=maxlink-network.target
After=maxlink-network.target maxlink-network-ready.service
Wants=mosquitto.service nginx.service

[Install]
WantedBy=multi-user.target
EOF

    # Target pour les widgets
    cat > /etc/systemd/system/maxlink-widgets.target << EOF
[Unit]
Description=MaxLink Widgets
Requires=maxlink-core.target
After=maxlink-core.target maxlink-mqtt-ready.service
Wants=maxlink-widget-system-stats.service maxlink-widget-network-monitor.service maxlink-widget-service-monitor.service

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Targets systemd créés ✓"
    log_success "Targets systemd créés"
}

# Configurer les overrides pour les services
setup_service_overrides() {
    echo ""
    echo "◦ Configuration des dépendances des services..."
    
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
                journalctl -u NetworkManager -u maxlink-network-ready -f
                ;;
            all)
                journalctl -u mosquitto -u nginx -u 'maxlink-*' -f
                ;;
            *)
                echo "Usage: $0 logs {mqtt|widgets|network|all}"
                ;;
        esac
        ;;
        
    enable)
        echo "Activation de l'orchestrateur..."
        systemctl daemon-reload
        systemctl enable maxlink-network.target
        systemctl enable maxlink-core.target
        systemctl enable maxlink-widgets.target
        systemctl enable maxlink-network-ready.service
        systemctl enable maxlink-mqtt-ready.service
        systemctl enable maxlink-widgets-ready.service
        systemctl enable maxlink-health-monitor.service
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

send_progress 35 "Permissions SSH configurées"

# ===============================================================================
# ÉTAPE 3 : INFRASTRUCTURE D'ORCHESTRATION
# ===============================================================================

send_progress 40 "Installation de l'orchestrateur..."

if [ "$IS_FIRST_INSTALL" = true ]; then
    setup_orchestration_infrastructure
else
    echo ""
    echo "◦ Infrastructure d'orchestration déjà présente"
    log_info "Mise à jour - infrastructure existante conservée"
fi

send_progress 60 "Orchestrateur installé"

# ===============================================================================
# ÉTAPE 4 : RECHARGEMENT SYSTEMD
# ===============================================================================

send_progress 70 "Configuration systemd..."

echo ""
echo "========================================================================"
echo "CONFIGURATION SYSTEMD"
echo "========================================================================"

echo "◦ Rechargement de la configuration systemd..."
systemctl daemon-reload
echo "  ↦ Configuration rechargée ✓"
log_success "Systemd daemon-reload effectué"

send_progress 80 "Systemd configuré"

# ===============================================================================
# ÉTAPE 5 : ACTIVATION DES SERVICES
# ===============================================================================

send_progress 85 "Activation des services..."

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