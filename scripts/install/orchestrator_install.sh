#!/bin/bash

# ===============================================================================
# MAXLINK - SYSTÈME D'ORCHESTRATION AVEC SYSTEMD (VERSION AUTO-SYNC)
# Script d'installation avec synchronisation automatique depuis la clé USB
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
init_logging "Installation/Mise à jour de l'orchestrateur MaxLink" "install"

# Répertoire local pour les widgets
LOCAL_WIDGETS_DIR="/opt/maxlink/widgets"
LOCAL_WIDGETS_CONFIG="/opt/maxlink/config/widgets"

# Flags pour déterminer ce qui doit être fait
IS_FIRST_INSTALL=false
WIDGETS_UPDATED=false
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

# Synchroniser les widgets depuis la clé USB
sync_widgets_from_usb() {
    echo ""
    echo "◦ Synchronisation des widgets depuis la clé USB..."
    log_info "Synchronisation des widgets depuis $BASE_DIR/scripts/widgets"
    
    # Créer les répertoires si nécessaire
    mkdir -p "$LOCAL_WIDGETS_DIR"
    mkdir -p "$LOCAL_WIDGETS_CONFIG"
    
    if [ ! -d "$BASE_DIR/scripts/widgets" ]; then
        echo "  ↦ Répertoire des widgets non trouvé sur la clé USB ✗"
        log_error "Répertoire des widgets non trouvé: $BASE_DIR/scripts/widgets"
        return 1
    fi
    
    # Sauvegarder la liste des widgets actuels pour comparaison
    local old_widgets=""
    if [ -d "$LOCAL_WIDGETS_DIR" ]; then
        old_widgets=$(find "$LOCAL_WIDGETS_DIR" -maxdepth 1 -type d -name "[^_]*" -exec basename {} \; | sort)
    fi
    
    # Utiliser rsync pour synchroniser intelligemment
    echo "  ↦ Synchronisation des fichiers..."
    
    # Synchroniser le core
    if [ -d "$BASE_DIR/scripts/widgets/_core" ]; then
        rsync -av --delete "$BASE_DIR/scripts/widgets/_core/" "$LOCAL_WIDGETS_DIR/_core/" > /dev/null 2>&1
        echo "    • Core synchronisé ✓"
    fi
    
    # Synchroniser chaque widget
    local sync_count=0
    local updated_widgets=""
    
    for widget_dir in "$BASE_DIR/scripts/widgets"/*; do
        if [ -d "$widget_dir" ] && [ "$(basename "$widget_dir")" != "_core" ]; then
            widget_name=$(basename "$widget_dir")
            
            # Vérifier si le widget a changé
            if ! diff -r "$widget_dir" "$LOCAL_WIDGETS_DIR/$widget_name" >/dev/null 2>&1; then
                rsync -av --delete "$widget_dir/" "$LOCAL_WIDGETS_DIR/$widget_name/" > /dev/null 2>&1
                echo "    • Widget $widget_name mis à jour ✓"
                updated_widgets="$updated_widgets $widget_name"
                ((sync_count++))
                WIDGETS_UPDATED=true
            fi
            
            # Copier la config JSON
            if [ -f "$widget_dir/${widget_name}_widget.json" ]; then
                cp "$widget_dir/${widget_name}_widget.json" "$LOCAL_WIDGETS_CONFIG/"
            fi
            
            log_info "Widget $widget_name synchronisé"
        fi
    done
    
    # Vérifier les widgets supprimés
    local new_widgets=$(find "$LOCAL_WIDGETS_DIR" -maxdepth 1 -type d -name "[^_]*" -exec basename {} \; | sort)
    local removed_widgets=$(comm -23 <(echo "$old_widgets") <(echo "$new_widgets"))
    
    if [ -n "$removed_widgets" ]; then
        echo "  ↦ Widgets supprimés détectés:"
        for widget in $removed_widgets; do
            echo "    • $widget sera désinstallé"
            # Désactiver et supprimer le service
            systemctl stop "maxlink-widget-$widget" 2>/dev/null
            systemctl disable "maxlink-widget-$widget" 2>/dev/null
            rm -f "/etc/systemd/system/maxlink-widget-$widget.service"
            rm -rf "/etc/systemd/system/maxlink-widget-$widget.service.d"
        done
        WIDGETS_UPDATED=true
    fi
    
    # Définir les permissions
    chown -R root:root "$LOCAL_WIDGETS_DIR"
    chmod -R 755 "$LOCAL_WIDGETS_DIR"
    find "$LOCAL_WIDGETS_DIR" -name "*.py" -exec chmod +x {} \;
    
    if [ $sync_count -gt 0 ]; then
        echo "  ↦ $sync_count widget(s) mis à jour ✓"
    else
        echo "  ↦ Tous les widgets sont déjà à jour ✓"
    fi
    
    log_success "Synchronisation terminée - $sync_count modifications"
    return 0
}

# Mettre à jour uniquement les services modifiés
update_modified_services() {
    echo ""
    echo "◦ Mise à jour des services modifiés..."
    log_info "Mise à jour des services pour les widgets modifiés"
    
    for widget_dir in "$LOCAL_WIDGETS_DIR"/*; do
        if [ -d "$widget_dir" ] && [ "$(basename "$widget_dir")" != "_core" ]; then
            widget_name=$(basename "$widget_dir")
            service_name="maxlink-widget-$widget_name"
            
            # Vérifier si le service existe
            if [ ! -f "/etc/systemd/system/${service_name}.service" ]; then
                echo "  ↦ Nouveau widget détecté: $widget_name"
                # Le service sera créé par le script d'installation du widget
                continue
            fi
            
            # Créer ou mettre à jour l'override pour les chemins locaux
            mkdir -p "/etc/systemd/system/${service_name}.service.d"
            
            cat > "/etc/systemd/system/${service_name}.service.d/local-paths.conf" << EOF
[Service]
# Utiliser les chemins locaux au lieu de la clé USB
ExecStart=
ExecStart=/usr/bin/python3 $LOCAL_WIDGETS_DIR/$widget_name/${widget_name}_collector.py

# Variables d'environnement mises à jour
Environment="CONFIG_FILE=$LOCAL_WIDGETS_CONFIG/${widget_name}_widget.json"
Environment="PYTHONPATH=$LOCAL_WIDGETS_DIR/_core:$LOCAL_WIDGETS_DIR"

# Condition d'existence mise à jour
ConditionPathExists=$LOCAL_WIDGETS_DIR/$widget_name/${widget_name}_collector.py
ConditionPathExists=$LOCAL_WIDGETS_CONFIG/${widget_name}_widget.json
EOF
            
            echo "  ↦ Service $service_name mis à jour ✓"
            log_info "Service $service_name configuré pour utiliser les chemins locaux"
        fi
    done
}

# Créer ou mettre à jour l'infrastructure d'orchestration
setup_orchestration_infrastructure() {
    if [ "$IS_FIRST_INSTALL" = true ]; then
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
    else
        echo ""
        echo "◦ Vérification de l'infrastructure d'orchestration..."
        # Vérifier si des mises à jour sont nécessaires
        update_healthcheck_scripts
        echo "  ↦ Infrastructure à jour ✓"
    fi
}

# Créer les scripts de healthcheck
create_healthcheck_scripts() {
    echo ""
    echo "◦ Création des scripts de vérification..."
    mkdir -p /opt/maxlink/healthchecks

    # 1. Script de vérification MQTT
    cat > /opt/maxlink/healthchecks/check-mqtt.sh << 'EOF'
#!/bin/bash
# Vérification que Mosquitto est prêt à accepter des connexions

# Configuration depuis l'environnement ou valeurs par défaut
MQTT_USER="${MQTT_USER:-mosquitto}"
MQTT_PASS="${MQTT_PASS:-mqtt}"
MQTT_PORT="${MQTT_PORT:-1883}"
MAX_ATTEMPTS=30
ATTEMPT=0

echo "[MQTT Check] Vérification du broker MQTT..."

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # Test de connexion
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/healthcheck" -m "test" 2>/dev/null; then
        echo "[MQTT Check] ✓ Broker MQTT opérationnel"
        
        # Vérifier aussi les topics système
        if timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 >/dev/null 2>&1; then
            echo "[MQTT Check] ✓ Topics système accessibles"
        fi
        
        exit 0
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
    echo "[MQTT Check] Tentative $ATTEMPT/$MAX_ATTEMPTS..."
    sleep 2
done

echo "[MQTT Check] ✗ Timeout - Mosquitto non disponible après $MAX_ATTEMPTS tentatives"
exit 1
EOF

    # 2. Script de vérification réseau
    cat > /opt/maxlink/healthchecks/check-network.sh << 'EOF'
#!/bin/bash
# Vérification que le réseau est complètement initialisé

echo "[Network Check] Vérification du réseau..."

# Attendre que NetworkManager soit complètement prêt
for i in {1..30}; do
    if nmcli general status >/dev/null 2>&1; then
        echo "[Network Check] ✓ NetworkManager opérationnel"
        break
    fi
    echo "[Network Check] Attente NetworkManager... ($i/30)"
    sleep 1
done

# Vérifier l'interface WiFi
if ip link show wlan0 >/dev/null 2>&1; then
    echo "[Network Check] ✓ Interface WiFi disponible"
    
    # Si l'AP est configuré, vérifier qu'il est actif
    if nmcli con show | grep -q "MaxLink-NETWORK"; then
        echo "[Network Check] Configuration AP détectée"
        
        # Attendre que l'AP soit actif si nécessaire
        for i in {1..20}; do
            if nmcli con show --active | grep -q "MaxLink-NETWORK"; then
                echo "[Network Check] ✓ Point d'accès actif"
                break
            fi
            echo "[Network Check] Attente activation AP... ($i/20)"
            sleep 2
        done
    fi
else
    echo "[Network Check] ⚠ Interface WiFi non trouvée"
fi

# Vérifier la résolution DNS locale si dnsmasq est actif
if pgrep -f "dnsmasq.*NetworkManager" >/dev/null; then
    echo "[Network Check] ✓ Service DNS (dnsmasq) actif"
fi

exit 0
EOF

    # 3. Script de vérification Nginx
    cat > /opt/maxlink/healthchecks/check-nginx.sh << 'EOF'
#!/bin/bash
# Vérification que Nginx est prêt

echo "[Nginx Check] Vérification du serveur web..."

# Vérifier que le service est actif
if ! systemctl is-active --quiet nginx; then
    echo "[Nginx Check] ✗ Service Nginx non actif"
    exit 1
fi

# Vérifier que le port est en écoute
if netstat -tlnp 2>/dev/null | grep -q ":80.*nginx" || ss -tlnp 2>/dev/null | grep -q ":80.*nginx"; then
    echo "[Nginx Check] ✓ Nginx écoute sur le port 80"
else
    echo "[Nginx Check] ✗ Nginx n'écoute pas sur le port 80"
    exit 1
fi

# Test HTTP simple
if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200\|304"; then
    echo "[Nginx Check] ✓ Réponse HTTP correcte"
else
    echo "[Nginx Check] ⚠ Pas de réponse HTTP valide"
fi

exit 0
EOF

    # 4. Script de vérification des widgets
    cat > /opt/maxlink/healthchecks/check-widgets.sh << 'EOF'
#!/bin/bash
# Vérification que les fichiers des widgets sont accessibles localement

echo "[Widgets Check] Vérification des fichiers des widgets..."

LOCAL_WIDGETS_DIR="/opt/maxlink/widgets"
LOCAL_WIDGETS_CONFIG="/opt/maxlink/config/widgets"
ERRORS=0

# Vérifier que les répertoires existent
if [ ! -d "$LOCAL_WIDGETS_DIR" ]; then
    echo "[Widgets Check] ✗ Répertoire des widgets non trouvé: $LOCAL_WIDGETS_DIR"
    exit 1
fi

if [ ! -d "$LOCAL_WIDGETS_CONFIG" ]; then
    echo "[Widgets Check] ✗ Répertoire de config non trouvé: $LOCAL_WIDGETS_CONFIG"
    exit 1
fi

# Vérifier chaque widget installé
for widget_service in /etc/systemd/system/maxlink-widget-*.service; do
    if [ -f "$widget_service" ]; then
        widget_name=$(basename "$widget_service" .service | sed 's/maxlink-widget-//')
        
        # Vérifier le collecteur
        if [ -f "$LOCAL_WIDGETS_DIR/$widget_name/${widget_name}_collector.py" ]; then
            echo "[Widgets Check] ✓ Collecteur $widget_name présent"
        else
            echo "[Widgets Check] ✗ Collecteur $widget_name manquant"
            ((ERRORS++))
        fi
        
        # Vérifier la config
        if [ -f "$LOCAL_WIDGETS_CONFIG/${widget_name}_widget.json" ]; then
            echo "[Widgets Check] ✓ Config $widget_name présente"
        else
            echo "[Widgets Check] ✗ Config $widget_name manquante"
            ((ERRORS++))
        fi
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "[Widgets Check] ✓ Tous les fichiers des widgets sont présents"
    exit 0
else
    echo "[Widgets Check] ✗ $ERRORS fichier(s) manquant(s)"
    exit 1
fi
EOF

    # 5. Script de vérification système global
    cat > /opt/maxlink/healthchecks/check-system.sh << 'EOF'
#!/bin/bash
# Vérification globale du système MaxLink

echo ""
echo "========================================================================"
echo "VÉRIFICATION DU SYSTÈME MAXLINK"
echo "========================================================================"
echo ""
echo "Date: $(date)"
echo ""

# Vérifier tous les composants
ERRORS=0

# 1. Réseau
echo "▶ Vérification réseau..."
if /opt/maxlink/healthchecks/check-network.sh; then
    echo "  └─ Réseau: OK ✓"
else
    echo "  └─ Réseau: ERREUR ✗"
    ((ERRORS++))
fi
echo ""

# 2. MQTT
echo "▶ Vérification MQTT..."
if /opt/maxlink/healthchecks/check-mqtt.sh; then
    echo "  └─ MQTT: OK ✓"
else
    echo "  └─ MQTT: ERREUR ✗"
    ((ERRORS++))
fi
echo ""

# 3. Nginx
echo "▶ Vérification Nginx..."
if /opt/maxlink/healthchecks/check-nginx.sh; then
    echo "  └─ Nginx: OK ✓"
else
    echo "  └─ Nginx: ERREUR ✗"
    ((ERRORS++))
fi
echo ""

# 4. Fichiers des widgets
echo "▶ Vérification des fichiers des widgets..."
if /opt/maxlink/healthchecks/check-widgets.sh; then
    echo "  └─ Fichiers widgets: OK ✓"
else
    echo "  └─ Fichiers widgets: ERREUR ✗"
    ((ERRORS++))
fi
echo ""

# 5. Services des widgets
echo "▶ Vérification des services des widgets..."
WIDGET_ERRORS=0
for service in maxlink-widget-*; do
    if systemctl is-enabled --quiet "$service" 2>/dev/null; then
        if systemctl is-active --quiet "$service"; then
            echo "  ├─ $service: ACTIF ✓"
        else
            echo "  ├─ $service: INACTIF ✗"
            ((WIDGET_ERRORS++))
        fi
    fi
done

if [ $WIDGET_ERRORS -eq 0 ]; then
    echo "  └─ Tous les widgets: OK ✓"
else
    echo "  └─ $WIDGET_ERRORS widget(s) inactif(s) ✗"
    ((ERRORS++))
fi
echo ""

# Résumé
echo "========================================================================"
if [ $ERRORS -eq 0 ]; then
    echo "RÉSULTAT: Système MaxLink opérationnel ✓"
    echo "Note: Les widgets sont synchronisés automatiquement depuis la clé USB"
else
    echo "RÉSULTAT: $ERRORS erreur(s) détectée(s) ✗"
fi
echo "========================================================================"
echo ""

exit $ERRORS
EOF

    # Rendre les scripts exécutables
    chmod +x /opt/maxlink/healthchecks/*.sh
    echo "  ↦ Scripts de vérification créés ✓"
    log_success "Scripts de healthcheck créés"
}

# Mettre à jour les scripts de healthcheck si nécessaire
update_healthcheck_scripts() {
    # Pour l'instant, on recrée simplement les scripts
    # Dans le futur, on pourrait faire une comparaison plus intelligente
    create_healthcheck_scripts
}

# Créer les services systemd
create_systemd_services() {
    echo ""
    echo "◦ Création des services de vérification..."

    # 1. Service de vérification réseau au démarrage
    cat > /etc/systemd/system/maxlink-network-ready.service << EOF
[Unit]
Description=MaxLink Network Readiness Check
After=NetworkManager.service
Wants=NetworkManager-wait-online.service
Before=maxlink-network.target

[Service]
Type=oneshot
ExecStart=/opt/maxlink/healthchecks/check-network.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-network.target
EOF

    # 2. Service de vérification MQTT
    cat > /etc/systemd/system/maxlink-mqtt-ready.service << EOF
[Unit]
Description=MaxLink MQTT Readiness Check
After=mosquitto.service
Requires=mosquitto.service
Before=maxlink-core.target

[Service]
Type=oneshot
ExecStart=/opt/maxlink/healthchecks/check-mqtt.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal
Environment="MQTT_USER=${MQTT_USER}"
Environment="MQTT_PASS=${MQTT_PASS}"
Environment="MQTT_PORT=${MQTT_PORT}"

[Install]
WantedBy=maxlink-core.target
EOF

    # 3. Service de vérification des widgets
    cat > /etc/systemd/system/maxlink-widgets-ready.service << EOF
[Unit]
Description=MaxLink Widgets Files Check
After=maxlink-core.target
Before=maxlink-widgets.target

[Service]
Type=oneshot
ExecStart=/opt/maxlink/healthchecks/check-widgets.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=maxlink-widgets.target
EOF

    # 4. Service de monitoring système
    cat > /etc/systemd/system/maxlink-health-monitor.service << EOF
[Unit]
Description=MaxLink System Health Monitor
After=maxlink-widgets.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /opt/maxlink/healthchecks/check-system.sh; sleep 300; done'
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Services de vérification créés ✓"
    log_success "Services de healthcheck créés"
}

# Créer les targets systemd
create_systemd_targets() {
    echo ""
    echo "◦ Création des targets d'orchestration..."

    # 1. Target réseau MaxLink
    cat > /etc/systemd/system/maxlink-network.target << EOF
[Unit]
Description=MaxLink Network Services
After=network-online.target NetworkManager-wait-online.service
Wants=network-online.target NetworkManager-wait-online.service maxlink-network-ready.service

[Install]
WantedBy=multi-user.target
EOF

    # 2. Target core MaxLink (MQTT + Nginx)
    cat > /etc/systemd/system/maxlink-core.target << EOF
[Unit]
Description=MaxLink Core Services
After=maxlink-network.target mosquitto.service
Wants=maxlink-network.target mosquitto.service maxlink-mqtt-ready.service

[Install]
WantedBy=multi-user.target
EOF

    # 3. Target widgets MaxLink
    cat > /etc/systemd/system/maxlink-widgets.target << EOF
[Unit]
Description=MaxLink Widget Services
After=maxlink-core.target maxlink-mqtt-ready.service maxlink-widgets-ready.service
Wants=maxlink-core.target maxlink-widgets-ready.service

[Install]
WantedBy=multi-user.target
EOF

    echo "  ↦ Targets d'orchestration créés ✓"
    log_success "Targets systemd créés"
}

# Configurer les overrides des services
setup_service_overrides() {
    echo ""
    echo "◦ Configuration des services existants..."

    # 1. Modifier Mosquitto pour utiliser le nouveau système
    mkdir -p /etc/systemd/system/mosquitto.service.d/
    cat > /etc/systemd/system/mosquitto.service.d/maxlink-orchestration.conf << EOF
[Unit]
# Intégration dans l'orchestration MaxLink
After=maxlink-network.target
PartOf=maxlink-core.target

[Service]
# Augmenter le timeout de démarrage
TimeoutStartSec=90
# S'assurer que le service redémarre en cas d'échec
Restart=on-failure
RestartSec=10
EOF

    # 2. Modifier Nginx
    mkdir -p /etc/systemd/system/nginx.service.d/
    cat > /etc/systemd/system/nginx.service.d/maxlink-orchestration.conf << EOF
[Unit]
# Dépendances MaxLink
After=maxlink-network.target mosquitto.service
Wants=mosquitto.service
PartOf=maxlink-core.target

[Service]
# Attendre que MQTT soit prêt avant de démarrer
ExecStartPre=/opt/maxlink/healthchecks/check-mqtt.sh
# Timeout généreux
TimeoutStartSec=90
EOF

    echo "  ↦ Services configurés ✓"
}

# Créer le script de gestion
create_management_script() {
    echo ""
    echo "◦ Création du script de gestion..."

    cat > /usr/local/bin/maxlink-orchestrator << 'EOF'
#!/bin/bash
# Script de gestion de l'orchestrateur MaxLink (version auto-sync)

case "$1" in
    status)
        echo "=== État de l'orchestrateur MaxLink ==="
        echo ""
        echo "▶ Targets:"
        systemctl status maxlink-network.target --no-pager --lines=0
        systemctl status maxlink-core.target --no-pager --lines=0
        systemctl status maxlink-widgets.target --no-pager --lines=0
        echo ""
        echo "▶ Services de vérification:"
        systemctl status maxlink-network-ready.service --no-pager --lines=0
        systemctl status maxlink-mqtt-ready.service --no-pager --lines=0
        systemctl status maxlink-widgets-ready.service --no-pager --lines=0
        echo ""
        echo "▶ Services core:"
        systemctl status mosquitto --no-pager --lines=0
        systemctl status nginx --no-pager --lines=0
        echo ""
        echo "▶ Widgets:"
        systemctl status 'maxlink-widget-*' --no-pager --lines=0
        echo ""
        echo "▶ Fichiers locaux:"
        echo "  Widgets: /opt/maxlink/widgets/"
        echo "  Configs: /opt/maxlink/config/widgets/"
        ;;
        
    check)
        /opt/maxlink/healthchecks/check-system.sh
        ;;
        
    restart-all)
        echo "Redémarrage de tous les services MaxLink..."
        systemctl restart maxlink-network.target
        sleep 2
        systemctl restart maxlink-core.target
        sleep 5
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
        echo "MaxLink Orchestrator Control (Version auto-sync)"
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
        echo "Note: Les widgets sont automatiquement synchronisés depuis la clé USB"
        echo "      lors de chaque exécution du script d'installation."
        echo ""
        exit 1
        ;;
esac
EOF

    chmod +x /usr/local/bin/maxlink-orchestrator
    echo "  ↦ Script de gestion créé ✓"
    log_success "Script de gestion créé"
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
echo "ORCHESTRATEUR MAXLINK - INSTALLATION/MISE À JOUR"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier si c'est la première installation
check_first_install

# ===============================================================================
# ÉTAPE 1 : SYNCHRONISATION DES WIDGETS
# ===============================================================================

send_progress 10 "Synchronisation des widgets..."

if ! sync_widgets_from_usb; then
    echo ""
    echo "⚠ Impossible de synchroniser les widgets depuis la clé USB"
    echo "  Vérifiez que la clé est bien montée dans: $BASE_DIR"
    log_error "Échec de la synchronisation des widgets"
    exit 1
fi

send_progress 30 "Widgets synchronisés"
wait_silently 2

# ===============================================================================
# ÉTAPE 2 : MISE À JOUR DES SERVICES
# ===============================================================================

send_progress 40 "Mise à jour des services..."

update_modified_services

send_progress 50 "Services mis à jour"
wait_silently 2

# ===============================================================================
# ÉTAPE 3 : INFRASTRUCTURE D'ORCHESTRATION
# ===============================================================================

send_progress 60 "Configuration de l'orchestration..."

setup_orchestration_infrastructure

send_progress 80 "Infrastructure configurée"
wait_silently 2

# ===============================================================================
# ÉTAPE 4 : ACTIVATION ET RECHARGEMENT
# ===============================================================================

send_progress 85 "Activation des services..."

echo ""
echo "◦ Rechargement de systemd..."
systemctl daemon-reload

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "◦ Activation de l'orchestrateur..."
    systemctl enable maxlink-network.target
    systemctl enable maxlink-core.target
    systemctl enable maxlink-widgets.target
    systemctl enable maxlink-network-ready.service
    systemctl enable maxlink-mqtt-ready.service
    systemctl enable maxlink-widgets-ready.service
    echo "  ↦ Orchestrateur activé ✓"
elif [ "$WIDGETS_UPDATED" = true ]; then
    echo "◦ Redémarrage des widgets modifiés..."
    systemctl restart maxlink-widgets.target
    echo "  ↦ Widgets redémarrés ✓"
fi

send_progress 95 "Services activés"
wait_silently 2

# ===============================================================================
# ÉTAPE 5 : TEST
# ===============================================================================

echo ""
echo "◦ Test du système..."
echo ""

/usr/local/bin/maxlink-orchestrator check

send_progress 100 "Installation terminée"
wait_silently 3

# ===============================================================================
# RÉSUMÉ
# ===============================================================================

echo ""
echo "========================================================================"
if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "INSTALLATION INITIALE TERMINÉE"
else
    echo "MISE À JOUR TERMINÉE"
fi
echo "========================================================================"
echo ""

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "✓ L'orchestrateur MaxLink est maintenant installé et actif."
    echo "✓ Les widgets ont été copiés localement depuis la clé USB."
elif [ "$WIDGETS_UPDATED" = true ]; then
    echo "✓ Les widgets ont été mis à jour depuis la clé USB."
    echo "✓ Les services modifiés ont été redémarrés."
else
    echo "✓ Aucune modification détectée, système déjà à jour."
fi

echo ""
echo "▶ Fichiers locaux :"
echo "  • Widgets    : /opt/maxlink/widgets/"
echo "  • Configs    : /opt/maxlink/config/widgets/"
echo "  • Healthchecks : /opt/maxlink/healthchecks/"
echo ""

if [ "$IS_FIRST_INSTALL" = true ]; then
    echo "▶ Architecture de démarrage :"
    echo "  1. network.target → NetworkManager"
    echo "  2. maxlink-network.target → Vérification réseau"
    echo "  3. mosquitto.service → Démarrage MQTT"
    echo "  4. maxlink-mqtt-ready → Vérification MQTT"
    echo "  5. maxlink-core.target → Services core (Nginx)"
    echo "  6. maxlink-widgets-ready → Vérification fichiers widgets"
    echo "  7. maxlink-widgets.target → Tous les widgets"
    echo ""
fi

echo "▶ Commandes utiles :"
echo "  • maxlink-orchestrator status    - État du système"
echo "  • maxlink-orchestrator check     - Vérification complète"
echo "  • maxlink-orchestrator logs all  - Voir tous les logs"
echo ""

log_success "Script terminé avec succès"

# Décider si un redémarrage est nécessaire
if [ "$NEED_REBOOT" = true ]; then
    echo ""
    echo "========================================================================"
    echo "⚠ REDÉMARRAGE NÉCESSAIRE"
    echo "========================================================================"
    echo ""
    echo "Un redémarrage est nécessaire pour activer l'orchestration complète."
    echo ""
    echo "  ↦ Redémarrage du système prévu dans 15 secondes..."
    echo ""
    
    log_info "Redémarrage du système prévu dans 15 secondes"
    sleep 15
    
    log_info "Redémarrage du système"
    reboot
else
    echo ""
    echo "✓ Aucun redémarrage nécessaire."
    echo ""
fi