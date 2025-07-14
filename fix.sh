#!/bin/bash

# ===============================================================================
# MAXLINK - CORRECTION CONFIGURATION NGINX/PHP
# Résout les problèmes détectés par le diagnostic
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

if [ "$EUID" -ne 0 ]; then
    print_error "Ce script doit être exécuté en tant que root"
    exit 1
fi

echo -e "${WHITE}========================================================================"
echo "🛠️  CORRECTION CONFIGURATION NGINX/PHP"
echo -e "========================================================================${NC}\n"

print_step "1. Vérification du problème PHP/nginx"

# Test si PHP est exécuté ou retourné en brut
PHP_TEST=$(curl -s "http://localhost/archives-list.php" 2>/dev/null | head -1)
if [[ "$PHP_TEST" == "<?php"* ]]; then
    print_error "PHP n'est pas exécuté par nginx (code PHP retourné en brut)"
    PHP_BROKEN=true
else
    print_success "PHP semble être exécuté correctement"
    PHP_BROKEN=false
fi

print_step "2. Vérification de la configuration nginx"

# Vérifier si nginx a la configuration PHP
NGINX_CONF="/etc/nginx/sites-available/default"
if [ -f "$NGINX_CONF" ]; then
    if grep -q "\.php" "$NGINX_CONF"; then
        print_success "Configuration PHP trouvée dans nginx"
    else
        print_error "Configuration PHP manquante dans nginx"
        NGINX_NEEDS_PHP=true
    fi
else
    print_error "Fichier de configuration nginx non trouvé"
    NGINX_NEEDS_PHP=true
fi

print_step "3. Vérification de PHP-FPM"

# Vérifier le service PHP-FPM
if systemctl is-active --quiet php*-fpm; then
    print_success "Service PHP-FPM actif"
    FPM_VERSION=$(systemctl list-units --type=service --state=active | grep php | grep fpm | awk '{print $1}' | head -1)
    echo "   Service: $FPM_VERSION"
else
    print_error "Service PHP-FPM inactif"
    FPM_BROKEN=true
fi

# Vérifier le socket PHP-FPM
FPM_SOCKET=$(find /run/php -name "php*-fpm.sock" 2>/dev/null | head -1)
if [ -n "$FPM_SOCKET" ]; then
    print_success "Socket PHP-FPM trouvé: $FPM_SOCKET"
else
    print_error "Socket PHP-FPM non trouvé"
    FPM_BROKEN=true
fi

print_step "4. Correction de la configuration nginx"

if [ "$NGINX_NEEDS_PHP" = true ] || [ "$PHP_BROKEN" = true ]; then
    print_warning "Mise à jour de la configuration nginx pour PHP..."
    
    # Backup de la configuration actuelle
    cp "$NGINX_CONF" "$NGINX_CONF.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Créer une configuration nginx avec support PHP
    cat > "$NGINX_CONF" << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/maxlink-dashboard;
    index index.html index.htm index.php;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    # Configuration PHP
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    # Sécurité - bloquer l'accès aux fichiers sensibles
    location ~ /\.ht {
        deny all;
    }
    
    # Logs
    access_log /var/log/nginx/maxlink_access.log;
    error_log /var/log/nginx/maxlink_error.log;
}
EOF
    
    print_success "Configuration nginx mise à jour"
else
    print_success "Configuration nginx OK"
fi

print_step "5. Correction du service PHP-FPM"

if [ "$FPM_BROKEN" = true ]; then
    print_warning "Redémarrage de PHP-FPM..."
    
    # Activer et démarrer PHP-FPM
    systemctl enable php8.2-fpm
    systemctl start php8.2-fpm
    
    # Vérifier que ça fonctionne
    sleep 2
    if systemctl is-active --quiet php8.2-fpm; then
        print_success "PHP-FPM redémarré avec succès"
    else
        print_error "Échec du redémarrage PHP-FPM"
        systemctl status php8.2-fpm
    fi
else
    print_success "PHP-FPM OK"
fi

print_step "6. Redémarrage de nginx"

systemctl restart nginx
sleep 2

if systemctl is-active --quiet nginx; then
    print_success "Nginx redémarré avec succès"
