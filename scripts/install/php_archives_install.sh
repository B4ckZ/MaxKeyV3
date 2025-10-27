#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../common/variables.sh"
source "$SCRIPT_DIR/../common/logging.sh"
source "$SCRIPT_DIR/../common/packages.sh"

init_logging "Installation Système PHP Archives" "install"

SERVICE_ID="php_archives"

# Détection simple et fiable de la version PHP
detect_php_version() {
    dpkg -l 2>/dev/null | grep "^ii.*php[0-9]" | grep -oE "php[0-9]+\.[0-9]+" | head -1 | sed 's/php//'
}

get_php_fpm_service() {
    echo "php${1}-fpm"
}

get_php_fpm_socket() {
    echo "/run/php/php${1}-fpm.sock"
}

send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

install_php_from_cache() {
    log_info "Installation de PHP depuis le cache"
    
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        log_error "Cache manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    if ! verify_category_cache_complete "php"; then
        log_error "Cache PHP incomplet"
        return 1
    fi
    
    if ! install_packages_by_category_simultaneously "php"; then
        log_error "Installation simultanée PHP échouée"
        return 1
    fi
    
    if ! command -v php >/dev/null 2>&1; then
        log_error "PHP CLI non trouvé après installation"
        return 1
    fi
    
    log_success "PHP installé avec succès"
    return 0
}

check_prerequisites() {
    log_info "Vérification des prérequis"
    
    if ! command -v nginx >/dev/null 2>&1; then
        log_error "Nginx non installé"
        return 1
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx n'est pas actif"
        return 1
    fi
    
    if [ ! -d "$NGINX_DASHBOARD_DIR" ]; then
        log_error "Dashboard non installé: $NGINX_DASHBOARD_DIR"
        return 1
    fi
    
    log_success "Prérequis validés"
    return 0
}

activate_php_fpm() {
    local php_version=$1
    local fpm_service=$(get_php_fpm_service "$php_version")
    local fpm_socket=$(get_php_fpm_socket "$php_version")
    
    log_info "Activation de $fpm_service"
    
    if ! dpkg -l | grep -q "^ii.*${fpm_service}"; then
        log_error "Package $fpm_service non installé"
        return 1
    fi
    
    systemctl enable "$fpm_service" >/dev/null 2>&1 || {
        log_error "Échec enable $fpm_service"
        return 1
    }
    
    systemctl start "$fpm_service" >/dev/null 2>&1 || {
        log_error "Échec start $fpm_service"
        return 1
    }
    
    sleep 2
    
    if [ ! -S "$fpm_socket" ]; then
        log_warning "Socket non trouvée: $fpm_socket"
    fi
    
    if ! systemctl is-active --quiet "$fpm_service"; then
        log_error "$fpm_service n'est pas actif"
        return 1
    fi
    
    log_success "$fpm_service activé - socket: $fpm_socket"
    return 0
}

configure_nginx_for_php() {
    local php_version=$1
    local fpm_socket=$(get_php_fpm_socket "$php_version")
    local nginx_conf="/etc/nginx/sites-available/maxlink-dashboard"
    
    log_info "Configuration nginx pour PHP"
    
    if [ ! -f "$nginx_conf" ]; then
        log_error "Config nginx manquante: $nginx_conf"
        return 1
    fi
    
    if grep -q "fastcgi_pass" "$nginx_conf"; then
        log_info "Configuration PHP déjà présente"
        sed -i "s|fastcgi_pass unix:/run/php/php[0-9.]*-fpm.sock|fastcgi_pass unix:${fpm_socket}|g" "$nginx_conf"
        log_info "Socket mis à jour dans la config"
    else
        cp "$nginx_conf" "$nginx_conf.backup.$(date +%s)"
        
        sed -i "/^}$/i\\
\\
    location ~ \\.php\$ {\\
        include snippets/fastcgi-php.conf;\\
        fastcgi_pass unix:${fpm_socket};\\
        fastcgi_param SCRIPT_FILENAME \\\$document_root\\\$fastcgi_script_name;\\
        include fastcgi_params;\\
    }" "$nginx_conf"
        
        log_info "Configuration PHP ajoutée"
    fi
    
    if ! nginx -t >/dev/null 2>&1; then
        log_error "Config nginx invalide"
        return 1
    fi
    
    systemctl restart nginx >/dev/null 2>&1 || {
        log_error "Échec restart nginx"
        return 1
    }
    
    log_success "Nginx configuré et redémarré"
    return 0
}

