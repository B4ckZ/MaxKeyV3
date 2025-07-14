#!/bin/bash

# ===============================================================================
# DIAGNOSTIC APPROFONDI NGINX/PHP
# Identifie précisément pourquoi PHP n'est pas exécuté
# ===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

print_header() {
    echo -e "\n${WHITE}========== $1 ==========${NC}"
}

print_check() {
    echo -e "${BLUE}🔍 $1${NC}"
}

print_result() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        "OK") echo -e "   ${GREEN}✅ $message${NC}" ;;
        "FAIL") echo -e "   ${RED}❌ $message${NC}" ;;
        "WARN") echo -e "   ${YELLOW}⚠️  $message${NC}" ;;
    esac
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ce script doit être exécuté en tant que root${NC}"
    exit 1
fi

print_header "DIAGNOSTIC APPROFONDI NGINX/PHP"

print_check "1. État des services"

# Nginx
if systemctl is-active --quiet nginx; then
    print_result "OK" "Nginx actif"
    NGINX_PID=$(pgrep nginx | head -1)
    echo "      PID: $NGINX_PID"
else
    print_result "FAIL" "Nginx inactif"
fi

# PHP-FPM
FPM_SERVICES=$(systemctl list-units --type=service --state=active | grep php | grep fpm)
if [ -n "$FPM_SERVICES" ]; then
    print_result "OK" "PHP-FPM actif"
    echo "      Service(s): $FPM_SERVICES"
else
    print_result "FAIL" "PHP-FPM inactif"
fi

print_check "2. Sockets et processus PHP-FPM"

# Sockets PHP-FPM
FPM_SOCKETS=$(find /run/php -name "*.sock" 2>/dev/null)
if [ -n "$FPM_SOCKETS" ]; then
    print_result "OK" "Sockets PHP-FPM trouvés"
    for socket in $FPM_SOCKETS; do
        if [ -S "$socket" ]; then
            perms=$(ls -la "$socket" | awk '{print $1 " " $3 ":" $4}')
            echo "      $socket ($perms)"
        fi
    done
else
    print_result "FAIL" "Aucun socket PHP-FPM trouvé"
fi

# Processus PHP-FPM
FPM_PROCESSES=$(pgrep -f "php.*fpm" | wc -l)
if [ "$FMP_PROCESSES" -gt 0 ]; then
    print_result "OK" "$FPM_PROCESSES processus PHP-FPM actifs"
else
    print_result "FAIL" "Aucun processus PHP-FPM"
fi

print_check "3. Configuration nginx actuelle"

NGINX_CONF="/etc/nginx/sites-available/default"
NGINX_ENABLED="/etc/nginx/sites-enabled/default"

if [ -f "$NGINX_CONF" ]; then
    print_result "OK" "Fichier de configuration nginx trouvé"
    
    # Vérifier si la config contient PHP
    if grep -q "\.php" "$NGINX_CONF"; then
        print_result "OK" "Configuration PHP présente"
    else
        print_result "FAIL" "Configuration PHP absente"
    fi
    
    # Vérifier le socket utilisé
    SOCKET_IN_CONF=$(grep "fastcgi_pass" "$NGINX_CONF" | head -1)
    if [ -n "$SOCKET_IN_CONF" ]; then
        print_result "OK" "Directive fastcgi_pass trouvée"
        echo "      $SOCKET_IN_CONF"
        
        # Extraire le socket
        CONFIGURED_SOCKET=$(echo "$SOCKET_IN_CONF" | sed 's/.*unix:\([^;]*\).*/\1/')
        if [ -S "$CONFIGURED_SOCKET" ]; then
            print_result "OK" "Socket configuré existe: $CONFIGURED_SOCKET"
        else
            print_result "FAIL" "Socket configuré n'existe pas: $CONFIGURED_SOCKET"
        fi
    else
        print_result "FAIL" "Directive fastcgi_pass manquante"
    fi
else
    print_result "FAIL" "Fichier de configuration nginx manquant"
fi

# Vérifier le lien symbolique sites-enabled
if [ -L "$NGINX_ENABLED" ]; then
    print_result "OK" "Site activé (lien symbolique présent)"
else
    print_result "FAIL" "Site non activé (lien symbolique manquant)"
fi

print_check "4. Test de configuration nginx"

# Test de syntaxe nginx
if nginx -t 2>/dev/null; then
    print_result "OK" "Syntaxe nginx valide"
else
    print_result "FAIL" "Erreur de syntaxe nginx"
    echo "      Détails:"
    nginx -t 2>&1 | sed 's/^/        /'
fi

print_check "5. Résolution et accès réseau"

# Test de résolution localhost
if ping -c1 localhost >/dev/null 2>&1; then
    print_result "OK" "localhost résolvable"
else
    print_result "FAIL" "localhost non résolvable"
fi

# Test du port 80
if netstat -tlpn | grep -q ":80.*nginx"; then
    print_result "OK" "nginx écoute sur le port 80"