else
    print_error "Échec du redémarrage nginx"
    systemctl status nginx
    exit 1
fi

print_step "7. Correction des permissions des fichiers"

DASHBOARD_DIR="/var/www/maxlink-dashboard"
FILES_TO_FIX=(
    "$DASHBOARD_DIR/archives-list.php"
    "$DASHBOARD_DIR/download-archive.php"
    "$DASHBOARD_DIR/download-manager.js"
)

for file in "${FILES_TO_FIX[@]}"; do
    if [ -f "$file" ]; then
        chmod 644 "$file"
        chown www-data:www-data "$file"
        print_success "Permissions corrigées: $(basename "$file")"
    fi
done

print_step "8. Création d'archives de test (optionnel)"

ARCHIVES_DIR="/home/prod/Documents/traçabilité/Archives"
if [ -d "$ARCHIVES_DIR" ]; then
    CSV_COUNT=$(find "$ARCHIVES_DIR" -name "*.csv" 2>/dev/null | wc -l)
    if [ "$CSV_COUNT" -eq 0 ]; then
        print_warning "Aucun fichier CSV trouvé dans les archives"
        echo "Voulez-vous créer des fichiers de test ? (o/n)"
        read -r CREATE_TEST
        
        if [[ "$CREATE_TEST" =~ ^[Oo]$ ]]; then
            mkdir -p "$ARCHIVES_DIR/2025"
            
            # Créer quelques fichiers CSV de test
            for week in 01 02 03; do
                for machine in machine1 machine2; do
                    cat > "$ARCHIVES_DIR/2025/S${week}_2025_${machine}.csv" << EOF
timestamp,machine,value,status
2025-01-01 00:00:00,$machine,100,OK
2025-01-01 01:00:00,$machine,105,OK
2025-01-01 02:00:00,$machine,98,OK
EOF
                done
            done
            
            chown -R www-data:www-data "$ARCHIVES_DIR"
            print_success "Fichiers CSV de test créés"
        fi
    else
        print_success "Archives contiennent $CSV_COUNT fichiers CSV"
    fi
fi

print_step "9. Test de la correction"

echo "Test des APIs après correction..."

# Test archives-list.php
ARCHIVES_RESPONSE=$(curl -s "http://localhost/archives-list.php" 2>/dev/null)
if echo "$ARCHIVES_RESPONSE" | python3 -m json.tool >/dev/null 2>&1; then
    print_success "archives-list.php retourne du JSON valide"
else
    print_error "archives-list.php ne retourne pas de JSON valide"
    echo "Réponse: ${ARCHIVES_RESPONSE:0:200}..."
fi

# Test download-archive.php
DOWNLOAD_RESPONSE=$(curl -s "http://localhost/download-archive.php?help" 2>/dev/null)
if echo "$DOWNLOAD_RESPONSE" | python3 -m json.tool >/dev/null 2>&1; then
    print_success "download-archive.php retourne du JSON valide"
else
    print_error "download-archive.php ne retourne pas de JSON valide"
fi

# Test download-manager.js
JS_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-manager.js" 2>/dev/null)
if [ "$JS_RESPONSE" = "200" ]; then
    print_success "download-manager.js accessible"
else
    print_warning "download-manager.js retourne HTTP $JS_RESPONSE"
fi

print_step "10. Vérification finale"

echo -e "\n${WHITE}🧪 Test rapide des URLs principales:${NC}"
echo "• Archives List: http://localhost/archives-list.php"
echo "• Download Help: http://localhost/download-archive.php?help"
echo "• JS Manager: http://localhost/download-manager.js"

echo -e "\n${GREEN}✨ Correction terminée !${NC}"
echo -e "${WHITE}Relancez le diagnostic pour vérifier les améliorations:${NC}"
echo "sudo ./test_php_archives_system.sh"

echo -e "\n${BLUE}📝 Résumé des corrections:${NC}"
echo "• Configuration nginx mise à jour pour PHP"
echo "• Service PHP-FPM redémarré"
echo "• Permissions des fichiers corrigées (644)"
echo "• Tests de fonctionnement effectués"

exit 0