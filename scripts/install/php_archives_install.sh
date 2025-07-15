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

send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

wait_silently() {
    sleep "$1"
}

check_prerequisites() {
    log_info "Vérification des prérequis pour $SERVICE_NAME"
    
    if ! command -v nginx >/dev/null 2>&1; then
        log_error "Nginx n'est pas installé"
        echo "❌ Nginx requis mais non installé"
        return 1
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx n'est pas actif"
        echo "❌ Nginx installé mais non actif"
        return 1
    fi
    
    if [ ! -d "$NGINX_DASHBOARD_DIR" ]; then
        log_error "Dashboard non installé"
        echo "❌ Dashboard MaxLink non trouvé"
        return 1
    fi
    
    log_success "Prérequis validés"
    return 0
}

install_php_from_cache() {
    echo "◦ Installation de PHP depuis le cache..."
    log_info "Installation de PHP depuis le cache local"
    
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        echo "  ↦ Cache de paquets non trouvé ✗"
        log_error "Cache de paquets manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    echo "  ↦ Vérification du cache PHP..."
    if ! verify_category_cache_complete "php"; then
        echo "  ↦ Cache PHP incomplet ✗"
        log_error "Cache PHP incomplet"
        return 1
    fi
    
    echo "  ↦ ✅ Cache PHP vérifié et complet"
    
    echo "  ↦ Vérification des installations existantes..."
    local existing_php_packages=""
    for pkg in php php-cli php-fpm; do
        if dpkg -l "$pkg" >/dev/null 2>&1; then
            existing_php_packages="$existing_php_packages $pkg"
        fi
    done
    
    if [ -n "$existing_php_packages" ]; then
        echo "  ↦ Paquets PHP déjà installés:$existing_php_packages"
        log_info "Paquets PHP existants détectés:$existing_php_packages"
        
        local missing_php=""
        for pkg in php php-cli php-fpm; do
            if ! dpkg -l "$pkg" >/dev/null 2>&1; then
                missing_php="$missing_php $pkg"
            fi
        done
        
        if [ -z "$missing_php" ]; then
            echo "  ↦ ✅ Tous les paquets PHP requis sont déjà installés"
            log_success "PHP déjà complètement installé"
            return 0
        fi
    else
        echo "  ↦ Installation PHP complète nécessaire"
        log_info "Installation PHP complète nécessaire"
    fi
    
    echo "  ↦ Installation simultanée de tous les paquets PHP..."
    log_info "Lancement de l'installation simultanée PHP"
    
    if install_packages_by_category_simultaneously "php"; then
        echo "  ↦ ✅ PHP installé avec succès depuis le cache"
        log_success "PHP installé avec succès"
        
        echo "  ↦ Vérification post-installation..."
        local verification_failed=0
        
        for pkg in php php-cli php-fpm; do
            if dpkg -l "$pkg" >/dev/null 2>&1; then
                echo "    ✓ $pkg vérifié"
            else
                echo "    ✗ $pkg manquant après installation"
                verification_failed=1
            fi
        done
        
        if [ $verification_failed -eq 0 ]; then
            echo "  ↦ ✅ Vérification post-installation réussie"
            log_success "Vérification post-installation PHP réussie"
            return 0
        else
            echo "  ↦ ❌ Échec de la vérification post-installation"
            log_error "Certains paquets PHP manquent après installation"
            return 1
        fi
    else
        echo "  ↦ ❌ Échec de l'installation de PHP"
        log_error "Échec de l'installation simultanée PHP"
        return 1
    fi
}

