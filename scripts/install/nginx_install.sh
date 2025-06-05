#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION NGINX ET DASHBOARD (VERSION OFFLINE CORRIGÉE)
# Installation sans connexion internet - utilise uniquement le cache local
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
init_logging "Installation Nginx et Dashboard (Mode Offline)" "install"

# Variables du cache dashboard
DASHBOARD_CACHE_DIR="/var/cache/maxlink/dashboard"
DASHBOARD_ARCHIVE="$DASHBOARD_CACHE_DIR/dashboard.tar.gz"

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

# Vérifier le cache dashboard
check_dashboard_cache() {
    log_info "Vérification du cache dashboard"
    
    if [ ! -f "$DASHBOARD_ARCHIVE" ]; then
        echo "  ↦ Archive dashboard non trouvée dans le cache ✗"
        echo ""
        echo "ERREUR: Le dashboard doit être téléchargé avec update_install.sh"
        echo "Fichier manquant: $DASHBOARD_ARCHIVE"
        log_error "Archive dashboard manquante: $DASHBOARD_ARCHIVE"
        return 1
    fi
    
    # Vérifier l'intégrité de l'archive
    if ! tar -tzf "$DASHBOARD_ARCHIVE" >/dev/null 2>&1; then
        echo "  ↦ Archive dashboard corrompue ✗"
        echo ""
        echo "ERREUR: L'archive du dashboard est corrompue"
        echo "Relancez update_install.sh pour retélécharger"
        log_error "Archive dashboard corrompue: $DASHBOARD_ARCHIVE"
        return 1
    fi
    
    echo "  ↦ Dashboard trouvé dans le cache ✓"
    log_info "Dashboard valide trouvé dans le cache"
    return 0
}

# Installer Nginx depuis le cache
install_nginx_from_cache() {
    echo "◦ Installation de Nginx depuis le cache..."
    log_info "Installation de Nginx depuis le cache local"
    
    # Vérifier que le cache existe
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        echo "  ↦ Cache de paquets non trouvé ✗"
        echo ""
        echo "ERREUR: Le cache de paquets n'existe pas"
        echo "Exécutez d'abord update_install.sh"
        log_error "Cache de paquets manquant: $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    # Installer les paquets depuis le cache
    if install_packages_by_category "nginx"; then
        echo "  ↦ Nginx installé depuis le cache ✓"
        log_success "Nginx installé avec succès depuis le cache"
        return 0
    else
        echo "  ↦ Échec de l'installation de Nginx ✗"
        echo ""
        echo "ERREUR: Impossible d'installer Nginx depuis le cache"
        echo "Vérifiez que le cache contient tous les paquets nécessaires"
        log_error "Échec de l'installation de Nginx depuis le cache"
        return 1
    fi
}

