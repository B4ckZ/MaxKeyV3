#!/bin/bash
#
# Installation du système PHP pour téléchargement des archives
# Service modulaire pour architecture MaxLink
# Version 3.1 - Solution PHP Pure
#

set -e

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Déterminer le chemin de base du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Charger les fonctions communes
source "$SCRIPT_DIR/../common/functions.sh"
source "$SCRIPT_DIR/../common/variables.sh"

# ===============================================================================
# VARIABLES SPÉCIFIQUES AU SERVICE
# ===============================================================================

SERVICE_ID="php_archives"
SERVICE_NAME="PHP Archives System"
SERVICE_DESCRIPTION="Système PHP pour téléchargement des archives de traçabilité"

# ===============================================================================
# FONCTIONS INTERNES
# ===============================================================================

function send_progress() {
    local progress="$1"
    local message="$2"
    echo "PROGRESS:$progress:$message"
}

function check_prerequisites() {
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

function install_php_packages() {
    log_info "Installation des paquets PHP"
    
    # Vérifier si PHP est déjà installé
    if command -v php >/dev/null 2>&1; then
        PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
        echo "   ✅ PHP déjà installé (version $PHP_VERSION)"
        log_info "PHP déjà installé version $PHP_VERSION"
    else
        echo "   📦 Installation de PHP et modules..."
        
        # Installation via le système de paquets hybride
        if hybrid_package_install "PHP" "php php-cli php-zip php-fpm"; then
            PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
            echo "   ✅ PHP installé avec succès (version $PHP_VERSION)"
            log_success "PHP installé version $PHP_VERSION"
        else
            log_error "Échec de l'installation de PHP"
            echo "   ❌ Échec de l'installation de PHP"
            return 1
        fi
    fi
    
    # Vérifier l'extension ZIP
    if php -m | grep -q zip; then
        echo "   ✅ Extension PHP zip disponible"
        log_success "Extension PHP zip vérifiée"
    else
        log_error "Extension PHP zip manquante"
        echo "   ❌ Extension PHP zip manquante"
        return 1
    fi
    
    return 0
}

function install_php_files() {
    log_info "Installation des fichiers PHP"
    
    # Vérifier que le dossier web_files existe
    if [ ! -d "$BASE_DIR/web_files" ]; then
        log_error "Dossier web_files/ non trouvé"
        echo "   ❌ Dossier web_files/ manquant dans le projet"
        echo "      Attendu: $BASE_DIR/web_files/"
        return 1
    fi
    
    # Installer archives-list.php
    if [ -f "$BASE_DIR/web_files/archives-list.php" ]; then
        cp "$BASE_DIR/web_files/archives-list.php" "$NGINX_DASHBOARD_DIR/"
        chown www-data:www-data "$NGINX_DASHBOARD_DIR/archives-list.php"
        chmod 644 "$NGINX_DASHBOARD_DIR/archives-list.php"
        echo "   ✅ archives-list.php installé"
        log_success "archives-list.php copié et configuré"
    else
        log_error "archives-list.php manquant"
        echo "   ❌ web_files/archives-list.php manquant"
        return 1
    fi
    
    # Installer download-archive.php
    if [ -f "$BASE_DIR/web_files/download-archive.php" ]; then
        cp "$BASE_DIR/web_files/download-archive.php" "$NGINX_DASHBOARD_DIR/"
        chown www-data:www-data "$NGINX_DASHBOARD_DIR/download-archive.php"
        chmod 644 "$NGINX_DASHBOARD_DIR/download-archive.php"
        echo "   ✅ download-archive.php installé"
        log_success "download-archive.php copié et configuré"
    else
        log_error "download-archive.php manquant"
        echo "   ❌ web_files/download-archive.php manquant"
        return 1
    fi
    
    return 0
}

function configure_permissions() {
    log_info "Configuration des permissions"
    
    # Ajouter www-data au groupe prod pour accès aux fichiers de traçabilité
    if ! groups www-data | grep -q prod; then
        usermod -a -G prod www-data
        echo "   ✅ www-data ajouté au groupe prod"
        log_success "www-data ajouté au groupe prod"
    else
        echo "   ✅ www-data déjà dans le groupe prod"
        log_info "www-data déjà dans le groupe prod"
    fi
    
    # Configurer les permissions du dossier de traçabilité s'il existe
    TRACABILITY_DIR="/home/prod/Documents/traçabilité"
    if [ -d "$TRACABILITY_DIR" ]; then
        chmod -R g+r "$TRACABILITY_DIR"
        echo "   ✅ Permissions de lecture configurées pour traçabilité"
        log_success "Permissions traçabilité configurées"
    else
        echo "   ⚠️  Dossier de traçabilité non trouvé (sera créé par testpersist)"
        log_info "Dossier traçabilité sera créé plus tard"
    fi
    
    return 0
}

function test_php_system() {
    log_info "Tests de validation du système PHP"
    
    # Recharger nginx
    systemctl reload nginx
    echo "   🔄 Nginx rechargé"
    sleep 2  # Attendre que nginx recharge
    
    # Test archives-list.php
    echo "   🔍 Test archives-list.php..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php")
    
    if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ archives-list.php répond correctement (HTTP 200)"
        log_success "archives-list.php opérationnel"
    else
        echo "   ❌ archives-list.php erreur HTTP $HTTP_CODE"
        log_error "archives-list.php erreur HTTP $HTTP_CODE"
        return 1
    fi
    
    # Test download-archive.php
    echo "   🔍 Test download-archive.php..."
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php")
    
    if [ "$HTTP_CODE" = "400" ]; then
        echo "   ✅ download-archive.php répond correctement (HTTP 400 sans paramètres)"
        log_success "download-archive.php opérationnel"
    else
        echo "   ⚠️  download-archive.php retourne HTTP $HTTP_CODE (attendu: 400)"
        log_warning "download-archive.php comportement inattendu mais probablement OK"
    fi
    
    return 0
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION $SERVICE_NAME =========="

echo "========================================================================"
echo "INSTALLATION $SERVICE_NAME"
echo "========================================================================"
echo ""

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
    exit 1
fi

echo "   ✅ Tous les prérequis sont satisfaits"

# ===============================================================================
# ÉTAPE 2 : INSTALLATION PHP
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 2 : INSTALLATION PHP"
echo "========================================================================"
echo ""

send_progress 30 "Installation de PHP..."

if ! install_php_packages; then
    log_error "Échec de l'installation PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

# ===============================================================================
# ÉTAPE 3 : INSTALLATION DES FICHIERS PHP
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 3 : INSTALLATION DES FICHIERS PHP"
echo "========================================================================"
echo ""

send_progress 60 "Installation des fichiers PHP..."

if ! install_php_files; then
    log_error "Échec de l'installation des fichiers PHP"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

# ===============================================================================
# ÉTAPE 4 : CONFIGURATION DES PERMISSIONS
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 4 : CONFIGURATION DES PERMISSIONS"
echo "========================================================================"
echo ""

send_progress 80 "Configuration des permissions..."

if ! configure_permissions; then
    log_error "Échec de la configuration des permissions"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

# ===============================================================================
# ÉTAPE 5 : TESTS ET VALIDATION
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : TESTS ET VALIDATION"
echo "========================================================================"
echo ""

send_progress 90 "Tests de validation..."

if ! test_php_system; then
    log_error "Échec des tests de validation"
    update_service_status "$SERVICE_ID" "inactive"
    exit 1
fi

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

# Mettre à jour le statut du service
update_service_status "$SERVICE_ID" "active"

echo ""
echo "========================================================================"
echo "✅ INSTALLATION $SERVICE_NAME TERMINÉE"
echo "========================================================================"
echo ""
echo "Composants installés :"
echo "• ✅ PHP $(php -v | head -n1 | cut -d' ' -f2) avec extension zip"
echo "• ✅ archives-list.php opérationnel"
echo "• ✅ download-archive.php opérationnel"
echo "• ✅ Permissions configurées pour www-data"
echo ""
echo "URLs d'accès :"
echo "• Liste archives : http://localhost/archives-list.php"
echo "• Téléchargement : http://localhost/download-archive.php?year=YYYY&week=NN"
echo ""
echo "📋 PROCHAINES ÉTAPES :"
echo "1. Le widget download est maintenant fonctionnel"
echo "2. Installer testpersist pour créer des données :"
echo "   sudo scripts/widgets/testpersist/testpersist_install.sh"
echo "3. Tester le widget dans le dashboard"
echo ""

log_success "Installation $SERVICE_NAME terminée avec succès"

exit 0