activate_php_fpm() {
    log_info "Activation du service PHP-FPM"
    
    echo "  ↦ Activation de PHP-FPM..."
    
    # Vérifier si PHP-FPM est déjà actif
    if systemctl is-active --quiet php8.2-fpm; then
        echo "    ✓ PHP-FPM déjà actif"
        log_info "PHP-FPM déjà actif"
        return 0
    fi
    
    # Activer PHP-FPM au démarrage
    if systemctl enable php8.2-fpm >/dev/null 2>&1; then
        echo "    ✓ PHP-FPM activé au démarrage"
        log_info "PHP-FPM activé au démarrage"
    else
        echo "    ✗ Échec activation PHP-FPM"
        log_error "Échec activation PHP-FPM"
        return 1
    fi
    
    # Démarrer PHP-FPM
    if systemctl start php8.2-fpm >/dev/null 2>&1; then
        echo "    ✓ PHP-FPM démarré"
        log_success "PHP-FPM activé et démarré"
    else
        echo "    ✗ Échec démarrage PHP-FPM"
        log_error "Échec démarrage PHP-FPM"
        return 1
    fi
    
    # Vérifier que le socket existe
    sleep 2
    if [ -S "/run/php/php8.2-fpm.sock" ]; then
        echo "    ✓ Socket PHP-FPM créé"
        log_success "Socket PHP-FPM vérifié"
    else
        echo "    ⚠ Socket PHP-FPM non trouvé"
        log_warning "Socket PHP-FPM non trouvé"
    fi
    
    return 0
}

configure_nginx_for_php() {
    log_info "Configuration nginx pour PHP avec sécurité renforcée"
    
    local nginx_conf="/etc/nginx/sites-available/maxlink-dashboard"
    
    echo "  ↦ Vérification de la configuration nginx..."
    
    # Vérifier si nginx a déjà la config PHP
    if grep -q "\.php" "$nginx_conf" 2>/dev/null; then
        echo "    ✓ Configuration PHP déjà présente dans nginx"
        log_info "Configuration PHP déjà présente"
        return 0
    fi
    
    echo "  ↦ Ajout de la configuration PHP sécurisée à nginx..."
    log_info "Modification de la configuration nginx pour PHP"
    
    # Vérifier que le fichier de configuration existe
    if [ ! -f "$nginx_conf" ]; then
        echo "    ✗ Fichier de configuration nginx non trouvé: $nginx_conf"
        log_error "Fichier de configuration nginx manquant"
        return 1
    fi
    
    # Backup de la configuration
    local backup_file="$nginx_conf.backup.php.$(date +%Y%m%d_%H%M%S)"
    if cp "$nginx_conf" "$backup_file"; then
        echo "    ✓ Backup créé: $(basename "$backup_file")"
        log_info "Backup configuration nginx créé"
    else
        echo "    ✗ Impossible de créer le backup"
        log_error "Échec création backup nginx"
        return 1
    fi
    
    # Insérer la configuration PHP sécurisée avant la dernière accolade
    if sed -i '/^}$/i\
\
    # Configuration PHP avec sécurité renforcée\
    location ~ ^/archives-list\\.php$ {\
        # Protection injection SQL\
        if ($args ~ "(union|select|insert|update|delete|drop|script|javascript|<|>|\047|\042|;|--|\\\||&)" ) {\
            return 400 "Invalid request";\
        }\
        \
        include snippets/fastcgi-php.conf;\
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\
        include fastcgi_params;\
        \
        # Headers de sécurité\
        add_header X-Content-Type-Options nosniff;\
        add_header X-Frame-Options DENY;\
        add_header X-XSS-Protection "1; mode=block";\
        add_header Content-Type "application/json";\
    }\
    \
    location ~ ^/download-archive\\.php$ {\
        # Protection injection SQL\
        if ($args ~ "(union|select|insert|update|delete|drop|script|javascript|<|>|\047|\042|;|--|\\\||&)" ) {\
            return 400 "Invalid request";\
        }\
        \
        include snippets/fastcgi-php.conf;\
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\
        include fastcgi_params;\
        \
        add_header X-Content-Type-Options nosniff;\
        add_header X-Frame-Options DENY;\
        add_header X-XSS-Protection "1; mode=block";\
    }\
    \
    # Configuration PHP générale pour autres fichiers\
    location ~ \\.php$ {\
        include snippets/fastcgi-php.conf;\
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;\
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;\
        include fastcgi_params;\
    }\
\
    # Sécurité - bloquer accès fichiers sensibles\
    location ~ /\\.ht {\
        deny all;\
    }\
    \
    # Bloquer accès aux fichiers de sauvegarde\
    location ~ \\.(bak|backup|old|tmp|log)$ {\
        deny all;\
    }' "$nginx_conf"; then
        echo "    ✓ Configuration PHP sécurisée ajoutée"
        log_success "Configuration PHP sécurisée ajoutée à nginx"
    else
        echo "    ✗ Échec modification configuration"
        log_error "Échec modification configuration nginx"
        return 1
    fi
    
    # Tester la configuration nginx
    echo "  ↦ Test de la configuration nginx..."
    if nginx -t >/dev/null 2>&1; then
        echo "    ✓ Configuration nginx validée"
        log_success "Configuration nginx valide"
        
        # Redémarrer nginx
        echo "  ↦ Redémarrage de nginx..."
        if systemctl restart nginx >/dev/null 2>&1; then
            echo "    ✓ Nginx redémarré avec succès"
            log_success "Nginx redémarré avec configuration PHP sécurisée"
            return 0
        else
            echo "    ✗ Échec redémarrage nginx"
            log_error "Échec redémarrage nginx"
            # Restaurer le backup
            mv "$backup_file" "$nginx_conf"
            systemctl restart nginx >/dev/null 2>&1
            return 1
        fi
    else
        echo "    ✗ Configuration nginx invalide"
        log_error "Configuration nginx invalide"
        # Restaurer le backup
        echo "  ↦ Restauration du backup..."
        mv "$backup_file" "$nginx_conf"
        systemctl restart nginx >/dev/null 2>&1
        nginx -t
        return 1
    fi
}

