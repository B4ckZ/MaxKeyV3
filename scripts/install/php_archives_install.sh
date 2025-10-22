#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$SCRIPT_DIR/../common/variables.sh"
source "$SCRIPT_DIR/../common/logging.sh"
source "$SCRIPT_DIR/../common/packages.sh"

init_logging "Installation Système PHP Archives" "install"

SERVICE_ID="php_archives"
SERVICE_NAME="PHP Archives System"
SERVICE_DESCRIPTION="Système PHP pour téléchargement des archives de traçabilité"

detect_php_version() {
    if command -v php >/dev/null 2>&1; then
        php -v | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -1
    fi
}

get_php_fpm_service() {
    local version="$1"
    echo "php${version}-fpm"
}

get_php_fpm_socket() {
    local version="$1"
    echo "/run/php/php${version}-fpm.sock"
}

get_php_ini_dir() {
    local version="$1"
    echo "/etc/php/${version}/fpm/conf.d"
}

send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

install_php_deps_from_cache() {
    log_info "Installation des dépendances PHP depuis le cache"
    
    echo "◦ Installation des dépendances système PHP..."
    
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        log_error "Cache de paquets manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    if ! verify_category_cache_complete "php-deps"; then
        log_warn "Catégorie php-deps non trouvée dans le cache - tentative installation apt-get"
        
        for pkg in libargon2-1 libsodium23; do
            if ! dpkg -l | grep -q "^ii.*$pkg"; then
                echo "  → Installation de $pkg via apt-get..."
                if apt-get install -y "$pkg" >/dev/null 2>&1; then
                    echo "  ✓ $pkg installé"
                    log_success "$pkg installé via apt-get"
                else
                    log_warn "Installation apt-get échouée pour $pkg - ignoré"
                fi
            fi
        done
        return 0
    fi
    
    if ! install_packages_by_category_simultaneously "php-deps"; then
        log_warn "Échec installation php-deps depuis le cache"
        return 1
    fi
    
    log_success "Dépendances PHP installées depuis le cache"
    return 0
}

check_prerequisites() {
    log_info "Vérification des prérequis pour $SERVICE_NAME"
    
    if ! command -v nginx >/dev/null 2>&1; then
        log_error "Nginx n'est pas installé"
        return 1
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx n'est pas actif"
        return 1
    fi
    
    if [ ! -d "$NGINX_DASHBOARD_DIR" ]; then
        log_error "Dashboard non installé"
        return 1
    fi
    
    log_success "Prérequis validés"
    return 0
}

install_php_from_cache() {
    log_info "Installation de PHP depuis le cache local"
    
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        log_error "Cache de paquets manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    if ! verify_category_cache_complete "php"; then
        log_error "Cache PHP incomplet"
        return 1
    fi
    
    if ! install_packages_by_category_simultaneously "php"; then
        log_error "Échec de l'installation simultanée PHP"
        return 1
    fi
    
    for pkg in php php-cli php-fpm; do
        if ! dpkg -l "$pkg" >/dev/null 2>&1; then
            log_error "Paquet PHP manquant après installation: $pkg"
            return 1
        fi
    done
    
    log_success "PHP installé avec succès"
    return 0
}

activate_php_fpm() {
    local php_version=$(detect_php_version)
    if [ -z "$php_version" ]; then
        log_error "Impossible de détecter la version PHP"
        return 1
    fi
    
    local fpm_service=$(get_php_fpm_service "$php_version")
    local fpm_socket=$(get_php_fpm_socket "$php_version")
    
    log_info "Activation du service $fpm_service (PHP $php_version)"
    
    if systemctl is-active --quiet "$fpm_service"; then
        log_info "$fpm_service déjà actif"
        return 0
    fi
    
    if ! systemctl enable "$fpm_service" >/dev/null 2>&1; then
        log_error "Échec activation $fpm_service au démarrage"
        return 1
    fi
    
    if ! systemctl start "$fpm_service" >/dev/null 2>&1; then
        log_error "Échec démarrage $fpm_service"
        return 1
    fi
    
    sleep 2
    
    if [ ! -S "$fpm_socket" ]; then
        log_warning "Socket $fpm_service non trouvé: $fpm_socket"
    fi
    
    log_success "$fpm_service activé avec socket $fpm_socket"
    return 0
}

