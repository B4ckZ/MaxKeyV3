#!/bin/bash

# ===============================================================================
# MAXLINK - DIAGNOSTIC DU SYSTÈME PHP ARCHIVES ULTRA-SIMPLIFIÉ
# Vérifie que tout le nouveau système fonctionne correctement
# Version 3.0 - Sans ZIP, téléchargement direct CSV
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Fonction pour afficher les résultats
print_result() {
    local status="$1"
    local message="$2"
    local details="$3"
    
    ((TOTAL_TESTS++))
    
    case "$status" in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC} - $message"
            [ -n "$details" ] && echo -e "   ${CYAN}ℹ️  $details${NC}"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC} - $message"
            [ -n "$details" ] && echo -e "   ${RED}💀 $details${NC}"
            ((FAILED_TESTS++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC} - $message"
            [ -n "$details" ] && echo -e "   ${YELLOW}⚠️  $details${NC}"
            ((WARNING_TESTS++))
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  INFO${NC} - $message"
            [ -n "$details" ] && echo -e "   ${CYAN}📝 $details${NC}"
            ;;
    esac
}

print_header() {
    echo -e "\n${WHITE}========================================================================"
    echo -e "$1"
    echo -e "========================================================================${NC}\n"
}

print_section() {
    echo -e "\n${CYAN}🔍 $1${NC}"
    echo "----------------------------------------"
}

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ce script doit être exécuté en tant que root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Charger les variables si disponibles
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$BASE_DIR/scripts/common/variables.sh" ]; then
    source "$BASE_DIR/scripts/common/variables.sh"
    DASHBOARD_DIR="$NGINX_DASHBOARD_DIR"
else
    DASHBOARD_DIR="/var/www/maxlink-dashboard"
fi

ARCHIVES_PATH="/home/prod/Documents/traçabilité/Archives"

print_header "🧪 DIAGNOSTIC SYSTÈME PHP ARCHIVES v3.0 - ULTRA-SIMPLIFIÉ"

print_section "1. VÉRIFICATION DU SERVICE PHP_ARCHIVES"