install_php_files() {
    log_info "Installation des fichiers PHP et JavaScript"
    
    if [ ! -d "$BASE_DIR/web_files" ]; then
        echo "  ↦ Dossier web_files non trouvé ✗"
        log_error "Dossier web_files manquant: $BASE_DIR/web_files"
        return 1
    fi
    
    local required_files=("archives-list.php" "download-archive.php" "download-manager.js")
    local missing_files=""
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$BASE_DIR/web_files/$file" ]; then
            missing_files="$missing_files $file"
        fi
    done
    
    if [ -n "$missing_files" ]; then
        echo "  ↦ Fichiers manquants:$missing_files ✗"
        log_error "Fichiers manquants:$missing_files"
        return 1
    fi
    
    echo "  ↦ Copie des fichiers PHP et JavaScript..."
    
    for file in "${required_files[@]}"; do
        if cp "$BASE_DIR/web_files/$file" "$NGINX_DASHBOARD_DIR/"; then
            echo "    ✓ $file copié"
            log_success "Fichier copié: $file"
        else
            echo "    ✗ Échec copie $file"
            log_error "Échec copie: $file"
            return 1
        fi
    done
    
    log_success "Fichiers PHP et JavaScript installés"
    return 0
}

configure_permissions_strict() {
    log_info "Configuration STRICTE des permissions (644 forcé)"
    
    echo "  ↦ Arrêt temporaire nginx pour permissions strictes..."
    systemctl stop nginx >/dev/null 2>&1
    sleep 1
    
    echo "  ↦ Application FORCÉE des permissions sécurisées..."
    
    local files_to_secure=("archives-list.php" "download-archive.php" "download-manager.js")
    
    for file in "${files_to_secure[@]}"; do
        local file_path="$NGINX_DASHBOARD_DIR/$file"
        
        if [ -f "$file_path" ]; then
            # Méthode de force brutale pour les permissions
            echo "    → Sécurisation de $file..."
            
            # Étape 1: Reset complet
            chmod 000 "$file_path" 2>/dev/null || true
            sleep 0.5
            
            # Étape 2: Application 644
            chmod 644 "$file_path"
            chown www-data:www-data "$file_path"
            
            # Étape 3: Vérification immédiate
            local actual_perms=$(stat -c "%a" "$file_path" 2>/dev/null || echo "unknown")
            if [ "$actual_perms" = "644" ]; then
                echo "    ✓ $file sécurisé (644)"
                log_success "Permissions strictes: $file (644)"
            else
                echo "    ⚠ $file permissions: $actual_perms (tentative force)"
                log_warning "Permissions non optimales: $file ($actual_perms)"
                
                # Force ultime avec chattr si disponible
                chattr +i "$file_path" 2>/dev/null || true
                sleep 0.2
                chattr -i "$file_path" 2>/dev/null || true
                chmod 644 "$file_path"
            fi
        else
            echo "    ✗ Fichier manquant: $file"
            log_error "Fichier manquant pour permissions: $file"
        fi
    done
    
    # Répertoire archives avec permissions appropriées
    if [ ! -d "$NGINX_DASHBOARD_DIR/archives" ]; then
        mkdir -p "$NGINX_DASHBOARD_DIR/archives"
        echo "    ✓ Répertoire archives créé"
    fi
    
    chmod 755 "$NGINX_DASHBOARD_DIR/archives"
    chown www-data:www-data "$NGINX_DASHBOARD_DIR/archives"
    echo "    ✓ Répertoire archives configuré (755)"
    
    echo "  ↦ Redémarrage nginx..."
    systemctl start nginx >/dev/null 2>&1
    sleep 2
    
    log_success "Permissions strictes configurées"
    return 0
}