configure_nginx_for_php() {
    local php_version=$(detect_php_version)
    if [ -z "$php_version" ]; then
        log_error "Impossible de détecter la version PHP pour nginx"
        return 1
    fi
    
    local fpm_socket=$(get_php_fpm_socket "$php_version")
    local nginx_conf="/etc/nginx/sites-available/maxlink-dashboard"
    
    log_info "Configuration nginx pour PHP $php_version avec socket $fpm_socket"
    
    if grep -q "\.php" "$nginx_conf" 2>/dev/null; then
        log_info "Configuration PHP déjà présente"
        return 0
    fi
    
    if [ ! -f "$nginx_conf" ]; then
        log_error "Fichier de configuration nginx manquant: $nginx_conf"
        return 1
    fi
    
    local backup_file="$nginx_conf.backup.php.$(date +%Y%m%d_%H%M%S)"
    cp "$nginx_conf" "$backup_file"
    log_info "Backup nginx créé: $backup_file"
    
    if sed -i "/^}$/i\\
\\
    location ~ ^/archives-list\\.php$ {\\
        if (\$args ~ \"(union|select|insert|update|delete|drop|script|javascript|<|>|\\047|\\042|;|--|\\\\\||&)\" ) {\\
            return 400 \"Invalid request\";\\
        }\\
        include snippets/fastcgi-php.conf;\\
        fastcgi_pass unix:${fpm_socket};\\
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\\
        include fastcgi_params;\\
        add_header X-Content-Type-Options nosniff;\\
        add_header X-Frame-Options DENY;\\
        add_header X-XSS-Protection \"1; mode=block\";\\
        add_header Content-Type \"application/json\";\\
    }\\
\\
    location ~ ^/download-archive\\.php$ {\\
        if (\$args ~ \"(union|select|insert|update|delete|drop|script|javascript|<|>|\\047|\\042|;|--|\\\\\||&)\" ) {\\
            return 400 \"Invalid request\";\\
        }\\
        include snippets/fastcgi-php.conf;\\
        fastcgi_pass unix:${fpm_socket};\\
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\\
        include fastcgi_params;\\
        add_header X-Content-Type-Options nosniff;\\
        add_header X-Frame-Options DENY;\\
    }\\
\\
    location ~ \\.php$ {\\
        include snippets/fastcgi-php.conf;\\
        fastcgi_pass unix:${fpm_socket};\\
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\\
        include fastcgi_params;\\
    }" "$nginx_conf"; then
        log_info "Configuration PHP ajoutée à nginx"
    else
        log_error "Échec ajout configuration PHP"
        mv "$backup_file" "$nginx_conf"
        return 1
    fi
    
    if ! nginx -t >/dev/null 2>&1; then
        log_error "Configuration nginx invalide"
        mv "$backup_file" "$nginx_conf"
        systemctl restart nginx >/dev/null 2>&1
        return 1
    fi
    
    if ! systemctl restart nginx >/dev/null 2>&1; then
        log_error "Échec redémarrage nginx"
        mv "$backup_file" "$nginx_conf"
        systemctl restart nginx >/dev/null 2>&1
        return 1
    fi
    
    log_success "Nginx configuré et redémarré"
    return 0
}