# Statut du service dans services_status.json
if [ -f "/var/lib/maxlink/services_status.json" ]; then
    SERVICE_STATUS=$(python3 -c "
import json
try:
    with open('/var/lib/maxlink/services_status.json', 'r') as f:
        data = json.load(f)
    print(data.get('php_archives', {}).get('status', 'unknown'))
except:
    print('error')
" 2>/dev/null)
    
    if [ "$SERVICE_STATUS" = "active" ]; then
        print_result "PASS" "Service php_archives actif" "Statut: $SERVICE_STATUS"
    else
        print_result "FAIL" "Service php_archives inactif" "Statut: $SERVICE_STATUS"
    fi
else
    print_result "WARN" "Fichier services_status.json non trouvé" "Le service peut fonctionner sans ce fichier"
fi

# Vérification PHP
if command -v php >/dev/null 2>&1; then
    PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
    print_result "PASS" "PHP installé" "Version: $PHP_VERSION"
else
    print_result "FAIL" "PHP non installé" "Requis pour le système d'archives"
fi

# Vérification des paquets PHP requis
for pkg in php php-cli php-fpm; do
    if dpkg -l "$pkg" >/dev/null 2>&1; then
        print_result "PASS" "Paquet $pkg installé"
    else
        print_result "FAIL" "Paquet $pkg manquant"
    fi
done

# Important: Vérifier qu'il n'y a PAS php-zip
if dpkg -l "php-zip" >/dev/null 2>&1; then
    print_result "WARN" "Paquet php-zip installé" "Non requis dans le nouveau système"
else
    print_result "PASS" "Paquet php-zip absent" "Correct - nouveau système sans ZIP"
fi

print_section "2. VÉRIFICATION DES FICHIERS DU SYSTÈME"

# Fichiers PHP principaux
FILES_TO_CHECK=(
    "$DASHBOARD_DIR/archives-list.php:Archives List API"
    "$DASHBOARD_DIR/download-archive.php:Download API"
    "$DASHBOARD_DIR/download-manager.js:Download Manager JavaScript"
)

for file_info in "${FILES_TO_CHECK[@]}"; do
    IFS=':' read -r file_path file_desc <<< "$file_info"
    
    if [ -f "$file_path" ]; then
        file_size=$(stat -c%s "$file_path" 2>/dev/null)
        file_perms=$(stat -c%a "$file_path" 2>/dev/null)
        file_owner=$(stat -c%U:%G "$file_path" 2>/dev/null)
        print_result "PASS" "$file_desc présent" "Taille: ${file_size}B, Perms: $file_perms, Propriétaire: $file_owner"
    else
        print_result "FAIL" "$file_desc manquant" "Fichier: $file_path"
    fi
done

# Répertoire des archives
if [ -d "$ARCHIVES_PATH" ]; then
    archive_size=$(du -sh "$ARCHIVES_PATH" 2>/dev/null | cut -f1)
    archive_files=$(find "$ARCHIVES_PATH" -name "*.csv" 2>/dev/null | wc -l)
    print_result "PASS" "Répertoire archives présent" "Taille: $archive_size, Fichiers CSV: $archive_files"
else
    print_result "WARN" "Répertoire archives absent" "Chemin: $ARCHIVES_PATH"
fi

print_section "3. TESTS DES APIS HTTP"

# Test Nginx
if systemctl is-active --quiet nginx; then
    print_result "PASS" "Service Nginx actif"
else
    print_result "FAIL" "Service Nginx inactif" "Requis pour servir les APIs"
fi

# Test des endpoints
ENDPOINTS=(
    "http://localhost/archives-list.php:Archives List API"
    "http://localhost/download-archive.php?help:Download API Help"
    "http://localhost/download-manager.js:Download Manager JS"
)

for endpoint_info in "${ENDPOINTS[@]}"; do
    IFS=':' read -r url desc <<< "$endpoint_info"
    
    response=$(curl -s -o /dev/null -w "%{http_code}:%{time_total}" "$url" 2>/dev/null || echo "000:0")
    IFS=':' read -r http_code response_time <<< "$response"
    
    if [ "$http_code" = "200" ]; then
        print_result "PASS" "$desc accessible" "HTTP $http_code en ${response_time}s"
    elif [ "$http_code" = "000" ]; then
        print_result "FAIL" "$desc inaccessible" "Connexion impossible"
    else
        print_result "WARN" "$desc retourne HTTP $http_code" "Comportement inattendu"
    fi
done

print_section "4. TESTS FONCTIONNELS"

# Test JSON de la liste des archives
echo -n "Test du JSON archives-list.php... "
archives_json=$(curl -s "http://localhost/archives-list.php" 2>/dev/null)
if echo "$archives_json" | python3 -m json.tool >/dev/null 2>&1; then
    archive_count=$(echo "$archives_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    total = sum(len(weeks) for weeks in data.values()) if isinstance(data, dict) else 0
    print(total)
except:
    print(0)
" 2>/dev/null)
    print_result "PASS" "JSON archives-list.php valide" "$archive_count semaines disponibles"
else
    print_result "FAIL" "JSON archives-list.php invalide" "Réponse: ${archives_json:0:100}..."
fi

# Test de téléchargement (simulation)
echo -n "Test simulation téléchargement... "
if [ -n "$archives_json" ] && [ "$archives_json" != "[]" ]; then
    # Essayer de trouver un fichier à tester
    first_file=$(echo "$archives_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for year, weeks in data.items():
        for week in weeks:
            if week.get('files'):
                file_info = week['files'][0]
                print(f\"{file_info['filename']}:{year}\")
                break
        else:
            continue
        break
    else:
        print('none:none')
except:
    print('error:error')
" 2>/dev/null)
    
    IFS=':' read -r test_file test_year <<< "$first_file"
    
    if [ "$test_file" != "none" ] && [ "$test_file" != "error" ]; then
        test_url="http://localhost/download-archive.php?file=${test_file}&year=${test_year}"
        test_response=$(curl -s -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null || echo "000")
        
        if [ "$test_response" = "200" ]; then
            print_result "PASS" "Téléchargement fichier simulé" "Fichier: $test_file"
        else
            print_result "WARN" "Téléchargement fichier échoué" "HTTP $test_response pour $test_file"
        fi
    else
        print_result "WARN" "Aucun fichier trouvé pour test" "Archives vides ou erreur parsing"
    fi
else
    print_result "WARN" "Pas d'archives pour tester téléchargement" "Archives vides"
fi

print_section "5. VÉRIFICATION DU WIDGET DOWNLOADBUTTON"

# Fichiers du widget
WIDGET_PATH="$BASE_DIR/widgets/downloadbutton"
WIDGET_FILES=(
    "$WIDGET_PATH/downloadbutton.html:Widget HTML"
    "$WIDGET_PATH/downloadbutton.js:Widget JavaScript"
    "$WIDGET_PATH/downloadbutton.css:Widget CSS"
)

if [ -d "$WIDGET_PATH" ]; then
    print_result "PASS" "Répertoire widget downloadbutton présent"
    
    for widget_file_info in "${WIDGET_FILES[@]}"; do
        IFS=':' read -r widget_file widget_desc <<< "$widget_file_info"
        
        if [ -f "$widget_file" ]; then
            widget_size=$(stat -c%s "$widget_file" 2>/dev/null)
            print_result "PASS" "$widget_desc présent" "Taille: ${widget_size}B"
        else
            print_result "WARN" "$widget_desc manquant" "Fichier: $widget_file"
        fi
    done
else
    print_result "WARN" "Répertoire widget downloadbutton absent" "Chemin: $WIDGET_PATH"
fi

print_section "6. VÉRIFICATION DE LA SÉCURITÉ"

# Permissions des fichiers
security_files=(
    "$DASHBOARD_DIR/archives-list.php"
    "$DASHBOARD_DIR/download-archive.php"
    "$DASHBOARD_DIR/download-manager.js"
)

for sec_file in "${security_files[@]}"; do
    if [ -f "$sec_file" ]; then
        file_perms=$(stat -c%a "$sec_file" 2>/dev/null)
        file_owner=$(stat -c%U "$sec_file" 2>/dev/null)
        
        if [ "$file_perms" = "644" ] && [ "$file_owner" = "www-data" ]; then
            print_result "PASS" "Permissions correctes $(basename "$sec_file")" "644, www-data"
        else
            print_result "WARN" "Permissions $(basename "$sec_file")" "Actuelles: $file_perms, $file_owner"
        fi
    fi
done

# Test injection basique
echo -n "Test protection injection... "
injection_test=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php?file=../../../etc/passwd&year=2025" 2>/dev/null || echo "000")
if [ "$injection_test" = "400" ] || [ "$injection_test" = "403" ]; then
    print_result "PASS" "Protection injection active" "HTTP $injection_test pour tentative ../../../"
else
    print_result "WARN" "Protection injection incertaine" "HTTP $injection_test"
fi

print_section "7. TESTS DE PERFORMANCE"

# Temps de réponse
echo -n "Test performance archives-list.php... "
perf_time=$(curl -s -o /dev/null -w "%{time_total}" "http://localhost/archives-list.php" 2>/dev/null || echo "0")
perf_ms=$(echo "$perf_time * 1000" | bc -l 2>/dev/null | cut -d. -f1 2>/dev/null || echo "0")

if [ "${perf_ms:-0}" -lt 1000 ]; then
    print_result "PASS" "Performance archives-list.php" "${perf_ms}ms"
elif [ "${perf_ms:-0}" -lt 3000 ]; then
    print_result "WARN" "Performance archives-list.php acceptable" "${perf_ms}ms"
else
    print_result "WARN" "Performance archives-list.php lente" "${perf_ms}ms"
fi

# Taille de la réponse
response_size=$(curl -s "http://localhost/archives-list.php" 2>/dev/null | wc -c)
if [ "$response_size" -gt 0 ]; then
    if [ "$response_size" -lt 10000 ]; then
        print_result "PASS" "Taille réponse raisonnable" "${response_size} octets"
    else
        print_result "WARN" "Réponse volumineuse" "${response_size} octets"
    fi
else
    print_result "FAIL" "Réponse vide"
fi

print_section "8. VÉRIFICATION LOGS"

# Logs récents
LOG_FILES=(
    "/var/log/maxlink/php_archives_install.log:Installation PHP Archives"
    "/var/log/nginx/error.log:Erreurs Nginx"
    "/var/log/nginx/access.log:Accès Nginx"
)

for log_info in "${LOG_FILES[@]}"; do
    IFS=':' read -r log_file log_desc <<< "$log_info"
    
    if [ -f "$log_file" ]; then
        log_size=$(stat -c%s "$log_file" 2>/dev/null)
        recent_errors=$(grep -i "error\|fail\|fatal" "$log_file" 2>/dev/null | tail -5 | wc -l)
        
        if [ "$recent_errors" -eq 0 ]; then
            print_result "PASS" "$log_desc sans erreur récente" "Taille: ${log_size}B"
        else
            print_result "WARN" "$log_desc avec $recent_errors erreurs récentes" "Vérifiez: $log_file"
        fi
    else
        print_result "INFO" "$log_desc absent" "Fichier: $log_file"
    fi
done

print_header "📊 RÉSUMÉ DU DIAGNOSTIC"

echo -e "${WHITE}Tests effectués:${NC} $TOTAL_TESTS"
echo -e "${GREEN}✅ Réussis:${NC} $PASSED_TESTS"
echo -e "${YELLOW}⚠️  Avertissements:${NC} $WARNING_TESTS"
echo -e "${RED}❌ Échecs:${NC} $FAILED_TESTS"

echo ""

# Calcul du score
if [ "$TOTAL_TESTS" -gt 0 ]; then
    score=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    
    if [ "$score" -ge 90 ]; then
        echo -e "${GREEN}🎉 SYSTÈME EXCELLENT${NC} - Score: ${score}%"
        echo -e "${GREEN}Le système PHP Archives fonctionne parfaitement !${NC}"
    elif [ "$score" -ge 75 ]; then
        echo -e "${YELLOW}✅ SYSTÈME BON${NC} - Score: ${score}%"
        echo -e "${YELLOW}Quelques améliorations mineures possibles.${NC}"
    elif [ "$score" -ge 50 ]; then
        echo -e "${YELLOW}⚠️  SYSTÈME ACCEPTABLE${NC} - Score: ${score}%"
        echo -e "${YELLOW}Des corrections sont recommandées.${NC}"
    else
        echo -e "${RED}❌ SYSTÈME DÉFAILLANT${NC} - Score: ${score}%"
        echo -e "${RED}Des corrections majeures sont requises.${NC}"
    fi
fi

echo ""
echo -e "${CYAN}🔗 URLs de test:${NC}"
echo "  • Archives: http://localhost/archives-list.php"
echo "  • Download: http://localhost/download-archive.php?help"
echo "  • Manager:  http://localhost/download-manager.js"

echo ""
echo -e "${CYAN}📁 Chemins importants:${NC}"
echo "  • Dashboard: $DASHBOARD_DIR"
echo "  • Archives:  $ARCHIVES_PATH"
echo "  • Widget:    $WIDGET_PATH"

if [ "$FAILED_TESTS" -gt 0 ]; then
    echo ""
    echo -e "${RED}💡 Actions recommandées:${NC}"
    echo "  • Vérifiez les logs: /var/log/maxlink/"
    echo "  • Réinstallez si nécessaire: sudo scripts/install/php_archives_install.sh"
    echo "  • Testez manuellement les URLs ci-dessus"
    exit 1
else
    echo ""
    echo -e "${GREEN}✨ Le système est opérationnel !${NC}"
    exit 0
fi