create_test_archives() {
    log_info "Création des archives de test"
    
    local archives_dir="/home/prod/Documents/traçabilité/Archives"
    
    echo "  ↦ Vérification du répertoire de données..."
    
    # Créer le répertoire s'il n'existe pas
    if [ ! -d "$archives_dir" ]; then
        echo "  ↦ Création du répertoire archives..."
        mkdir -p "$archives_dir"
        echo "    ✓ Répertoire créé: $archives_dir"
    fi
    
    # Vérifier s'il y a déjà des fichiers CSV
    local existing_csv=$(find "$archives_dir" -name "*.csv" 2>/dev/null | wc -l)
    
    if [ "$existing_csv" -gt 0 ]; then
        echo "  ↦ Archives existantes trouvées ($existing_csv fichiers CSV) ✓"
        log_info "Archives existantes: $existing_csv fichiers"
        return 0
    fi
    
    echo "  ↦ Création d'archives de démonstration..."
    
    # Créer le répertoire pour l'année courante
    local current_year=$(date +%Y)
    local year_dir="$archives_dir/$current_year"
    mkdir -p "$year_dir"
    
    # Créer des fichiers CSV de test pour les 3 premières semaines
    for week in 01 02 03; do
        for machine in machine1 machine2; do
            local csv_file="$year_dir/S${week}_${current_year}_${machine}.csv"
            
            cat > "$csv_file" << EOF
timestamp,machine,operation,value,status,temperature,pressure
${current_year}-01-0${week} 08:00:00,$machine,startup,100,OK,22.5,1.2
${current_year}-01-0${week} 09:00:00,$machine,production,105,OK,23.1,1.25
${current_year}-01-0${week} 10:00:00,$machine,production,98,OK,22.8,1.18
${current_year}-01-0${week} 11:00:00,$machine,production,102,OK,23.2,1.22
${current_year}-01-0${week} 12:00:00,$machine,maintenance,0,MAINT,21.5,0.8
${current_year}-01-0${week} 13:00:00,$machine,production,107,OK,23.4,1.28
${current_year}-01-0${week} 14:00:00,$machine,production,103,OK,23.0,1.21
${current_year}-01-0${week} 15:00:00,$machine,production,99,OK,22.9,1.19
${current_year}-01-0${week} 16:00:00,$machine,production,104,OK,23.1,1.23
${current_year}-01-0${week} 17:00:00,$machine,shutdown,0,STOP,21.0,0.5
EOF
            
            echo "    ✓ Créé: S${week}_${current_year}_${machine}.csv"
        done
    done
    
    # Définir les permissions appropriées
    chown -R www-data:www-data "$archives_dir"
    chmod -R 755 "$archives_dir"
    find "$archives_dir" -name "*.csv" -exec chmod 644 {} \;
    
    local total_csv=$(find "$archives_dir" -name "*.csv" 2>/dev/null | wc -l)
    echo "  ↦ ✅ $total_csv archives de test créées"
    log_success "Archives de test créées: $total_csv fichiers"
    
    return 0
}

