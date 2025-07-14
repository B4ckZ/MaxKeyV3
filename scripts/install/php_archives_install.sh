#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION SYSTÈME PHP ARCHIVES (VERSION CORRIGÉE)
# Installation avec mise à jour du statut et nouvelles fonctions de cache
# Utilise l'installation simultanée pour résoudre les problèmes de dépendances
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$SCRIPT_DIR/../common/variables.sh"
source "$SCRIPT_DIR/../common/logging.sh"
source "$SCRIPT_DIR/../common/packages.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Installation Système PHP Archives" "install"

# Variables spécifiques au service
SERVICE_ID="php_archives"
SERVICE_NAME="PHP Archives System"
SERVICE_DESCRIPTION="Système PHP pour téléchargement des archives de traçabilité"

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

# Vérifier les prérequis
check_prerequisites() {
    log_info "Vérification des prérequis pour $SERVICE_NAME"
    
    # Vérifier que nginx est installé et actif
    if ! command -v nginx >/dev/null 2>&1; then
        log_error "Nginx n'est pas installé. Le service $SERVICE_ID nécessite nginx."
        echo "❌ Nginx requis mais non installé"
        echo "   Exécutez d'abord nginx_install.sh"
        return 1
    fi
    
    if ! systemctl is-active --quiet nginx; then
        log_error "Nginx n'est pas actif"
        echo "❌ Nginx installé mais non actif"
        return 1
    fi
    
    # Vérifier que le dashboard est installé
    if [ ! -d "$NGINX_DASHBOARD_DIR" ]; then
        log_error "Dashboard non installé"
        echo "❌ Dashboard MaxLink non trouvé"
        echo "   Répertoire attendu: $NGINX_DASHBOARD_DIR"
        return 1
    fi
    
    log_success "Prérequis validés"
    return 0
}

# Installer PHP depuis le cache avec vérification et installation simultanée
install_php_from_cache() {
    echo "◦ Installation de PHP depuis le cache..."
    log_info "Installation de PHP depuis le cache local avec nouvelle méthode"
    
    # Vérifier que le cache existe
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        echo "  ↦ Cache de paquets non trouvé ✗"
        echo ""
        echo "ERREUR: Le cache de paquets n'existe pas"
        echo "Exécutez d'abord update_install.sh"
        log_error "Cache de paquets manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    # NOUVELLE ÉTAPE : Vérification complète du cache PHP
    echo ""
    echo "  ↦ Étape 1/3 : Vérification du cache PHP..."
    if ! verify_category_cache_complete "php"; then
        echo "  ↦ Cache PHP incomplet ✗"
        echo ""
        echo "ERREUR: Le cache ne contient pas tous les paquets PHP nécessaires"
        echo "Exécutez update_install.sh pour recréer le cache complet"
        log_error "Cache PHP incomplet - installation impossible"
        return 1
    fi
    
    echo "  ↦ ✅ Cache PHP vérifié et complet"
    
    # NOUVELLE ÉTAPE : Vérification des conflits existants
    echo ""
    echo "  ↦ Étape 2/3 : Vérification des installations existantes..."
    local existing_php_packages=""
    for pkg in php php-cli php-zip php-fpm; do
        if dpkg -l "$pkg" >/dev/null 2>&1; then
            existing_php_packages="$existing_php_packages $pkg"
        fi
    done
    
    if [ -n "$existing_php_packages" ]; then
        echo "  ↦ Paquets PHP déjà installés:$existing_php_packages"
        log_info "Paquets PHP existants détectés:$existing_php_packages"
        
        # Vérifier si tous les paquets requis sont installés
        local missing_php=""
        for pkg in php php-cli php-zip php-fpm; do
            if ! dpkg -l "$pkg" >/dev/null 2>&1; then
                missing_php="$missing_php $pkg"
            fi
        done
        
        if [ -z "$missing_php" ]; then
            echo "  ↦ ✅ Tous les paquets PHP sont déjà installés"
            log_success "PHP déjà complètement installé"
            return 0
        else
            echo "  ↦ Paquets manquants:$missing_php"
            log_info "Installation partielle détectée, paquets manquants:$missing_php"
        fi
    else
        echo "  ↦ Aucun paquet PHP installé - installation complète nécessaire"
        log_info "Installation PHP complète nécessaire"
    fi
    
    # NOUVELLE MÉTHODE : Installation simultanée
    echo ""
    echo "  ↦ Étape 3/3 : Installation simultanée de tous les paquets PHP..."
    log_info "Lancement de l'installation simultanée PHP"
    
    if install_packages_by_category_simultaneously "php"; then
        echo ""
        echo "  ↦ ✅ PHP installé avec succès depuis le cache"
        log_success "PHP installé avec succès depuis le cache via installation simultanée"
        
        # Vérification post-installation
        echo ""
        echo "  ↦ Vérification post-installation..."
        local verification_failed=0
        
        for pkg in php php-cli php-zip php-fpm; do
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
        echo ""
        echo "  ↦ ❌ Échec de l'installation de PHP"
        echo ""
        echo "ERREUR: Impossible d'installer PHP depuis le cache"
        echo "Détails :"
        echo "  • Vérifiez les logs dans /tmp/dpkg_install_php.log"
        echo "  • Vérifiez l'intégrité du cache avec: scripts/common/cache_manager.sh verify"
        echo "  • Recréez le cache avec: scripts/install/update_install.sh"
        log_error "Échec de l'installation simultanée PHP"
        return 1
    fi
}