install_php_files() {
    log_info "Installation des fichiers PHP"
    
    if [ ! -d "$BASE_DIR/web_files" ]; then
        log_error "Dossier web_files manquant: $BASE_DIR/web_files"
        return 1
    fi
    
    for file in "archives-list.php" "download-archive.php" "download-manager.js"; do
        if [ ! -f "$BASE_DIR/web_files/$file" ]; then
            log_error "Fichier manquant: $file"
            return 1
        fi
        cp "$BASE_DIR/web_files/$file" "$NGINX_DASHBOARD_DIR/"
    done
    
    chown www-data:www-data "$NGINX_DASHBOARD_DIR"/*.php "$NGINX_DASHBOARD_DIR"/*.js 2>/dev/null || true
    chmod 644 "$NGINX_DASHBOARD_DIR"/*.php "$NGINX_DASHBOARD_DIR"/*.js 2>/dev/null || true
    
    log_success "Fichiers PHP installés"
    return 0
}

configure_php_security() {
    local php_version=$1
    local ini_dir="/etc/php/${php_version}/fpm/conf.d"
    
    log_info "Configuration de sécurité PHP"
    
    if [ ! -d "$ini_dir" ]; then
        log_warning "Répertoire ini non trouvé: $ini_dir"
        return 0
    fi
    
    cat > "$ini_dir/maxlink-security.ini" << EOF
disable_functions = exec,passthru,shell_exec,system,proc_open,proc_close,popen,socket_create
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
display_errors = Off
log_errors = On
max_execution_time = 30
memory_limit = 128M
post_max_size = 8M
upload_max_filesize = 2M
session.cookie_httponly = On
session.use_strict_mode = On
EOF
    
    local fpm_service=$(get_php_fpm_service "$php_version")
    systemctl restart "$fpm_service" >/dev/null 2>&1
    
    log_success "Sécurité PHP configurée"
    return 0
}

create_test_archives() {
    log_info "Création archives de test"
    
    local archives_dir="$NGINX_DASHBOARD_DIR/archives"
    mkdir -p "$archives_dir"
    
    local year=$(date +%Y)
    for week in {01..04}; do
        for machine in "S01" "S02"; do
            cat > "$archives_dir/${machine}_${year}_${week}.csv" << EOF
timestamp,machine,status,result
${year}-01-0${week} 09:00:00,$machine,production,95
${year}-01-0${week} 10:00:00,$machine,production,98
EOF
        done
    done
    
    chown -R www-data:www-data "$archives_dir"
    chmod -R 755 "$archives_dir"
    find "$archives_dir" -name "*.csv" -exec chmod 644 {} \;
    
    log_success "Archives test créées"
    return 0
}

# PROGRAMME PRINCIPAL

log_info "========== DÉBUT INSTALLATION PHP ARCHIVES =========="

echo ""
echo "========================================================================"
echo "INSTALLATION PHP ARCHIVES SYSTEM"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

if [ "$EUID" -ne 0 ]; then
    log_error "Privilèges root requis"
    exit 1
fi

echo "✓ Privilèges root confirmés"

send_progress 15 "Vérification des prérequis..."

if ! check_prerequisites; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✓ Tous les prérequis validés"

send_progress 35 "Installation de PHP..."

if command -v php >/dev/null 2>&1; then
    local PHP_VERSION=$(detect_php_version)
    echo "✓ PHP détecté (version $PHP_VERSION)"
    log_info "PHP déjà installé: $PHP_VERSION"
    
    local fpm_service=$(get_php_fpm_service "$PHP_VERSION")
    if ! dpkg -l | grep -q "^ii.*$fpm_service"; then
        echo "  ⚠ Package $fpm_service manquant"
        if ! install_php_from_cache; then
            update_service_status "$SERVICE_ID" "inactive"
            exit 1
        fi
    fi
else
    if ! install_php_from_cache; then
        update_service_status "$SERVICE_ID" "inactive"
        exit 1
    fi
fi

local PHP_VERSION=$(detect_php_version)
if [ -z "$PHP_VERSION" ]; then
    echo "✗ Impossible de détecter la version PHP"
    log_error "Détection version PHP échouée"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✓ PHP version détectée: $PHP_VERSION"

send_progress 55 "Activation PHP-FPM..."

if ! activate_php_fpm "$PHP_VERSION"; then
    echo "✗ ERREUR CRITIQUE: PHP-FPM non activé"
    log_error "Activation PHP-FPM échouée"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✓ PHP-FPM activé"

send_progress 65 "Installation des fichiers..."

if ! install_php_files; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✓ Fichiers PHP installés"

send_progress 75 "Configuration nginx..."

if ! configure_nginx_for_php "$PHP_VERSION"; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✓ Nginx configuré"

send_progress 85 "Configuration de sécurité..."

if ! configure_php_security "$PHP_VERSION"; then
    log_warning "Problème configuration sécurité - continuation"
fi

send_progress 90 "Création archives test..."

if ! create_test_archives; then
    log_warning "Problème création archives test - continuation"
fi

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION RÉUSSIE"
echo "========================================================================"
echo ""

update_service_status "$SERVICE_ID" "active"

local fpm_service=$(get_php_fpm_service "$PHP_VERSION")
local fpm_socket=$(get_php_fpm_socket "$PHP_VERSION")

echo "✓ PHP Archives System installé avec succès !"
echo ""
echo "Configuration:"
echo "  PHP version       : $PHP_VERSION"
echo "  Service FPM       : $fpm_service"
echo "  Socket FPM        : $fpm_socket"
echo "  Dashboard         : $NGINX_DASHBOARD_DIR"
echo "  Archives          : $NGINX_DASHBOARD_DIR/archives"
echo ""

log_success "Installation terminée avec succès"

exit 0