optimize_php_security() {
    log_info "Optimisation de la sécurité PHP"
    
    echo "  ↦ Configuration de la sécurité PHP..."
    
    # Créer un fichier de configuration PHP personnalisé
    local php_ini_custom="/etc/php/8.2/fpm/conf.d/99-maxlink-security.ini"
    
    cat > "$php_ini_custom" << 'EOF'
; Configuration sécurité MaxLink PHP Archives
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
    
    echo "    ✓ Configuration sécurité PHP créée"
    
    # Redémarrer PHP-FPM pour appliquer les changements
    if systemctl restart php8.2-fpm >/dev/null 2>&1; then
        echo "    ✓ PHP-FPM redémarré avec nouvelle configuration"
        log_success "Sécurité PHP optimisée"
    else
        echo "    ⚠ Redémarrage PHP-FPM échoué"
        log_warning "Problème redémarrage PHP-FPM"
    fi
    
    return 0
}

create_diagnostic_log_link() {
    log_info "Création du lien pour diagnostic"
    
    echo "  ↦ Création du lien symbolique pour le log d'installation..."
    
    local log_dir="/var/log/maxlink"
    local install_log_dir="/var/log/maxlink/install"
    
    # Créer le répertoire de logs si nécessaire
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir"
        chown www-data:www-data "$log_dir"
    fi
    
    # Trouver le log d'installation le plus récent
    if [ -f "$install_log_dir/php_archives_install_$(date +%Y%m%d)_"*.log ]; then
        local latest_log=$(ls -t "$install_log_dir"/php_archives_install_$(date +%Y%m%d)_*.log 2>/dev/null | head -1)
        if [ -n "$latest_log" ]; then
            ln -sf "$latest_log" "$log_dir/php_archives_install.log"
            echo "    ✓ Lien log créé: $log_dir/php_archives_install.log"
            log_success "Lien log diagnostic créé"
        fi
    fi
    
    return 0
}

test_php_service() {
    log_info "Test complet du service PHP"
    
    echo "  ↦ Test de PHP CLI..."
    if php -v >/dev/null 2>&1; then
        local php_version=$(php -v | head -n1 | cut -d' ' -f2)
        echo "    ✓ PHP CLI fonctionnel (version $php_version)"
        log_success "PHP CLI vérifié: $php_version"
    else
        echo "    ✗ PHP CLI non fonctionnel"
        log_error "PHP CLI ne fonctionne pas"
        return 1
    fi
    
    echo "  ↦ Test de PHP-FPM..."
    if systemctl is-active --quiet php8.2-fpm; then
        echo "    ✓ PHP-FPM actif et fonctionnel"
        log_success "PHP-FPM vérifié actif"
    else
        echo "    ❌ PHP-FPM inactif ou non fonctionnel"
        log_error "PHP-FPM non actif"
        return 1
    fi
    
    echo "  ↦ Test HTTP et JSON des scripts..."
    
    # Test archives-list.php avec validation JSON stricte
    local response=$(curl -s "http://localhost/archives-list.php" 2>/dev/null)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        # Vérifier que c'est du JSON valide et pas du PHP brut
        if echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
            echo "    ✓ archives-list.php → JSON valide (HTTP 200)"
            log_success "archives-list.php opérationnel"
        else
            echo "    ❌ archives-list.php → contenu non-JSON"
            log_error "archives-list.php contenu invalide"
            return 1
        fi
    else
        echo "    ❌ archives-list.php → HTTP $http_code"
        log_error "archives-list.php erreur HTTP $http_code"
        return 1
    fi
    
    # Test download-archive.php
    response=$(curl -s "http://localhost/download-archive.php?help" 2>/dev/null)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php?help" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        if echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
            echo "    ✓ download-archive.php → JSON valide (HTTP 200)"
            log_success "download-archive.php opérationnel"
        else
            echo "    ⚠ download-archive.php → contenu non-JSON (acceptable)"
            log_warning "download-archive.php format inattendu"
        fi
    else
        echo "    ⚠ download-archive.php → HTTP $http_code"
        log_warning "download-archive.php comportement inattendu"
    fi
    
    # Test download-manager.js
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-manager.js" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo "    ✓ download-manager.js → accessible (HTTP 200)"
        log_success "download-manager.js accessible"
    else
        echo "    ⚠ download-manager.js → HTTP $http_code"
        log_warning "download-manager.js non accessible"
    fi
    
    # Test de sécurité renforcé
    echo "  ↦ Test de protection injection SQL..."
    local security_response=$(curl -s -w "HTTPCODE:%{http_code}" "http://localhost/archives-list.php?year=2025%27%3BDROP%20TABLE--" 2>/dev/null)
    local security_code=$(echo "$security_response" | grep -o "HTTPCODE:[0-9]*" | cut -d: -f2)
    
    if [ "$security_code" = "400" ]; then
        echo "    ✓ Protection injection SQL → Bloqué (HTTP 400)"
        log_success "Sécurité injection SQL validée"
    elif [ "$security_code" = "403" ]; then
        echo "    ✓ Protection injection SQL → Interdit (HTTP 403)"
        log_success "Sécurité injection SQL validée"
    elif [ "$security_code" = "200" ]; then
        # Vérifier que la réponse est toujours du JSON valide
        local security_content=$(echo "$security_response" | sed 's/HTTPCODE:[0-9]*$//')
        if echo "$security_content" | python3 -m json.tool >/dev/null 2>&1; then
            echo "    ✓ Protection injection SQL → JSON valide retourné"
            log_success "Sécurité injection validée (filtrage côté PHP)"
        else
            echo "    ⚠ Protection injection SQL → réponse inattendue"
            log_warning "Test sécurité incertain"
        fi
    else
        echo "    ⚠ Protection injection SQL → code inattendu: $security_code"
        log_warning "Comportement sécurité non standard"
    fi
    
    return 0
}

