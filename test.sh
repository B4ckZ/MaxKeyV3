#!/bin/bash

# ===============================================================================
# MAXLINK - DIAGNOSTIC COMPLET SYSTÈME PHP ARCHIVES
# Vérifie que tout fonctionne correctement après installation
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables de comptage
TOTAL_TESTS=0
PASSED_TESTS=0
WARNED_TESTS=0
FAILED_TESTS=0

print_header() {
    echo -e "\n${WHITE}========== $1 ==========${NC}"
}

print_section() {
    echo -e "\n${CYAN}🔍 $1${NC}"
    echo "----------------------------------------"
}

print_test() {
    echo -e "${BLUE}Test $1...${NC}"
    ((TOTAL_TESTS++))
}

print_result() {
    local status="$1"
    local message="$2"
    local detail="$3"
    
    case "$status" in
        "PASS") 
            echo -e "   ${GREEN}✅ PASS${NC} - $message"
            [ -n "$detail" ] && echo -e "   ${GREEN}ℹ️  $detail${NC}"
            ((PASSED_TESTS++))
            ;;
        "FAIL") 
            echo -e "   ${RED}❌ FAIL${NC} - $message"
            [ -n "$detail" ] && echo -e "   ${RED}💀 $detail${NC}"
            ((FAILED_TESTS++))
            ;;
        "WARN") 
            echo -e "   ${YELLOW}⚠️  WARN${NC} - $message"
            [ -n "$detail" ] && echo -e "   ${YELLOW}⚠️  $detail${NC}"
            ((WARNED_TESTS++))
            ;;
        "INFO")
            echo -e "   ${CYAN}ℹ️  INFO${NC} - $message"
            [ -n "$detail" ] && echo -e "   ${CYAN}📝 $detail${NC}"
            ;;
    esac
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_result "FAIL" "Ce script doit être exécuté en tant que root"
        exit 1
    fi
}

