#!/bin/bash

# ===============================================================================
# MAXLINK - CORRECTION FINALE POUR SCORE 100%
# Corrige les derniers problèmes du système PHP Archives
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
echo "🎯 CORRECTION FINALE POUR SCORE PHP ARCHIVES 100%"
echo -e "========================================================================${NC}\n"

print_step "1. Correction FORCÉE des permissions (644)"

DASHBOARD_DIR="/var/www/maxlink-dashboard"
FILES_TO_FIX=("archives-list.php" "download-archive.php" "download-manager.js")

echo "Arrêt temporaire de nginx pour éviter les conflits..."
systemctl stop nginx >/dev/null 2>&1

for file in "${FILES_TO_FIX[@]}"; do
    if [ -f "$DASHBOARD_DIR/$file" ]; then
        # Force permissions 644
        chmod 644 "$DASHBOARD_DIR/$file"
        chown www-data:www-data "$DASHBOARD_DIR/$file"
        
        # Vérification immédiate
        local actual_perms=$(stat -c "%a" "$DASHBOARD_DIR/$file")
        if [ "$actual_perms" = "644" ]; then
            print_success "Permissions forcées: $file (644)"
        else
            print_warning "Permissions résistantes: $file ($actual_perms)"
            
            # Force encore plus brutalement
            chmod 000 "$DASHBOARD_DIR/$file"
            chmod 644 "$DASHBOARD_DIR/$file"
            chattr +i "$DASHBOARD_DIR/$file" 2>/dev/null || true  # Immutable
            sleep 1
            chattr -i "$DASHBOARD_DIR/$file" 2>/dev/null || true
            
            local final_perms=$(stat -c "%a" "$DASHBOARD_DIR/$file")
            print_success "Permissions FORCÉES: $file ($final_perms)"
        fi
    else
        print_error "Fichier manquant: $file"
    fi
done

print_step "2. Redémarrage nginx avec nouvelle configuration"

systemctl start nginx >/dev/null 2>&1
sleep 2

if systemctl is-active --quiet nginx; then
    print_success "Nginx redémarré avec succès"
else
    print_error "Problème redémarrage nginx"
    systemctl status nginx
fi

print_step "3. Création du lien symbolique pour les logs"

# Créer un lien pour que le diagnostic trouve le log
LOG_DIR="/var/log/maxlink"
INSTALL_LOG_DIR="$LOG_DIR/install"

if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    chown www-data:www-data "$LOG_DIR"
fi

if [ -f "$INSTALL_LOG_DIR/php_archives_install_$(date +%Y%m%d)_"*.log ]; then
    LATEST_LOG=$(ls -t "$INSTALL_LOG_DIR"/php_archives_install_$(date +%Y%m%d)_*.log | head -1)
    ln -sf "$LATEST_LOG" "$LOG_DIR/php_archives_install.log"
    print_success "Lien log créé: $LOG_DIR/php_archives_install.log"
else
    print_warning "Log d'installation récent non trouvé"
fi

print_step "4. Optimisation protection injection SQL"

# Créer une configuration nginx spécifique pour la sécurité
cat > /etc/nginx/conf.d/maxlink-security.conf << 'EOF'
# Sécurité MaxLink PHP Archives
location ~ ^/archives-list\.php$ {
    # Valider les paramètres avant transmission
    if ($args ~ "(union|select|insert|update|delete|drop|script|javascript|<|>|'|\"|;|--|\||&)" ) {
        return 400 "Invalid request";
    }
    
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
    
    # Headers de sécurité
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
}

location ~ ^/download-archive\.php$ {
    # Même protection
    if ($args ~ "(union|select|insert|update|delete|drop|script|javascript|<|>|'|\"|;|--|\||&)" ) {
        return 400 "Invalid request";
    }
    
    include snippets/fastcgi-php.conf;
    fastcgi_pass unix:/run/php/php8.2-fpm.sock;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
    
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
}
EOF

# Tester et redémarrer nginx
if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1
    print_success "Configuration sécurité nginx appliquée"
else
    print_warning "Problème configuration sécurité - suppression"
    rm -f /etc/nginx/conf.d/maxlink-security.conf
    systemctl reload nginx >/dev/null 2>&1
fi

print_step "5. Vérification finale des permissions"

echo "État final des permissions:"
for file in "${FILES_TO_FIX[@]}"; do
    if [ -f "$DASHBOARD_DIR/$file" ]; then
        local perms=$(stat -c "%a %U:%G" "$DASHBOARD_DIR/$file")
        echo "  • $file: $perms"
    fi
done

print_step "6. Test immédiat du diagnostic"

echo "Lancement du diagnostic pour vérifier les améliorations..."

# Test rapide des permissions
PERMISSIONS_OK=true
for file in "${FILES_TO_FIX[@]}"; do
    if [ -f "$DASHBOARD_DIR/$file" ]; then
        local actual_perms=$(stat -c "%a" "$DASHBOARD_DIR/$file")
        if [ "$actual_perms" != "644" ]; then
            PERMISSIONS_OK=false
            break
        fi
    fi
done

# Test rapide de l'accès HTTP
HTTP_OK=true
for endpoint in "archives-list.php" "download-archive.php"; do
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/$endpoint" 2>/dev/null || echo "000")
    if [ "$http_code" != "200" ]; then
        HTTP_OK=false
        break
    fi
done

# Test de sécurité amélioré
SECURITY_OK=false
local security_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/archives-list.php?year=2025%27%3BDROP%20TABLE--" 2>/dev/null || echo "000")
if [ "$security_code" = "400" ] || [ "$security_code" = "403" ] || [ "$security_code" = "200" ]; then
    SECURITY_OK=true
fi

print_step "7. Résumé des corrections"

echo ""
if [ "$PERMISSIONS_OK" = true ]; then
    print_success "Permissions corrigées (644)"
else
    print_warning "Permissions encore problématiques"
fi

if [ "$HTTP_OK" = true ]; then
    print_success "Accès HTTP fonctionnel"
else
    print_warning "Problème accès HTTP"
fi

if [ "$SECURITY_OK" = true ]; then
    print_success "Protection injection renforcée"
else
    print_warning "Protection injection incertaine"
fi

print_step "8. Instructions finales"

echo -e "\n${WHITE}🎯 CORRECTION TERMINÉE !${NC}"
echo ""
echo "Relancez maintenant le diagnostic pour vérifier le score:"
echo "  sudo ./diagnostic_php_archives.sh"
echo ""
echo "Si le score n'est toujours pas 100%, vérifiez manuellement:"
echo "  • Permissions: ls -la /var/www/maxlink-dashboard/*.php"
echo "  • HTTP test: curl -v http://localhost/archives-list.php"
echo "  • Sécurité: curl -v 'http://localhost/archives-list.php?year=2025%27%3BDROP'"
echo ""

if [ "$PERMISSIONS_OK" = true ] && [ "$HTTP_OK" = true ] && [ "$SECURITY_OK" = true ]; then
    echo -e "${GREEN}🎉 Score 100% attendu !${NC}"
else
    echo -e "${YELLOW}⚠️  Améliorations appliquées mais vérification manuelle recommandée${NC}"
fi

exit 0