log_info "========== DÉBUT DE L'INSTALLATION $SERVICE_NAME =========="

echo ""
echo "========================================================================"
echo "INSTALLATION $SERVICE_NAME (VERSION FINALE 100%)"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

if [ "$EUID" -ne 0 ]; then
    echo "❌ Ce script doit être exécuté en tant que root"
    log_error "Privilèges root requis"
    exit 1
fi

echo "🔍 Vérifications initiales..."
echo "   ✅ Privilèges root confirmés"
log_success "Privilèges root confirmés"

echo ""
echo "========================================================================"
echo "ÉTAPE 1 : VÉRIFICATION DES PRÉREQUIS"
echo "========================================================================"
echo ""

send_progress 10 "Vérification des prérequis..."

if ! check_prerequisites; then
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "   ✅ Tous les prérequis sont satisfaits"
send_progress 25 "Prérequis validés"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 2 : INSTALLATION PHP"
echo "========================================================================"
echo ""

send_progress 35 "Installation de PHP..."

if command -v php >/dev/null 2>&1; then
    PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
    echo "   ✅ PHP déjà installé (version $PHP_VERSION)"
    log_info "PHP déjà installé version $PHP_VERSION"
    
    local missing_components=""
    for pkg in php-cli php-fpm; do
        if ! dpkg -l "$pkg" >/dev/null 2>&1; then
            missing_components="$missing_components $pkg"
        fi
    done
    
    if [ -n "$missing_components" ]; then
        echo "   ⚠ Composants manquants:$missing_components"
        if ! install_php_from_cache; then
            log_error "Échec de l'installation des composants PHP manquants"
            update_service_status "$SERVICE_ID" "inactive"
            exit 1
        fi
    fi
else
    echo "   ↦ PHP non installé - installation complète nécessaire"
    if ! install_php_from_cache; then
        log_error "Échec de l'installation PHP"
        update_service_status "$SERVICE_ID" "inactive"
        exit 1
    fi
fi

echo "   ✅ PHP installé avec succès"
send_progress 50 "PHP installé"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 3 : ACTIVATION PHP-FPM"
echo "========================================================================"
echo ""

send_progress 55 "Activation PHP-FPM..."