# Fonction pour mettre à jour la configuration DNS si AP existe
update_dns_if_ap_exists() {
    log_info "Vérification de la configuration AP existante"
    
    if [ -f "/etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf" ]; then
        echo "◦ Mode AP détecté, mise à jour de la configuration DNS..."
        log_info "Mode AP détecté, mise à jour DNS nécessaire"
        
        if ! grep -q "address=/$NGINX_DASHBOARD_DOMAIN/" /etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf; then
            echo "" >> /etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf
            echo "# Dashboard MaxLink (ajouté par nginx_install.sh)" >> /etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf
            echo "address=/$NGINX_DASHBOARD_DOMAIN/$AP_IP" >> /etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf
            echo "  ↦ Entrée DNS ajoutée pour $NGINX_DASHBOARD_DOMAIN ✓"
            log_success "Entrée DNS ajoutée pour $NGINX_DASHBOARD_DOMAIN"
            
            if nmcli con show --active | grep -q "$AP_SSID"; then
                echo "  ↦ Redémarrage de NetworkManager pour appliquer les changements..."
                log_command "systemctl restart NetworkManager" "Redémarrage NetworkManager"
                wait_silently 3
                
                log_command "nmcli con up '$AP_SSID' >/dev/null 2>&1" "Réactivation mode AP"
                echo "  ↦ Mode AP réactivé avec la nouvelle configuration DNS ✓"
                log_info "Mode AP réactivé avec nouvelle configuration DNS"
            fi
        else
            echo "  ↦ Configuration DNS déjà présente ✓"
            log_info "Configuration DNS déjà présente"
        fi
    else
        echo "◦ Mode AP non installé - La résolution DNS sera configurée lors de l'installation de l'AP"
        log_info "Mode AP non installé - configuration DNS différée"
    fi
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION NGINX ET DASHBOARD (OFFLINE) =========="

echo "========================================================================"
echo "ÉTAPE 1 : VÉRIFICATIONS"
echo "========================================================================"
echo ""

send_progress 5 "Vérifications initiales..."

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "  ↦ Privilèges root requis ✗"
    log_error "Privilèges root requis - EUID: $EUID"
    exit 1
fi
log_info "Privilèges root confirmés"

echo "  ↦ Privilèges root confirmés ✓"
echo ""

# Vérifier le cache
echo "◦ Vérification du cache local..."
if ! check_dashboard_cache; then
    exit 1
fi

send_progress 10 "Vérifications terminées"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 2 : INSTALLATION DE NGINX
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 2 : INSTALLATION DE NGINX"
echo "========================================================================"
echo ""

send_progress 20 "Installation de Nginx..."

# Installer Nginx depuis le cache uniquement
if ! install_nginx_from_cache; then
    exit 1
fi

# Arrêter Nginx pour la configuration
echo ""
echo "◦ Préparation de Nginx..."
log_command "systemctl stop nginx >/dev/null 2>&1" "Arrêt Nginx"
echo "  ↦ Service Nginx arrêté ✓"

send_progress 35 "Nginx installé"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 3 : INSTALLATION DU DASHBOARD
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 3 : INSTALLATION DU DASHBOARD"
echo "========================================================================"
echo ""

send_progress 40 "Installation du dashboard..."

# Vérifier si le dashboard existe déjà
if [ -d "$NGINX_DASHBOARD_DIR" ]; then
    echo ""
    echo "◦ Dashboard existant détecté..."
    echo "  ↦ Sauvegarde de l'ancienne version..."
    log_info "Dashboard existant détecté - création sauvegarde"
    
    BACKUP_DIR="/var/www/maxlink-dashboard-backup-$(date +%Y%m%d_%H%M%S)"
    log_command "cp -r '$NGINX_DASHBOARD_DIR' '$BACKUP_DIR'" "Sauvegarde dashboard"
    echo "  ↦ Sauvegarde créée : $BACKUP_DIR ✓"
    log_info "Sauvegarde créée: $BACKUP_DIR"
    
    rm -rf "$NGINX_DASHBOARD_DIR"
fi

# Extraire le dashboard depuis le cache
echo ""
echo "◦ Extraction du dashboard depuis le cache..."
TEMP_DIR="/tmp/maxlink-dashboard-$(date +%s)"
mkdir -p "$TEMP_DIR"
log_info "Répertoire temporaire: $TEMP_DIR"

echo "  ↦ Extraction de l'archive..."
if log_command "tar -xzf '$DASHBOARD_ARCHIVE' -C '$TEMP_DIR'" "Extraction archive"; then
    echo "  ↦ Archive extraite ✓"
    log_success "Archive extraite avec succès"
    
    EXTRACTED_DIR=$(find "$TEMP_DIR" -maxdepth 1 -type d ! -path "$TEMP_DIR" | head -1)
    
    if [ -z "$EXTRACTED_DIR" ]; then
        echo "  ↦ Erreur: aucun dossier trouvé après extraction ✗"
        log_error "Aucun dossier trouvé dans l'archive"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    log_info "Dossier racine de l'archive: $EXTRACTED_DIR"
    
    # Si GITHUB_DASHBOARD_DIR est vide, utiliser la racine
    if [ -z "$GITHUB_DASHBOARD_DIR" ]; then
        DASHBOARD_PATH="$EXTRACTED_DIR"
    else
        DASHBOARD_PATH="$EXTRACTED_DIR/$GITHUB_DASHBOARD_DIR"
    fi
    
    log_info "Recherche du dashboard dans: $DASHBOARD_PATH"
    
    if [ -d "$DASHBOARD_PATH" ]; then
        echo "  ↦ Dossier dashboard trouvé ✓"
        log_info "Dossier dashboard trouvé: $DASHBOARD_PATH"
        
        # CORRECTION: Créer le répertoire destination avant la copie
        echo "  ↦ Création du répertoire destination..."
        mkdir -p "$(dirname "$NGINX_DASHBOARD_DIR")"
        mkdir -p "$NGINX_DASHBOARD_DIR"
        log_info "Répertoire destination créé: $NGINX_DASHBOARD_DIR"
        
        # Copier le contenu du dashboard
        log_command "cp -r '$DASHBOARD_PATH'/* '$NGINX_DASHBOARD_DIR'/" "Copie dashboard"
        echo "  ↦ Dashboard installé ✓"
        log_success "Dashboard installé avec succès"
    else
        echo "  ↦ Dossier dashboard non trouvé dans l'archive ✗"
        log_error "Dossier dashboard non trouvé dans l'archive"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
else
    echo "  ↦ Erreur lors de l'extraction ✗"
    log_error "Échec de l'extraction de l'archive"
    rm -rf "$TEMP_DIR"
    exit 1
fi

rm -rf "$TEMP_DIR"
log_info "Nettoyage du répertoire temporaire"

# Permissions basiques pour Nginx
echo ""
echo "◦ Configuration des permissions..."

groupadd -f www-data 2>/dev/null || true

log_command "chown -R www-data:www-data '$NGINX_DASHBOARD_DIR'" "Application propriétaire"
log_command "chmod -R 755 '$NGINX_DASHBOARD_DIR'" "Permissions standard"

echo "  ↦ Permissions configurées ✓"
log_info "Permissions appliquées au dashboard"

send_progress 60 "Dashboard installé"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 4 : CONFIGURATION NGINX
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 4 : CONFIGURATION DE NGINX"
echo "========================================================================"
echo ""

send_progress 70 "Configuration de Nginx..."

echo "◦ Création de la configuration du site..."
log_info "Création de la configuration Nginx"

# Créer la configuration Nginx
cat > /etc/nginx/sites-available/maxlink-dashboard << EOF
server {
    listen $NGINX_PORT default_server;
    server_name $NGINX_DASHBOARD_DOMAIN maxlink-dashboard.local maxlink.dashboard.local dashboard.local $AP_IP localhost _;
    
    root $NGINX_DASHBOARD_DIR;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location /widgets {
        alias $NGINX_DASHBOARD_DIR/widgets;
        autoindex on;
        autoindex_format json;
        autoindex_exact_size off;
        autoindex_localtime on;
    }
    
    location ~ ^/widgets/$ {
        root $NGINX_DASHBOARD_DIR;
        autoindex on;
        autoindex_format html;
    }
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml application/atom+xml image/svg+xml;
    
    location ~* \.(jpg|jpeg|png|gif|ico|svg|woff|woff2|ttf|otf)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
    
    location ~* \.(html|js|css)$ {
        expires -1;
        add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";
    }
    
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    access_log /var/log/nginx/maxlink-access.log;
    error_log /var/log/nginx/maxlink-error.log;
}
EOF

echo "  ↦ Configuration créée ✓"
log_success "Configuration Nginx créée"

# Activer le site
echo ""
echo "◦ Activation du site..."
log_command "rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true" "Suppression site par défaut"
log_command "rm -f /etc/nginx/sites-enabled/maxlink-dashboard 2>/dev/null || true" "Suppression ancien lien"
log_command "ln -s /etc/nginx/sites-available/maxlink-dashboard /etc/nginx/sites-enabled/" "Création lien symbolique"
echo "  ↦ Site activé ✓"
log_info "Site Nginx activé"

# Tester la configuration
if log_command "nginx -t >/dev/null 2>&1" "Test configuration Nginx"; then
    echo "  ↦ Configuration validée ✓"
    log_success "Configuration Nginx valide"
else
    echo "  ↦ Erreur de configuration ✗"
    log_error "Configuration Nginx invalide"
    nginx -t
    exit 1
fi

# Recharger systemd
systemctl daemon-reload

# Démarrer Nginx
echo ""
echo "◦ Démarrage de Nginx..."
log_command "systemctl enable nginx >/dev/null 2>&1" "Activation au démarrage"
log_command "systemctl start nginx >/dev/null 2>&1" "Démarrage Nginx"
echo "  ↦ Nginx démarré et activé ✓"
log_success "Nginx démarré avec succès"

send_progress 85 "Nginx configuré"
echo ""
sleep 2

# ===============================================================================
# ÉTAPE 5 : CONFIGURATION DNS
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 5 : CONFIGURATION DNS"
echo "========================================================================"
echo ""

send_progress 90 "Configuration DNS..."

# Mettre à jour le DNS si l'AP existe
update_dns_if_ap_exists

send_progress 100 "Installation terminée !"

echo ""
echo "◦ Installation terminée avec succès !"
echo "  ↦ Dashboard installé dans : $NGINX_DASHBOARD_DIR"
echo "  ↦ Accessible via :"
echo "    • http://$AP_IP"
if [ -f "/etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf" ] && grep -q "address=/$NGINX_DASHBOARD_DOMAIN/" /etc/NetworkManager/dnsmasq-shared.d/00-maxlink-ap.conf; then
    echo "    • http://$NGINX_DASHBOARD_DOMAIN"
    echo "    • http://maxlink-dashboard.local"
    echo "    • http://dashboard.local"
else
    echo "    • http://$NGINX_DASHBOARD_DOMAIN (nécessite l'installation de l'AP)"
fi
echo ""
echo "◦ IMPORTANT : L'orchestrateur doit être installé pour gérer le démarrage ordonné"
echo ""

log_info "Installation terminée avec succès"
log_info "Dashboard accessible à: http://$AP_IP et http://$NGINX_DASHBOARD_DOMAIN"

echo ""
echo "  ↦ Redémarrage du système prévu dans 15 secondes..."
echo ""

log_info "Redémarrage du système prévu dans 15 secondes"
sleep 15

log_info "Redémarrage du système"
reboot