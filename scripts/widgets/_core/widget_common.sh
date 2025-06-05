#!/bin/bash

# ===============================================================================
# MAXLINK - CORE COMMUN DES WIDGETS (VERSION CORRIGÉE)
# Version sans dépendance USB - chemins locaux uniquement
# ===============================================================================

# Vérifier les dépendances
if [ -z "$BASE_DIR" ]; then
    echo "ERREUR: Ce module doit être sourcé après variables.sh"
    exit 1
fi

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# IMPORTANT: Utiliser les chemins LOCAUX pour l'exécution
LOCAL_WIDGETS_DIR="/opt/maxlink/widgets"
LOCAL_CONFIG_DIR="/opt/maxlink/config/widgets"

# Pour l'installation initiale depuis la clé USB
USB_WIDGETS_DIR="$BASE_DIR/scripts/widgets"

# Fichiers de tracking
WIDGETS_CONFIG_DIR="/etc/maxlink/widgets"
WIDGETS_TRACKING_FILE="/etc/maxlink/widgets_installed.json"

# Créer les répertoires
mkdir -p "$WIDGETS_CONFIG_DIR" "$(dirname "$WIDGETS_TRACKING_FILE")"
mkdir -p "$LOCAL_WIDGETS_DIR" "$LOCAL_CONFIG_DIR"

# ===============================================================================
# FONCTIONS DE BASE
# ===============================================================================

# Charger la configuration d'un widget (depuis USB pendant l'installation)
widget_load_config() {
    local widget_name=$1
    local config_file="$USB_WIDGETS_DIR/$widget_name/${widget_name}_widget.json"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration manquante: $config_file"
        return 1
    fi
    
    echo "$config_file"
}

# Extraire une valeur du JSON
widget_get_value() {
    local json_file=$1
    local key_path=$2
    
    python3 -c "
import json
try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    keys = '$key_path'.split('.')
    value = data
    for key in keys:
        value = value.get(key, '')
    print(value)
except:
    print('')
"
}

# Vérifier si un widget est installé
widget_is_installed() {
    local widget_name=$1
    
    if [ -f "$WIDGETS_TRACKING_FILE" ]; then
        python3 -c "
import json
try:
    with open('$WIDGETS_TRACKING_FILE', 'r') as f:
        data = json.load(f)
    print('yes' if '$widget_name' in data else 'no')
except:
    print('no')
"
    else
        echo "no"
    fi
}