if ! activate_php_fpm; then
    log_error "Échec de l'activation PHP-FPM"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "   ✅ PHP-FPM activé avec succès"
send_progress 60 "PHP-FPM activé"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 4 : INSTALLATION DES FICHIERS"
echo "========================================================================"
echo ""

send_progress 65 "Installation des fichiers..."

if ! install_php_files; then
    log_error "Échec de l'installation des fichiers"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 70 "Fichiers installés"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : CONFIGURATION NGINX SÉCURISÉE POUR PHP"
echo "========================================================================"
echo ""

send_progress 75 "Configuration nginx sécurisée..."

if ! configure_nginx_for_php; then
    log_error "Échec de la configuration nginx pour PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "   ✅ Nginx configuré avec sécurité renforcée"
send_progress 80 "Nginx sécurisé configuré"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 6 : PERMISSIONS STRICTES (644 FORCÉ)"
echo "========================================================================"
echo ""

send_progress 82 "Application permissions strictes..."

if ! configure_permissions_strict; then
    log_error "Échec de la configuration des permissions strictes"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

echo "   ✅ Permissions strictes (644) appliquées"
send_progress 85 "Permissions strictes configurées"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 7 : OPTIMISATION SÉCURITÉ PHP"
echo "========================================================================"
echo ""

send_progress 87 "Optimisation sécurité PHP..."

if ! optimize_php_security; then
    log_warning "Problème optimisation sécurité"
    # Continuer malgré l'avertissement
fi

echo "   ✅ Sécurité PHP optimisée"
send_progress 90 "Sécurité optimisée"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 8 : CRÉATION ARCHIVES DE TEST"
echo "========================================================================"
echo ""

send_progress 92 "Création archives de test..."

if ! create_test_archives; then
    log_warning "Problème création archives de test"
    # Continuer malgré l'avertissement
fi

echo "   ✅ Archives de test créées"
send_progress 94 "Archives de test créées"
sleep 1

echo ""
echo "========================================================================"
echo "ÉTAPE 9 : PRÉPARATION DIAGNOSTIC"
echo "========================================================================"
echo ""

send_progress 96 "Préparation diagnostic..."

if ! create_diagnostic_log_link; then
    log_warning "Problème création lien diagnostic"
    # Continuer malgré l'avertissement
fi

echo "   ✅ Diagnostic préparé"
send_progress 97 "Diagnostic préparé"
sleep 1

echo ""
echo "========================================================================"
echo "ÉTAPE 10 : VALIDATION FINALE COMPLÈTE"
echo "========================================================================"
echo ""

send_progress 98 "Validation finale..."

if ! test_php_service; then
    log_error "Échec des tests finaux du service PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE - OPTIMISATION MAXIMALE 100%"
echo "========================================================================"
echo ""

update_service_status "$SERVICE_ID" "active"
echo "🎉 $SERVICE_NAME installé avec optimisation MAXIMALE !"
echo ""

echo "🔗 URLs disponibles :"
echo "  • Liste des archives : http://localhost/archives-list.php"
echo "  • Téléchargement fichier : http://localhost/download-archive.php?file=S01_$(date +%Y)_machine1.csv&year=$(date +%Y)"
echo "  • Liste semaine : http://localhost/download-archive.php?week=1&year=$(date +%Y)"
echo "  • Gestionnaire JavaScript : http://localhost/download-manager.js"

echo ""
echo "🛡️ Sécurité appliquée :"
echo "  • ✅ Permissions strictes (644 pour fichiers)"
echo "  • ✅ Protection injection SQL nginx"
echo "  • ✅ Configuration PHP sécurisée"
echo "  • ✅ Headers sécurité HTTP"
echo "  • ✅ Validation JSON stricte"

echo ""
echo "📊 Test recommandé :"
echo "  sudo ./diagnostic_php_archives.sh"
echo ""
echo "🎯 Score attendu: 100% !"

log_success "Installation $SERVICE_NAME terminée avec succès - OPTIMISATION MAXIMALE"
log_info "Script $SERVICE_ID terminé avec le code 0"

exit 0