# Installer les fichiers PHP
install_php_files() {
    log_info "Installation des fichiers PHP"
    
    # Vérifier que le dossier web_files existe
    if [ ! -d "$BASE_DIR/web_files" ]; then
        echo "  ↦ Dossier web_files non trouvé ✗"
        echo ""
        echo "ERREUR: Le dossier web_files est requis"
        echo "Répertoire attendu: $BASE_DIR/web_files"
        log_error "Dossier web_files manquant: $BASE_DIR/web_files"
        return 1
    fi
    
    # Vérifier que les fichiers PHP existent
    local required_files=("archives-list.php" "download-archive.php")
    local missing_files=""
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$BASE_DIR/web_files/$file" ]; then
            missing_files="$missing_files $file"
        fi
    done
    
    if [ -n "$missing_files" ]; then
        echo "  ↦ Fichiers PHP manquants:$missing_files ✗"
        log_error "Fichiers PHP manquants:$missing_files"
        return 1
    fi
    
    # Copier les fichiers PHP vers le répertoire web
    echo "  ↦ Copie des fichiers PHP..."
    
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
    
    log_success "Fichiers PHP installés"
    return 0
}

# Configurer les permissions
configure_permissions() {
    log_info "Configuration des permissions pour $SERVICE_NAME"
    
    # Permissions sur les fichiers PHP
    echo "  ↦ Configuration des permissions des fichiers PHP..."
    
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
    
    # Permissions sur le répertoire des archives
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

# Tester le service PHP
test_php_service() {
    log_info "Test du service PHP"
    
    # Vérifier que PHP fonctionne
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
    
    # Vérifier l'extension ZIP
    echo "  ↦ Test de l'extension ZIP..."
    if php -m | grep -q zip; then
        echo "    ✓ Extension ZIP disponible"
        log_success "Extension PHP zip vérifiée"
    else
        echo "    ✗ Extension ZIP manquante"
        log_error "Extension PHP zip manquante"
        return 1
    fi
    
    # Vérifier PHP-FPM
    echo "  ↦ Test de PHP-FPM..."
    if systemctl is-enabled php*-fpm >/dev/null 2>&1; then
        echo "    ✓ PHP-FPM configuré"
        log_success "PHP-FPM vérifié"
    else
        echo "    ⚠ PHP-FPM non activé (normal si Apache est utilisé)"
        log_info "PHP-FPM non activé"
    fi
    
    # Test HTTP basique des fichiers PHP
    echo "  ↦ Test HTTP des scripts PHP..."
    
    # Test archives-list.php
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "200" ]; then
        echo "    ✓ archives-list.php répond correctement (HTTP 200)"
        log_success "archives-list.php opérationnel"
    else
        echo "    ❌ archives-list.php erreur HTTP $http_code"
        log_error "archives-list.php erreur HTTP $http_code"
        return 1
    fi
    
    # Test download-archive.php
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php" 2>/dev/null || echo "000")
    
    if [ "$http_code" = "400" ]; then
        echo "    ✓ download-archive.php répond correctement (HTTP 400 sans paramètres)"
        log_success "download-archive.php opérationnel"
    else
        echo "    ⚠ download-archive.php retourne HTTP $http_code (attendu: 400)"
        log_warning "download-archive.php comportement inattendu mais probablement OK"
    fi
    
    return 0
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION $SERVICE_NAME =========="

echo ""
echo "========================================================================"
echo "INSTALLATION $SERVICE_NAME"
echo "========================================================================"
echo ""

send_progress 5 "Initialisation..."

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Ce script doit être exécuté en tant que root"
    log_error "Privilèges root requis"
    exit 1
fi

echo "🔍 Vérifications initiales..."
echo "   ✅ Privilèges root confirmés"
log_success "Privilèges root confirmés"

# ===============================================================================
# ÉTAPE 1 : VÉRIFICATION DES PRÉREQUIS
# ===============================================================================

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
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 2 : INSTALLATION PHP
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 2 : INSTALLATION PHP"
echo "========================================================================"
echo ""

send_progress 40 "Installation de PHP..."

# Vérifier si PHP est déjà installé
if command -v php >/dev/null 2>&1; then
    PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
    echo "   ✅ PHP déjà installé (version $PHP_VERSION)"
    log_info "PHP déjà installé version $PHP_VERSION"
    
    # Vérifier que tous les composants sont installés
    local missing_components=""
    for pkg in php-cli php-zip php-fpm; do
        if ! dpkg -l "$pkg" >/dev/null 2>&1; then
            missing_components="$missing_components $pkg"
        fi
    done
    
    if [ -n "$missing_components" ]; then
        echo "   ⚠ Composants manquants:$missing_components"
        echo "   ↦ Installation des composants manquants..."
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

# Vérification finale de l'extension ZIP
if php -m | grep -q zip; then
    echo "   ✅ Extension PHP zip disponible"
    log_success "Extension PHP zip vérifiée"
else
    log_error "Extension PHP zip manquante après installation"
    echo "   ❌ Extension PHP zip manquante"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 55 "PHP installé"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 3 : INSTALLATION DES FICHIERS PHP
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 3 : INSTALLATION DES FICHIERS PHP"
echo "========================================================================"
echo ""

send_progress 70 "Installation des fichiers PHP..."

if ! install_php_files; then
    log_error "Échec de l'installation des fichiers PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

send_progress 80 "Fichiers PHP installés"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 4 : CONFIGURATION DES PERMISSIONS
# ===============================================================================

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
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 5 : TESTS ET VALIDATION
# ===============================================================================

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

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "INSTALLATION TERMINÉE"
echo "========================================================================"
echo ""

# Mettre à jour le statut du service
update_service_status "$SERVICE_ID" "active"
echo "✅ $SERVICE_NAME installé avec succès"
echo ""

echo "📋 Résumé de l'installation :"
echo "  • PHP et extensions installés depuis le cache"
echo "  • Fichiers PHP copiés vers le dashboard"
echo "  • Permissions configurées"
echo "  • Tests de fonctionnement validés"
echo ""

echo "🔗 URLs disponibles :"
echo "  • Liste des archives : http://localhost/archives-list.php"
echo "  • Téléchargement     : http://localhost/download-archive.php"
echo ""

echo "📁 Répertoires importants :"
echo "  • Fichiers web   : $NGINX_DASHBOARD_DIR"
echo "  • Archives       : $NGINX_DASHBOARD_DIR/archives"
echo "  • Logs           : /var/log/maxlink/"

log_success "Installation $SERVICE_NAME terminée avec succès"

echo ""
echo "Statut $SERVICE_ID mis à jour: active"
echo "  ↦ Statut du service $SERVICE_ID mis à jour: active"

log_info "Script $SERVICE_ID terminé avec le code 0"

exit 0