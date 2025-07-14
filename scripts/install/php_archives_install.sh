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

configure_permissions() {
    log_info "Configuration des permissions pour $SERVICE_NAME"
    
    echo "  ↦ Configuration des permissions des fichiers..."
    
    if [ -f "$NGINX_DASHBOARD_DIR/archives-list.php" ]; then
        chmod 644 "$NGINX_DASHBOARD_DIR/archives-list.php"
        chown www-data:www-data "$NGINX_DASHBOARD_DIR/archives-list.php"
        echo "    ✓ archives-list.php configuré"
    fi
    
    if [ -f "$NGINX_DASHBOARD_DIR/download-archive.php" ]; then
        chmod 644 "$NGINX_DASHBOARD_DIR/download-archive.php"
        chown www-data:www-data "$NGINX_DASHBOARD_DIR/download-archive.php"
        echo "    ✓ download-archive.php configuré"
    fi
    
    if [ -f "$NGINX_DASHBOARD_DIR/download-manager.js" ]; then
        chmod 644 "$NGINX_DASHBOARD_DIR/download-manager.js"
        chown www-data:www-data "$NGINX_DASHBOARD_DIR/download-manager.js"
        echo "    ✓ download-manager.js configuré"
    fi
    
    if [ ! -d "$NGINX_DASHBOARD_DIR/archives" ]; then
        mkdir -p "$NGINX_DASHBOARD_DIR/archives"
        echo "    ✓ Répertoire archives créé"
    fi
    
    chmod 755 "$NGINX_DASHBOARD_DIR/archives"
    chown www-data:www-data "$NGINX_DASHBOARD_DIR/archives"
    echo "    ✓ Répertoire archives configuré"
    
    log_success "Permissions configurées"
    return 0
}

test_php_service() {
    log_info "Test du service PHP"
    
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
    if systemctl is-enabled php*-fpm >/dev/null 2>&1; then
        echo "    ✓ PHP-FPM configuré"
        log_success "PHP-FPM vérifié"
    else
        echo "    ⚠ PHP-FPM non activé"
        log_info "PHP-FPM non activé"
    fi
    
    echo "  ↦ Test HTTP des scripts..."
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo "    ✓ archives-list.php opérationnel (HTTP 200)"
        log_success "archives-list.php opérationnel"
    else
        echo "    ❌ archives-list.php erreur HTTP $http_code"
        log_error "archives-list.php erreur HTTP $http_code"
        return 1
    fi
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php?help" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo "    ✓ download-archive.php opérationnel (HTTP 200)"
        log_success "download-archive.php opérationnel"
    else
        echo "    ⚠ download-archive.php retourne HTTP $http_code"
        log_warning "download-archive.php comportement inattendu"
    fi
    
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-manager.js" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo "    ✓ download-manager.js accessible (HTTP 200)"
        log_success "download-manager.js accessible"
    else
        echo "    ⚠ download-manager.js retourne HTTP $http_code"
        log_warning "download-manager.js non accessible"
    fi
    
    return 0
}

log_info "========== DÉBUT DE L'INSTALLATION $SERVICE_NAME =========="

echo ""
echo "========================================================================"
echo "INSTALLATION $SERVICE_NAME (VERSION ULTRA-SIMPLIFIÉE)"
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

send_progress 40 "Installation de PHP..."

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
send_progress 55 "PHP installé"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 3 : INSTALLATION DES FICHIERS"
echo "========================================================================"
echo ""

send_progress 70 "Installation des fichiers..."

if ! install_php_files; then
    log_error "Échec de l'installation des fichiers"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 80 "Fichiers installés"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 4 : CONFIGURATION DES PERMISSIONS"
echo "========================================================================"
echo ""

send_progress 85 "Configuration des permissions..."

if ! configure_permissions; then
    log_error "Échec de la configuration des permissions"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 90 "Permissions configurées"
sleep 2

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : TESTS ET VALIDATION"
echo "========================================================================"
echo ""

send_progress 95 "Tests du service..."

if ! test_php_service; then
    log_error "Échec des tests du service PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE"
echo "========================================================================"
echo ""

update_service_status "$SERVICE_ID" "active"
echo "✅ $SERVICE_NAME installé avec succès"
echo ""

echo "🔗 URLs disponibles :"
echo "  • Liste des archives : http://localhost/archives-list.php"
echo "  • Téléchargement fichier : http://localhost/download-archive.php?file=S01_2025_machine.csv&year=2025"
echo "  • Liste semaine : http://localhost/download-archive.php?week=1&year=2025"
echo "  • Gestionnaire JavaScript : http://localhost/download-manager.js"

log_success "Installation $SERVICE_NAME terminée avec succès"
log_info "Script $SERVICE_ID terminé avec le code 0"

exit 0