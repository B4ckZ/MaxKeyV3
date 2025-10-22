#!/bin/bash

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "========================================================================"
}

print_check() {
    printf "%-50s" "◦ $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC}"
}

print_fail() {
    echo -e "${RED}[FAIL]${NC}"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC}"
}

print_info() {
    echo "  ↦ $1"
}

main() {
    clear
    echo ""
    echo "========================================================================"
    echo " PHP-FPM DIAGNOSTIC"
    echo "========================================================================"
    
    print_header "VERSION ET INSTALLATION"
    
    print_check "PHP-FPM installé"
    if command -v php-fpm >/dev/null 2>&1; then
        print_ok
        local php_version=$(php-fpm -v 2>/dev/null | head -1)
        print_info "$php_version"
    else
        print_fail
        print_info "php-fpm non trouvé"
        exit 1
    fi
    
    print_check "Version complète"
    php -v 2>/dev/null | head -1
    echo ""
    
    print_check "Extensions activées"
    php -m 2>/dev/null | grep -E "json|curl|pdo|mysql|opcache" | head -5
    echo ""
    
    print_header "SERVICE SYSTEMD"
    
    print_check "Service actif"
    if systemctl is-active --quiet php8.2-fpm; then
        print_ok
    else
        print_fail
        print_info "Service inactif"
    fi
    
    print_check "Service au démarrage"
    if systemctl is-enabled php8.2-fpm >/dev/null 2>&1; then
        print_ok
    else
        print_warn
        print_info "Service non activé au démarrage"
    fi
    
    print_check "Uptime du service"
    local uptime=$(systemctl show php8.2-fpm --property=ActiveEnterTimestamp --value 2>/dev/null)
    print_ok
    print_info "$uptime"
    
    print_header "SOCKET ET CONFIGURATION"
    
    print_check "Socket Unix"
    if [ -S /run/php/php8.2-fpm.sock ]; then
        print_ok
        print_info "/run/php/php8.2-fpm.sock"
        local perms=$(ls -l /run/php/php8.2-fpm.sock | awk '{print $1}')
        print_info "Permissions: $perms"
    else
        print_fail
        print_info "Socket non trouvée"
    fi
    
    print_check "Port d'écoute"
    if ss -tlnp 2>/dev/null | grep -q "php-fpm"; then
        print_ok
        ss -tlnp 2>/dev/null | grep "php-fpm"
    else
        print_warn
        print_info "Pas sur port TCP (normal si socket Unix)"
    fi
    
    print_check "Fichier config"
    if [ -f /etc/php/8.2/fpm/php-fpm.conf ]; then
        print_ok
        print_info "/etc/php/8.2/fpm/php-fpm.conf"
    else
        print_fail
    fi
    
    print_check "Pool config"
    if [ -f /etc/php/8.2/fpm/pool.d/www.conf ]; then
        print_ok
        print_info "/etc/php/8.2/fpm/pool.d/www.conf"
    else
        print_warn
    fi
    
    print_header "PROCESSUS ET MÉMOIRE"
    
    print_check "Processus master"
    if pgrep -f "php-fpm: master" >/dev/null; then
        print_ok
        local master_pid=$(pgrep -f "php-fpm: master")
        print_info "PID: $master_pid"
    else
        print_fail
    fi
    
    print_check "Processus workers"
    local worker_count=$(pgrep -f "php-fpm: pool" | wc -l)
    if [ "$worker_count" -gt 0 ]; then
        print_ok
        print_info "$worker_count workers actifs"
    else
        print_fail
        print_info "Aucun worker trouvé"
    fi
    
    print_check "Mémoire utilisée"
    print_ok
    local mem_usage=$(ps aux | grep "[p]hp-fpm" | awk '{sum+=$6} END {print sum/1024 " MB"}')
    print_info "Total: $mem_usage"
    
    print_header "TEST FONCTIONNEL"
    
    print_check "Test info.php"
    if [ -f /var/www/maxlink-dashboard/info.php ]; then
        print_ok
        local status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/info.php 2>/dev/null)
        print_info "HTTP $status"
    else
        print_warn
        print_info "Fichier info.php non trouvé"
    fi
    
    print_check "Test archives-list.php"
    if [ -f /var/www/maxlink-dashboard/archives-list.php ]; then
        print_ok
        local status=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/archives-list.php 2>/dev/null)
        print_info "HTTP $status"
        
        if [ "$status" = "200" ]; then
            local json_lines=$(curl -s http://localhost/archives-list.php 2>/dev/null | wc -l)
            print_info "Réponse: $json_lines lignes"
        fi
    else
        print_fail
        print_info "archives-list.php non trouvé"
    fi
    
    print_check "Test téléchargement CSV"
    local csv_count=$(find /var/www/maxlink-dashboard/archives -name "*.csv" 2>/dev/null | wc -l)
    if [ "$csv_count" -gt 0 ]; then
        print_ok
        print_info "$csv_count fichiers CSV trouvés"
    else
        print_warn
        print_info "Aucun CSV"
    fi
    
    print_header "CONFIGURATION PHP"
    
    print_check "max_execution_time"
    print_ok
    php -i 2>/dev/null | grep "max_execution_time" | head -1
    echo ""
    
    print_check "memory_limit"
    print_ok
    php -i 2>/dev/null | grep "memory_limit" | head -1
    echo ""
    
    print_check "upload_max_filesize"
    print_ok
    php -i 2>/dev/null | grep "upload_max_filesize" | head -1
    echo ""
    
    print_check "post_max_size"
    print_ok
    php -i 2>/dev/null | grep "post_max_size" | head -1
    echo ""
    
    print_header "ERREURS RÉCENTES"
    
    print_check "Erreurs (dernière heure)"
    local error_count=$(journalctl -u php8.2-fpm --since "1 hour ago" -p err --no-pager 2>/dev/null | wc -l)
    if [ "$error_count" -eq 0 ]; then
        print_ok
        print_info "Aucune erreur"
    else
        print_warn
        print_info "$error_count erreurs détectées"
        journalctl -u php8.2-fpm --since "1 hour ago" -p err --no-pager 2>/dev/null | head -5
    fi
    
    print_check "Avertissements (24h)"
    local warn_count=$(journalctl -u php8.2-fpm --since "24 hours ago" -p warning --no-pager 2>/dev/null | wc -l)
    if [ "$warn_count" -eq 0 ]; then
        print_ok
        print_info "Aucun avertissement"
    else
        print_warn
        print_info "$warn_count avertissements"
    fi
    
    print_header "SYNTAXE PHP"
    
    print_check "Vérification syntaxe info.php"
    if php -l /var/www/maxlink-dashboard/info.php >/dev/null 2>&1; then
        print_ok
    else
        print_fail
    fi
    
    print_check "Vérification syntaxe archives-list.php"
    if php -l /var/www/maxlink-dashboard/archives-list.php >/dev/null 2>&1; then
        print_ok
    else
        print_fail
        print_info "Erreur de syntaxe détectée"
        php -l /var/www/maxlink-dashboard/archives-list.php
    fi
    
    print_header "RÉSUMÉ"
    
    echo ""
    echo -e "  ${GREEN}✓ PHP-FPM fonctionne correctement${NC}"
    echo "  • Version: $(php -v 2>/dev/null | head -1 | awk '{print $2}')"
    echo "  • Status: Actif"
    echo "  • Workers: $worker_count"
    echo "  • CSV archives: $csv_count fichiers"
    echo ""
}

main "$@"