check_service_status() {
    print_section "1. VÉRIFICATION DES SERVICES"
    
    # Vérifier le statut du service php_archives
    print_test "statut service php_archives"
    if [ -f "/var/lib/maxlink/services_status.json" ]; then
        local status=$(python3 -c "
import json
try:
    with open('/var/lib/maxlink/services_status.json', 'r') as f:
        data = json.load(f)
        print(data.get('php_archives', {}).get('status', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)
        
        if [ "$status" = "active" ]; then
            print_result "PASS" "Service php_archives actif" "Statut: $status"
        else
            print_result "FAIL" "Service php_archives non actif" "Statut: $status"
        fi
    else
        print_result "WARN" "Fichier de statut services non trouvé"
    fi
    
    # Vérifier Nginx
    print_test "service Nginx"
    if systemctl is-active --quiet nginx; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3 | cut -d'/' -f2)
        print_result "PASS" "Nginx actif" "Version: $nginx_version"
    else
        print_result "FAIL" "Nginx inactif"
    fi
    
    # Vérifier PHP-FPM
    print_test "service PHP-FPM"
    if systemctl is-active --quiet php8.2-fpm; then
        local fpm_status=$(systemctl show php8.2-fpm --property=ActiveState --value)
        print_result "PASS" "PHP-FPM actif" "État: $fmp_status"
    else
        print_result "FAIL" "PHP-FPM inactif"
    fi
    
    # Vérifier PHP CLI
    print_test "PHP CLI"
    if command -v php >/dev/null 2>&1; then
        local php_version=$(php -v | head -n1 | cut -d' ' -f2)
        print_result "PASS" "PHP CLI installé" "Version: $php_version"
    else
        print_result "FAIL" "PHP CLI non installé"
    fi
    
    # Vérifier socket PHP-FPM
    print_test "socket PHP-FPM"
    if [ -S "/run/php/php8.2-fpm.sock" ]; then
        local socket_perms=$(ls -la /run/php/php8.2-fpm.sock | awk '{print $1 " " $3 ":" $4}')
        print_result "PASS" "Socket PHP-FPM présent" "Permissions: $socket_perms"
    else
        print_result "FAIL" "Socket PHP-FPM manquant"
    fi
}

check_configuration() {
    print_section "2. VÉRIFICATION DE LA CONFIGURATION"
    
    # Configuration Nginx
    print_test "configuration nginx PHP"
    local nginx_conf="/etc/nginx/sites-available/maxlink-dashboard"
    if [ -f "$nginx_conf" ]; then
        if grep -q "\.php" "$nginx_conf" && grep -q "fastcgi_pass" "$nginx_conf"; then
            local socket_configured=$(grep "fastcgi_pass" "$nginx_conf" | head -1 | sed 's/.*unix:\([^;]*\).*/\1/')
            print_result "PASS" "Configuration PHP présente" "Socket: $socket_configured"
        else
            print_result "FAIL" "Configuration PHP manquante"
        fi
    else
        print_result "FAIL" "Fichier de configuration nginx manquant"
    fi
    
    # Test syntaxe nginx
    print_test "syntaxe nginx"
    if nginx -t >/dev/null 2>&1; then
        print_result "PASS" "Syntaxe nginx valide"
    else
        print_result "FAIL" "Erreur de syntaxe nginx"
    fi
    
    # Sites activés
    print_test "site nginx activé"
    if [ -L "/etc/nginx/sites-enabled/maxlink-dashboard" ]; then
        print_result "PASS" "Site maxlink-dashboard activé"
    else
        print_result "FAIL" "Site non activé"
    fi
}

check_files() {
    print_section "3. VÉRIFICATION DES FICHIERS"
    
    local dashboard_dir="/var/www/maxlink-dashboard"
    
    # Archives List API
    print_test "archives-list.php"
    if [ -f "$dashboard_dir/archives-list.php" ]; then
        local size=$(stat -c%s "$dashboard_dir/archives-list.php")
        local perms=$(stat -c "%a %U:%G" "$dashboard_dir/archives-list.php")
        print_result "PASS" "Archives List API présent" "Taille: ${size}B, Perms: $perms"
    else
        print_result "FAIL" "Archives List API manquant"
    fi
    
    # Download API
    print_test "download-archive.php"
    if [ -f "$dashboard_dir/download-archive.php" ]; then
        local size=$(stat -c%s "$dashboard_dir/download-archive.php")
        local perms=$(stat -c "%a %U:%G" "$dashboard_dir/download-archive.php")
        print_result "PASS" "Download API présent" "Taille: ${size}B, Perms: $perms"
    else
        print_result "FAIL" "Download API manquant"
    fi
    
    # JavaScript Manager
    print_test "download-manager.js"
    if [ -f "$dashboard_dir/download-manager.js" ]; then
        local size=$(stat -c%s "$dashboard_dir/download-manager.js")
        local perms=$(stat -c "%a %U:%G" "$dashboard_dir/download-manager.js")
        print_result "PASS" "JavaScript Manager présent" "Taille: ${size}B, Perms: $perms"
    else
        print_result "FAIL" "JavaScript Manager manquant"
    fi
    
    # Répertoire archives
    print_test "répertoire archives"
    if [ -d "$dashboard_dir/archives" ]; then
        local perms=$(stat -c "%a %U:%G" "$dashboard_dir/archives")
        print_result "PASS" "Répertoire archives présent" "Perms: $perms"
    else
        print_result "WARN" "Répertoire archives manquant"
    fi
    
    # Archives de données
    print_test "archives de données"
    local archives_data_dir="/home/prod/Documents/traçabilité/Archives"
    if [ -d "$archives_data_dir" ]; then
        local csv_count=$(find "$archives_data_dir" -name "*.csv" 2>/dev/null | wc -l)
        if [ "$csv_count" -gt 0 ]; then
            print_result "PASS" "Archives de données trouvées" "Fichiers CSV: $csv_count"
        else
            print_result "WARN" "Répertoire archives vide" "Aucun fichier CSV"
        fi
    else
        print_result "WARN" "Répertoire archives de données manquant"
    fi
}

check_http_access() {
    print_section "4. TESTS D'ACCÈS HTTP"
    
    # Test archives-list.php
    print_test "accès HTTP archives-list.php"
    local response=$(curl -s -w "HTTPCODE:%{http_code}" "http://localhost/archives-list.php" 2>/dev/null)
    local http_code=$(echo "$response" | grep -o "HTTPCODE:[0-9]*" | cut -d: -f2)
    local content=$(echo "$response" | sed 's/HTTPCODE:[0-9]*$//')
    
    if [ "$http_code" = "200" ]; then
        print_result "PASS" "Archives List API accessible" "HTTP $http_code"
    else
        print_result "FAIL" "Archives List API inaccessible" "HTTP $http_code"
    fi
    
    # Test download-archive.php
    print_test "accès HTTP download-archive.php"
    local response=$(curl -s -w "HTTPCODE:%{http_code}" "http://localhost/download-archive.php?help" 2>/dev/null)
    local http_code=$(echo "$response" | grep -o "HTTPCODE:[0-9]*" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        print_result "PASS" "Download API accessible" "HTTP $http_code"
    else
        print_result "FAIL" "Download API inaccessible" "HTTP $http_code"
    fi
    
    # Test download-manager.js
    print_test "accès HTTP download-manager.js"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-manager.js" 2>/dev/null)
    
    if [ "$http_code" = "200" ]; then
        print_result "PASS" "JavaScript Manager accessible" "HTTP $http_code"
    else
        print_result "FAIL" "JavaScript Manager inaccessible" "HTTP $http_code"
    fi
}

check_functionality() {
    print_section "5. TESTS FONCTIONNELS"
    
    # Test JSON archives-list.php
    print_test "réponse JSON archives-list.php"
    local response=$(curl -s "http://localhost/archives-list.php" 2>/dev/null)
    
    # Vérifier si c'est du PHP brut ou du JSON
    if [[ "$response" == "<?php"* ]]; then
        print_result "FAIL" "PHP retourné en brut (non exécuté)" "Début: ${response:0:50}..."
    elif echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
        local archives_count=$(echo "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict) and 'archives' in data:
        print(len(data['archives']))
    elif isinstance(data, list):
        print(len(data))
    else:
        print('0')
except:
    print('erreur')
")
        print_result "PASS" "JSON valide retourné" "Archives trouvées: $archives_count"
    else
        print_result "FAIL" "Réponse non-JSON" "Contenu: ${response:0:100}..."
    fi
    
    # Test JSON download-archive.php
    print_test "réponse JSON download-archive.php"
    local response=$(curl -s "http://localhost/download-archive.php?help" 2>/dev/null)
    
    if [[ "$response" == "<?php"* ]]; then
        print_result "FAIL" "PHP retourné en brut (non exécuté)"
    elif echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
        print_result "PASS" "JSON valide retourné"
    else
        print_result "WARN" "Réponse non-JSON (comportement possible)"
    fi
    
    # Test performance
    print_test "performance archives-list.php"
    local start_time=$(date +%s%N)
    curl -s "http://localhost/archives-list.php" >/dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 ))
    
    if [ "$duration" -lt 1000 ]; then
        print_result "PASS" "Performance correcte" "${duration}ms"
    elif [ "$duration" -lt 3000 ]; then
        print_result "WARN" "Performance acceptable" "${duration}ms"
    else
        print_result "FAIL" "Performance dégradée" "${duration}ms"
    fi
}

check_security() {
    print_section "6. VÉRIFICATION SÉCURITÉ"
    
    # Permissions fichiers
    print_test "permissions fichiers"
    local dashboard_dir="/var/www/maxlink-dashboard"
    local security_issues=0
    
    for file in "archives-list.php" "download-archive.php" "download-manager.js"; do
        if [ -f "$dashboard_dir/$file" ]; then
            local perms=$(stat -c "%a" "$dashboard_dir/$file")
            local owner=$(stat -c "%U:%G" "$dashboard_dir/$file")
            
            if [ "$perms" = "644" ] && [ "$owner" = "www-data:www-data" ]; then
                print_result "PASS" "Permissions correctes $file" "$perms, $owner"
            else
                print_result "WARN" "Permissions incorrectes $file" "$perms, $owner"
                ((security_issues++))
            fi
        fi
    done
    
    # Test injection basique
    print_test "protection injection SQL"
    local response=$(curl -s -w "HTTPCODE:%{http_code}" "http://localhost/archives-list.php?year=2025';DROP TABLE--" 2>/dev/null)
    local http_code=$(echo "$response" | grep -o "HTTPCODE:[0-9]*" | cut -d: -f2)
    
    if [ "$http_code" = "400" ] || [ "$http_code" = "403" ]; then
        print_result "PASS" "Protection injection active" "HTTP $http_code"
    else
        print_result "WARN" "Protection injection incertaine" "HTTP $http_code"
    fi
}

check_logs() {
    print_section "7. VÉRIFICATION DES LOGS"
    
    # Log d'installation
    print_test "log installation PHP Archives"
    local install_log="/var/log/maxlink/install/php_archives_install.log"
    if [ -f "$install_log" ]; then
        if grep -q "SUCCESS.*Installation.*terminée" "$install_log"; then
            print_result "PASS" "Installation loggée avec succès"
        else
            print_result "WARN" "Log d'installation sans succès confirmé"
        fi
    else
        print_result "INFO" "Log d'installation non trouvé" "Normal si première installation"
    fi
    
    # Logs d'erreur Nginx
    print_test "erreurs Nginx récentes"
    local nginx_error_log="/var/log/nginx/error.log"
    if [ -f "$nginx_error_log" ]; then
        local recent_errors=$(tail -50 "$nginx_error_log" | grep -E "(error|fail|fatal)" | grep "$(date +%Y/%m/%d)" | wc -l)
        local log_size=$(stat -c%s "$nginx_error_log")
        
        if [ "$recent_errors" -eq 0 ]; then
            print_result "PASS" "Aucune erreur récente" "Taille log: ${log_size}B"
        else
            print_result "WARN" "$recent_errors erreurs aujourd'hui" "Vérifiez le log"
        fi
    else
        print_result "INFO" "Log d'erreur nginx non trouvé"
    fi
    
    # Logs d'accès Nginx
    print_test "accès Nginx récents"
    local nginx_access_log="/var/log/nginx/access.log"
    if [ -f "$nginx_access_log" ]; then
        local php_requests=$(tail -100 "$nginx_access_log" | grep "\.php" | wc -l)
        print_result "INFO" "Requêtes PHP récentes" "$php_requests dans les 100 dernières"
    else
        print_result "INFO" "Log d'accès nginx non trouvé"
    fi
}

generate_summary() {
    print_header "RÉSUMÉ DU DIAGNOSTIC"
    
    local success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    
    echo "Tests effectués: $TOTAL_TESTS"
    echo -e "✅ Réussis: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "⚠️  Avertissements: ${YELLOW}$WARNED_TESTS${NC}"
    echo -e "❌ Échecs: ${RED}$FAILED_TESTS${NC}"
    echo ""
    
    if [ "$FAILED_TESTS" -eq 0 ] && [ "$WARNED_TESTS" -eq 0 ]; then
        echo -e "🎉 ${GREEN}SYSTÈME PARFAIT${NC} - Score: ${success_rate}%"
        echo "Tout fonctionne parfaitement !"
    elif [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "✅ ${GREEN}SYSTÈME FONCTIONNEL${NC} - Score: ${success_rate}%"
        echo "Système opérationnel avec quelques avertissements mineurs."
    elif [ "$success_rate" -ge 70 ]; then
        echo -e "⚠️  ${YELLOW}SYSTÈME ACCEPTABLE${NC} - Score: ${success_rate}%"
        echo "Des corrections sont recommandées."
    else
        echo -e "❌ ${RED}SYSTÈME DÉFAILLANT${NC} - Score: ${success_rate}%"
        echo "Corrections urgentes nécessaires."
    fi
    
    echo ""
    echo -e "${BLUE}🔗 URLs de test:${NC}"
    echo "  • Archives: http://localhost/archives-list.php"
    echo "  • Download: http://localhost/download-archive.php?help"
    echo "  • Manager:  http://localhost/download-manager.js"
    
    echo ""
    echo -e "${BLUE}📁 Chemins importants:${NC}"
    echo "  • Dashboard: /var/www/maxlink-dashboard"
    echo "  • Archives:  /home/prod/Documents/traçabilité/Archives"
    echo "  • Logs:     /var/log/maxlink/"
    
    if [ "$FAILED_TESTS" -gt 0 ] || [ "$WARNED_TESTS" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}💡 Actions recommandées:${NC}"
        echo "  • Vérifiez les logs: /var/log/nginx/error.log"
        echo "  • Relancez l'installation: sudo scripts/install/php_archives_install.sh"
        echo "  • Testez manuellement les URLs ci-dessus"
        
        if [ "$FAILED_TESTS" -gt 0 ]; then
            echo "  • Exécutez le script de correction: sudo ./fix.sh"
        fi
    fi
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

echo -e "${WHITE}========================================================================"
echo "🧪 DIAGNOSTIC SYSTÈME PHP ARCHIVES v2.0"
echo -e "========================================================================${NC}\n"

check_root

check_service_status
check_configuration  
check_files
check_http_access
check_functionality
check_security
check_logs

generate_summary

echo ""