install_php_files() {
    log_info "Installation des fichiers PHP et JavaScript"
    
    if [ ! -d "$BASE_DIR/web_files" ]; then
        log_error "Dossier web_files manquant: $BASE_DIR/web_files"
        return 1
    fi
    
    local required_files=("archives-list.php" "download-archive.php" "download-manager.js")
    for file in "${required_files[@]}"; do
        if [ ! -f "$BASE_DIR/web_files/$file" ]; then
            log_error "Fichier manquant: $file"
            return 1
        fi
        cp "$BASE_DIR/web_files/$file" "$NGINX_DASHBOARD_DIR/"
    done
    
    chown www-data:www-data "$NGINX_DASHBOARD_DIR"/*.php "$NGINX_DASHBOARD_DIR"/*.js
    chmod 644 "$NGINX_DASHBOARD_DIR"/*.php "$NGINX_DASHBOARD_DIR"/*.js
    
    log_success "Fichiers PHP et JavaScript installés"
    return 0
}

configure_permissions_strict() {
    log_info "Configuration permissions strictes (644)"
    
    find "$NGINX_DASHBOARD_DIR" -name "*.php" -exec chmod 644 {} \;
    find "$NGINX_DASHBOARD_DIR" -name "*.js" -exec chmod 644 {} \;
    find "$NGINX_DASHBOARD_DIR" -type d -exec chmod 755 {} \;
    
    chown -R www-data:www-data "$NGINX_DASHBOARD_DIR"
    
    log_success "Permissions strictes appliquées"
    return 0
}

optimize_php_security() {
    local php_version=$(detect_php_version)
    if [ -z "$php_version" ]; then
        log_warning "Impossible de détecter la version PHP pour optimisation"
        return 1
    fi
    
    local php_ini_dir=$(get_php_ini_dir "$php_version")
    local php_ini_custom="$php_ini_dir/99-maxlink-security.ini"
    
    log_info "Optimisation sécurité PHP $php_version"
    
    cat > "$php_ini_custom" << 'EOF'
display_errors = Off
log_errors = On
expose_php = Off
allow_url_fopen = Off
allow_url_include = Off
file_uploads = Off
max_execution_time = 30
max_input_time = 30
memory_limit = 64M
post_max_size = 8M
upload_max_filesize = 2M
session.cookie_httponly = On
session.cookie_secure = Off
session.use_strict_mode = On
EOF
    
    local fpm_service=$(get_php_fpm_service "$php_version")
    if systemctl restart "$fpm_service" >/dev/null 2>&1; then
        log_success "Sécurité PHP optimisée et service redémarré"
        return 0
    else
        log_warning "Problème redémarrage $fpm_service après optimisation"
        return 0
    fi
}

create_test_archives() {
    log_info "Création archives de test"
    
    local archives_dir="$NGINX_DASHBOARD_DIR/archives"
    mkdir -p "$archives_dir"
    
    local current_year=$(date +%Y)
    for week in {01..04}; do
        for machine in "S01" "S02"; do
            cat > "$archives_dir/${machine}_${current_year}_${week}.csv" << EOF
timestamp,machine,status,result,humidity,temp
${current_year}-01-0${week} 09:00:00,$machine,production,95,OK,22.5,1.15
${current_year}-01-0${week} 10:00:00,$machine,production,98,OK,22.8,1.18
${current_year}-01-0${week} 11:00:00,$machine,production,102,OK,23.2,1.22
${current_year}-01-0${week} 12:00:00,$machine,maintenance,0,MAINT,21.5,0.8
${current_year}-01-0${week} 13:00:00,$machine,production,107,OK,23.4,1.28
EOF
        done
    done
    
    chown -R www-data:www-data "$archives_dir"
    chmod -R 755 "$archives_dir"
    find "$archives_dir" -name "*.csv" -exec chmod 644 {} \;
    
    log_success "Archives de test créées"
    return 0
}

test_php_service() {
    local php_version=$(detect_php_version)
    if [ -z "$php_version" ]; then
        log_error "Impossible de détecter version PHP pour tests"
        return 1
    fi
    
    local fpm_service=$(get_php_fpm_service "$php_version")
    local fpm_socket=$(get_php_fpm_socket "$php_version")
    
    log_info "Test service PHP $php_version"
    
    if ! php -v >/dev/null 2>&1; then
        log_error "PHP CLI non fonctionnel"
        return 1
    fi
    
    if ! systemctl is-active --quiet "$fpm_service"; then
        log_error "$fpm_service inactif"
        return 1
    fi
    
    if [ ! -S "$fpm_socket" ]; then
        log_error "Socket PHP non accessible: $fpm_socket"
        return 1
    fi
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php" 2>/dev/null || echo "000")
    if [ "$http_code" != "200" ] && [ "$http_code" != "000" ]; then
        log_warning "HTTP code archives-list.php: $http_code"
    fi
    
    log_success "Tests PHP réussis"
    return 0
}

# PROGRAMME PRINCIPAL
log_info "========== DÉBUT DE L'INSTALLATION $SERVICE_NAME =========="

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

echo "✅ Privilèges root confirmés"

echo ""
echo "========================================================================"
echo "ÉTAPE 0 : INSTALLATION DÉPENDANCES SYSTÈME"
echo "========================================================================"

send_progress 8 "Installation dépendances..."

if ! install_php_deps_from_cache; then
    log_warn "Problème installation dépendances - continuation"
fi

send_progress 10 "Dépendances prêtes"

echo ""
echo "========================================================================"
echo "ÉTAPE 1 : VÉRIFICATION DES PRÉREQUIS"
echo "========================================================================"

send_progress 15 "Vérification des prérequis..."

if ! check_prerequisites; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✅ Tous les prérequis sont satisfaits"
send_progress 25 "Prérequis validés"

echo ""
echo "========================================================================"
echo "ÉTAPE 2 : INSTALLATION PHP"
echo "========================================================================"

send_progress 35 "Installation de PHP..."

if command -v php >/dev/null 2>&1; then
    local PHP_VERSION=$(detect_php_version)
    echo "✅ PHP déjà installé (version $PHP_VERSION)"
    log_info "PHP détecté: version $PHP_VERSION"
    
    local missing_components=""
    for pkg in php-cli php-fpm; do
        if ! dpkg -l "$pkg" >/dev/null 2>&1; then
            missing_components="$missing_components $pkg"
        fi
    done
    
    if [ -n "$missing_components" ]; then
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

echo "✅ PHP installé avec succès"
send_progress 50 "PHP installé"

echo ""
echo "========================================================================"
echo "ÉTAPE 3 : ACTIVATION PHP-FPM"
echo "========================================================================"

send_progress 55 "Activation PHP-FPM..."

if ! activate_php_fpm; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✅ PHP-FPM activé avec succès"
send_progress 60 "PHP-FPM activé"

echo ""
echo "========================================================================"
echo "ÉTAPE 4 : INSTALLATION FICHIERS"
echo "========================================================================"

send_progress 65 "Installation fichiers..."

if ! install_php_files; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 70 "Fichiers installés"

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : CONFIGURATION NGINX"
echo "========================================================================"

send_progress 75 "Configuration nginx..."

if ! configure_nginx_for_php; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "✅ Nginx configuré"
send_progress 80 "Nginx configuré"

echo ""
echo "========================================================================"
echo "ÉTAPE 6 : PERMISSIONS ET SÉCURITÉ"
echo "========================================================================"

send_progress 82 "Permissions strictes..."

if ! configure_permissions_strict; then
    log_warning "Problème permissions"
fi

send_progress 85 "Permissions configurées"

send_progress 87 "Optimisation sécurité..."

if ! optimize_php_security; then
    log_warning "Problème optimisation sécurité"
fi

send_progress 90 "Sécurité optimisée"

echo ""
echo "========================================================================"
echo "ÉTAPE 7 : TESTS FINAUX"
echo "========================================================================"

send_progress 92 "Création archives test..."

if ! create_test_archives; then
    log_warning "Problème création archives test"
fi

send_progress 95 "Validation..."

if ! test_php_service; then
    log_warning "Tests PHP échoués - vérification manuelle recommandée"
fi

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE"
echo "========================================================================"
echo ""

update_service_status "$SERVICE_ID" "active"

local php_version=$(detect_php_version)
local fpm_service=$(get_php_fpm_service "$php_version")
local fpm_socket=$(get_php_fpm_socket "$php_version")

echo "🎉 $SERVICE_NAME installé avec succès !"
echo ""
echo "Configuration appliquée:"
echo "  • PHP version: $php_version"
echo "  • Service FPM: $fpm_service"
echo "  • Socket: $fpm_socket"
echo "  • Dashboard: $NGINX_DASHBOARD_DIR"
echo ""

log_success "Installation $SERVICE_NAME terminée avec succès"

exit 0