else
    print_result "WARN" "nginx n'écoute pas sur le port 80"
    echo "      Ports écoutés par nginx:"
    netstat -tlpn | grep nginx | sed 's/^/        /'
fi

print_check "6. Test HTTP détaillé"

echo "Test HTTP avec curl verbose..."
CURL_OUTPUT=$(curl -v "http://localhost/archives-list.php" 2>&1)
CURL_CODE=$?

if [ $CURL_CODE -eq 0 ]; then
    print_result "OK" "Connexion HTTP réussie"
    
    # Analyser la réponse
    if echo "$CURL_OUTPUT" | grep -q "200 OK"; then
        print_result "OK" "HTTP 200 reçu"
    else
        HTTP_STATUS=$(echo "$CURL_OUTPUT" | grep "HTTP/" | head -1)
        print_result "WARN" "Statut HTTP: $HTTP_STATUS"
    fi
    
    # Vérifier le contenu
    CONTENT=$(echo "$CURL_OUTPUT" | sed -n '/^<?php/,$p')
    if [ -n "$CONTENT" ]; then
        print_result "FAIL" "PHP retourné en brut (non exécuté)"
        echo "      Début du contenu:"
        echo "$CONTENT" | head -3 | sed 's/^/        /'
    else
        print_result "OK" "Contenu semble être du JSON"
    fi
else
    print_result "FAIL" "Échec de connexion HTTP (code: $CURL_CODE)"
    echo "      Erreur curl:"
    echo "$CURL_OUTPUT" | grep -E "(curl:|failed|error)" | sed 's/^/        /'
fi

print_check "7. Logs nginx récents"

NGINX_ERROR_LOG="/var/log/nginx/error.log"
if [ -f "$NGINX_ERROR_LOG" ]; then
    RECENT_ERRORS=$(tail -20 "$NGINX_ERROR_LOG" | grep -E "(error|fail|fatal)" | wc -l)
    if [ "$RECENT_ERRORS" -eq 0 ]; then
        print_result "OK" "Aucune erreur récente dans nginx"
    else
        print_result "WARN" "$RECENT_ERRORS erreurs récentes trouvées"
        echo "      Dernières erreurs:"
        tail -10 "$NGINX_ERROR_LOG" | grep -E "(error|fail|fatal)" | sed 's/^/        /'
    fi
else
    print_result "WARN" "Log d'erreur nginx non trouvé"
fi

print_check "8. Test direct du socket PHP-FPM"

if [ -n "$CONFIGURED_SOCKET" ] && [ -S "$CONFIGURED_SOCKET" ]; then
    echo "Test du socket PHP-FPM avec cgi-fcgi..."
    if command -v cgi-fcgi >/dev/null 2>&1; then
        TEST_RESULT=$(echo -e "SCRIPT_FILENAME=/var/www/maxlink-dashboard/archives-list.php\nREQUEST_METHOD=GET\n\n" | cgi-fcgi -bind -connect "$CONFIGURED_SOCKET" 2>&1)
        if echo "$TEST_RESULT" | grep -q "Content-Type"; then
            print_result "OK" "Socket PHP-FPM répond"
        else
            print_result "FAIL" "Socket PHP-FPM ne répond pas correctement"
        fi
    else
        print_result "WARN" "cgi-fcgi non installé (impossible de tester le socket)"
    fi
fi

print_check "9. Structure des fichiers"

DASHBOARD_DIR="/var/www/maxlink-dashboard"
echo "Contenu de $DASHBOARD_DIR:"
if [ -d "$DASHBOARD_DIR" ]; then
    ls -la "$DASHBOARD_DIR" | head -10 | sed 's/^/  /'
    
    # Vérifier le fichier PHP
    if [ -f "$DASHBOARD_DIR/archives-list.php" ]; then
        print_result "OK" "archives-list.php présent"
        echo "      Premières lignes:"
        head -3 "$DASHBOARD_DIR/archives-list.php" | sed 's/^/        /'
    else
        print_result "FAIL" "archives-list.php manquant"
    fi
else
    print_result "FAIL" "Répertoire dashboard manquant"
fi

print_header "RECOMMANDATIONS"

echo -e "${YELLOW}Basé sur ce diagnostic, voici les actions recommandées:${NC}\n"

# Actions correctives
if ! systemctl is-active --quiet php8.2-fpm; then
    echo -e "${RED}1. Démarrer PHP-FPM:${NC}"
    echo "   sudo systemctl start php8.2-fpm"
    echo "   sudo systemctl enable php8.2-fpm"
fi

if [ ! -L "$NGINX_ENABLED" ]; then
    echo -e "${RED}2. Activer le site nginx:${NC}"
    echo "   sudo ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/"
fi

if ! nginx -t 2>/dev/null; then
    echo -e "${RED}3. Corriger la configuration nginx${NC}"
fi

echo -e "${BLUE}4. Redémarrer les services:${NC}"
echo "   sudo systemctl restart php8.2-fpm"
echo "   sudo systemctl restart nginx"

echo -e "${BLUE}5. Tester manuellement:${NC}"
echo "   curl -v http://localhost/archives-list.php"

echo ""