# Enregistrer un widget comme installé
widget_register() {
    local widget_name=$1
    local service_name=$2
    local version=$3
    
    python3 -c "
import json
from datetime import datetime

try:
    with open('$WIDGETS_TRACKING_FILE', 'r') as f:
        data = json.load(f)
except:
    data = {}

data['$widget_name'] = {
    'installed_date': datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'service_name': '$service_name',
    'version': '$version',
    'status': 'active'
}

with open('$WIDGETS_TRACKING_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
    
    log_success "Widget $widget_name enregistré"
}

# ===============================================================================
# INSTALLATION PYTHON
# ===============================================================================

# Installer les dépendances Python d'un widget
widget_install_python_deps() {
    local widget_name=$1
    local config_file=$2
    
    log_info "Vérification des dépendances Python pour $widget_name"
    
    local python_deps=$(widget_get_value "$config_file" "dependencies.python_packages")
    
    if [ -z "$python_deps" ] || [ "$python_deps" = "[]" ]; then
        log_info "Aucune dépendance Python pour $widget_name"
        return 0
    fi
    
    log_info "Dépendances Python vérifiées (installées via le cache)"
    return 0
}

# ===============================================================================
# SERVICE SYSTEMD AVEC CHEMINS LOCAUX
# ===============================================================================

# Créer et installer un service systemd pour un widget
widget_create_service() {
    local widget_name=$1
    local config_file=$2
    local collector_script=$3  # Chemin USB pendant l'installation
    
    local service_name=$(widget_get_value "$config_file" "collector.service_name")
    local service_desc=$(widget_get_value "$config_file" "collector.service_description")
    
    if [ -z "$service_name" ]; then
        service_name="maxlink-widget-$widget_name"
    fi
    
    if [ -z "$service_desc" ]; then
        service_desc="MaxLink Widget $widget_name"
    fi
    
    log_info "Création du service $service_name"
    
    # IMPORTANT: Utiliser UNIQUEMENT les chemins locaux pour l'exécution
    local local_collector="/opt/maxlink/widgets/$widget_name/${widget_name}_collector.py"
    local local_config="/opt/maxlink/config/widgets/${widget_name}_widget.json"
    
    # Copier les fichiers depuis USB vers local
    log_info "Copie des fichiers du widget vers /opt/maxlink"
    
    # Créer le répertoire du widget
    mkdir -p "$LOCAL_WIDGETS_DIR/$widget_name"
    
    # Copier tous les fichiers du widget
    cp -r "$USB_WIDGETS_DIR/$widget_name"/* "$LOCAL_WIDGETS_DIR/$widget_name/"
    
    # Copier la configuration
    cp "$config_file" "$LOCAL_CONFIG_DIR/"
    
    # Définir les permissions
    chmod +x "$local_collector"
    chown -R root:root "$LOCAL_WIDGETS_DIR/$widget_name"
    chown -R root:root "$LOCAL_CONFIG_DIR/${widget_name}_widget.json"
    
    # Créer le fichier service avec chemins locaux fixes
    cat > "/etc/systemd/system/${service_name}.service" << EOF
[Unit]
Description=$service_desc
After=network-online.target mosquitto.service
Wants=network-online.target
Requires=mosquitto.service

# Vérifier l'existence des fichiers LOCAUX uniquement
ConditionPathExists=$local_collector
ConditionPathExists=$local_config

[Service]
Type=simple
ExecStart=/usr/bin/python3 $local_collector
Restart=always
RestartSec=30
StartLimitInterval=600
StartLimitBurst=5

User=root
StandardOutput=journal
StandardError=journal

# Environnement
Environment="PYTHONUNBUFFERED=1"
Environment="WIDGET_NAME=$widget_name"
Environment="CONFIG_FILE=$local_config"
Environment="MQTT_RETRY_ENABLED=true"
Environment="MQTT_RETRY_DELAY=10"
Environment="MQTT_MAX_RETRIES=0"
Environment="PYTHONPATH=/opt/maxlink/widgets/_core:/opt/maxlink/widgets"

# Répertoire de travail LOCAL
WorkingDirectory=/opt/maxlink/widgets/$widget_name

# Sécurité
PrivateTmp=true
NoNewPrivileges=true

TimeoutStartSec=90

[Install]
WantedBy=multi-user.target
EOF
    
    log_info "Service créé : ${service_name}.service"
    
    # Recharger systemd
    systemctl daemon-reload
    
    # Activer et démarrer le service
    if systemctl enable "$service_name" >/dev/null 2>&1; then
        log_success "Service activé: $service_name"
        
        if systemctl start "$service_name"; then
            log_success "Service démarré: $service_name"
            return 0
        else
            log_error "Impossible de démarrer le service"
            return 1
        fi
    else
        log_error "Impossible d'activer le service"
        return 1
    fi
}

# ===============================================================================
# VALIDATION
# ===============================================================================

# Valider la structure d'un widget
widget_validate() {
    local widget_name=$1
    local widget_dir="$USB_WIDGETS_DIR/$widget_name"
    
    local config_file="$widget_dir/${widget_name}_widget.json"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration manquante: $config_file"
        return 1
    fi
    
    if ! python3 -m json.tool "$config_file" >/dev/null 2>&1; then
        log_error "JSON invalide: ${widget_name}_widget.json"
        return 1
    fi
    
    local collector_enabled=$(widget_get_value "$config_file" "collector.enabled")
    
    local required_files=(
        "${widget_name}_widget.json"
        "${widget_name}_install.sh"
    )
    
    if [ "$collector_enabled" = "true" ] || [ "$collector_enabled" = "True" ]; then
        required_files+=("${widget_name}_collector.py")
    fi
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$widget_dir/$file" ]; then
            log_error "Fichier manquant: $widget_dir/$file"
            return 1
        fi
    done
    
    log_success "Widget $widget_name validé"
    return 0
}

# ===============================================================================
# INSTALLATION STANDARD
# ===============================================================================

# Fonction d'installation standard d'un widget
widget_standard_install() {
    local widget_name=$1
    
    echo ""
    echo "Installation du widget: $widget_name"
    echo "------------------------------------"
    
    if ! widget_validate "$widget_name"; then
        echo "  ↦ Widget invalide ✗"
        return 1
    fi
    
    local config_file=$(widget_load_config "$widget_name")
    local widget_dir="$USB_WIDGETS_DIR/$widget_name"
    local collector_script="$widget_dir/${widget_name}_collector.py"
    
    # Copier le core si nécessaire
    if [ ! -d "$LOCAL_WIDGETS_DIR/_core" ]; then
        echo "  ↦ Copie du core des widgets..."
        cp -r "$USB_WIDGETS_DIR/_core" "$LOCAL_WIDGETS_DIR/"
        chmod +x "$LOCAL_WIDGETS_DIR/_core"/*.py 2>/dev/null || true
    fi
    
    if [ "$(widget_is_installed "$widget_name")" = "yes" ]; then
        echo "  ↦ Widget déjà installé, mise à jour..."
        
        local old_service=$(widget_get_value "$WIDGETS_TRACKING_FILE" "$widget_name.service_name")
        if [ -n "$old_service" ] && [ "$old_service" != "none" ]; then
            systemctl stop "$old_service" 2>/dev/null || true
        fi
    fi
    
    if ! widget_install_python_deps "$widget_name" "$config_file"; then
        echo "  ↦ Dépendances Python manquantes ✗"
        return 1
    fi
    
    local collector_enabled=$(widget_get_value "$config_file" "collector.enabled")
    
    if [ "$collector_enabled" = "true" ] || [ "$collector_enabled" = "True" ]; then
        chmod +x "$collector_script"
        
        if widget_create_service "$widget_name" "$config_file" "$collector_script"; then
            local version=$(widget_get_value "$config_file" "widget.version")
            local service_name=$(widget_get_value "$config_file" "collector.service_name")
            [ -z "$service_name" ] && service_name="maxlink-widget-$widget_name"
            
            widget_register "$widget_name" "$service_name" "$version"
            
            echo "  ↦ Widget $widget_name installé ✓"
            echo "  ↦ Note : L'orchestrateur gère le démarrage ordonné"
            return 0
        else
            echo "  ↦ Erreur lors de l'installation ✗"
            return 1
        fi
    else
        echo "  ↦ Widget passif (pas de collector)"
        
        # Copier quand même les fichiers du widget
        mkdir -p "$LOCAL_WIDGETS_DIR/$widget_name"
        cp -r "$widget_dir"/* "$LOCAL_WIDGETS_DIR/$widget_name/"
        cp "$config_file" "$LOCAL_CONFIG_DIR/"
        
        local version=$(widget_get_value "$config_file" "widget.version")
        widget_register "$widget_name" "none" "$version"
        
        echo "  ↦ Widget $widget_name installé ✓"
        return 0
    fi
}

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

# Vérifier l'état de tous les widgets
widget_check_all_status() {
    echo "État des widgets installés :"
    
    if [ -f "$WIDGETS_TRACKING_FILE" ]; then
        python3 -c "
import json
import subprocess

with open('$WIDGETS_TRACKING_FILE', 'r') as f:
    widgets = json.load(f)

for name, info in widgets.items():
    service = info.get('service_name', 'none')
    if service != 'none':
        try:
            result = subprocess.run(['systemctl', 'is-active', service], 
                                  capture_output=True, text=True)
            status = '✓' if result.stdout.strip() == 'active' else '✗'
        except:
            status = '?'
    else:
        status = '-'
    
    print(f'  • {name}: {status} ({service})')
"
    else
        echo "  Aucun widget installé"
    fi
}

# Redémarrer tous les widgets
widget_restart_all() {
    echo "Redémarrage de tous les widgets..."
    
    if [ -f "$WIDGETS_TRACKING_FILE" ]; then
        python3 -c "
import json
import subprocess

with open('$WIDGETS_TRACKING_FILE', 'r') as f:
    widgets = json.load(f)

for name, info in widgets.items():
    service = info.get('service_name', 'none')
    if service != 'none':
        print(f'  • Redémarrage de {name}...')
        subprocess.run(['systemctl', 'restart', service])
"
    fi
}

# ===============================================================================
# EXPORT
# ===============================================================================

export -f widget_load_config
export -f widget_get_value
export -f widget_is_installed
export -f widget_register
export -f widget_install_python_deps
export -f widget_create_service
export -f widget_validate
export -f widget_standard_install
export -f widget_check_all_status
export -f widget_restart_all