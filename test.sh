#!/bin/bash
#
# Script de diagnostic - Système de téléchargement des archives
# Teste et valide la solution PHP pure
# MaxLink Dashboard v3.1
#

set -e

# Configuration
NGINX_ROOT="/var/www/maxlink-dashboard"
TRACABILITY_DIR="/home/prod/Documents/traçabilité"
ARCHIVES_DIR="$TRACABILITY_DIR/Archives"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "🔍 DIAGNOSTIC SYSTÈME TÉLÉCHARGEMENT ARCHIVES - PHP PUR"
echo "========================================================================"
echo ""

# Variables de comptage
TESTS_TOTAL=0
TESTS_OK=0
TESTS_KO=0

function test_result() {
    local status=$1
    local message=$2
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$status" = "OK" ]; then
        echo -e "   ${GREEN}✅ $message${NC}"
        TESTS_OK=$((TESTS_OK + 1))
    elif [ "$status" = "WARNING" ]; then
        echo -e "   ${YELLOW}⚠️  $message${NC}"
    else
        echo -e "   ${RED}❌ $message${NC}"
        TESTS_KO=$((TESTS_KO + 1))
    fi
}

function test_section() {
    echo -e "${BLUE}$1${NC}"
}

# ===============================================================================
# TEST 1 : VÉRIFICATIONS SYSTÈME DE BASE
# ===============================================================================

test_section "🔧 VÉRIFICATIONS SYSTÈME DE BASE"

# Privilèges root
if [ "$EUID" -eq 0 ]; then
    test_result "OK" "Privilèges root confirmés"
else
    test_result "KO" "Ce script doit être exécuté en tant que root"
    exit 1
fi

# Nginx installé et actif
if systemctl is-active --quiet nginx; then
    test_result "OK" "Nginx actif"
else
    test_result "KO" "Nginx non actif"
fi

# PHP installé
if command -v php >/dev/null 2>&1; then
    PHP_VERSION=$(php -v | head -n1 | cut -d' ' -f2)
    test_result "OK" "PHP installé (version $PHP_VERSION)"
else
    test_result "KO" "PHP non installé"
fi

# Extension PHP zip
if php -m | grep -q zip; then
    test_result "OK" "Extension PHP zip disponible"
else
    test_result "KO" "Extension PHP zip manquante"
fi

echo ""

# ===============================================================================
# TEST 2 : FICHIERS DU SYSTÈME DE TÉLÉCHARGEMENT
# ===============================================================================

test_section "📁 FICHIERS DU SYSTÈME DE TÉLÉCHARGEMENT"

# archives-list.php
if [ -f "$NGINX_ROOT/archives-list.php" ]; then
    test_result "OK" "archives-list.php présent"
    
    # Test syntaxe PHP
    if php -l "$NGINX_ROOT/archives-list.php" >/dev/null 2>&1; then
        test_result "OK" "archives-list.php syntaxe valide"
    else
        test_result "KO" "archives-list.php erreur de syntaxe"
    fi
    
    # Permissions
    PERMS=$(stat -c "%a" "$NGINX_ROOT/archives-list.php")
    if [ "$PERMS" = "644" ]; then
        test_result "OK" "archives-list.php permissions OK (644)"
    else
        test_result "WARNING" "archives-list.php permissions: $PERMS (recommandé: 644)"
    fi
else
    test_result "KO" "archives-list.php MANQUANT"
fi

# download-archive.php
if [ -f "$NGINX_ROOT/download-archive.php" ]; then
    test_result "OK" "download-archive.php présent"
    
    # Test syntaxe PHP
    if php -l "$NGINX_ROOT/download-archive.php" >/dev/null 2>&1; then
        test_result "OK" "download-archive.php syntaxe valide"
    else
        test_result "KO" "download-archive.php erreur de syntaxe"
    fi
    
    # Permissions
    PERMS=$(stat -c "%a" "$NGINX_ROOT/download-archive.php")
    if [ "$PERMS" = "644" ]; then
        test_result "OK" "download-archive.php permissions OK (644)"
    else
        test_result "WARNING" "download-archive.php permissions: $PERMS (recommandé: 644)"
    fi
else
    test_result "KO" "download-archive.php MANQUANT"
fi

# Widget downloadbutton.js
if [ -f "$NGINX_ROOT/widgets/downloadbutton/downloadbutton.js" ]; then
    test_result "OK" "downloadbutton.js présent"
    
    # Vérifier qu'il utilise bien PHP (chercher archives-list.php)
    if grep -q "archives-list.php" "$NGINX_ROOT/widgets/downloadbutton/downloadbutton.js"; then
        test_result "OK" "downloadbutton.js configuré pour PHP"
    else
        test_result "KO" "downloadbutton.js ne semble pas configuré pour PHP"
    fi
else
    test_result "KO" "downloadbutton.js MANQUANT"
fi

echo ""

# ===============================================================================
# TEST 3 : DOSSIERS DE TRAÇABILITÉ
# ===============================================================================

test_section "📂 DOSSIERS DE TRAÇABILITÉ"

# Dossier principal
if [ -d "$TRACABILITY_DIR" ]; then
    test_result "OK" "Dossier traçabilité présent ($TRACABILITY_DIR)"
    
    # Permissions du dossier
    OWNER=$(stat -c "%U:%G" "$TRACABILITY_DIR")
    test_result "OK" "Propriétaire: $OWNER"
else
    test_result "WARNING" "Dossier traçabilité manquant (sera créé)"
    mkdir -p "$TRACABILITY_DIR"
    chown prod:prod "$TRACABILITY_DIR"
fi

# Dossier Archives
if [ -d "$ARCHIVES_DIR" ]; then
    test_result "OK" "Dossier Archives présent"
    
    # Compter les années
    YEAR_COUNT=$(find "$ARCHIVES_DIR" -maxdepth 1 -type d -name "20*" | wc -l)
    test_result "OK" "Nombre d'années archivées: $YEAR_COUNT"
else
    test_result "WARNING" "Dossier Archives manquant (normal sur serveur neuf)"
fi

# Accès www-data
if groups www-data | grep -q prod; then
    test_result "OK" "www-data a accès au groupe prod"
else
    test_result "WARNING" "www-data n'a pas accès au groupe prod (à configurer)"
    usermod -a -G prod www-data
    test_result "OK" "www-data ajouté au groupe prod"
fi

echo ""

# ===============================================================================
# TEST 4 : TESTS HTTP
# ===============================================================================

test_section "🌐 TESTS HTTP"

# Test archives-list.php via HTTP
echo "   🔍 Test HTTP archives-list.php..."
HTTP_CODE=$(curl -s -o /tmp/archives_test.json -w "%{http_code}" "http://localhost/archives-list.php")

if [ "$HTTP_CODE" = "200" ]; then
    test_result "OK" "archives-list.php répond HTTP 200"
    
    # Vérifier que c'est du JSON valide
    if jq . /tmp/archives_test.json >/dev/null 2>&1; then
        test_result "OK" "archives-list.php retourne du JSON valide"
        
        # Afficher le contenu
        CONTENT=$(cat /tmp/archives_test.json)
        if [ "$CONTENT" = "[]" ] || [ "$CONTENT" = "{}" ]; then
            test_result "WARNING" "archives-list.php retourne vide (normal si pas d'archives)"
        else
            test_result "OK" "archives-list.php retourne des données"
        fi
    else
        test_result "KO" "archives-list.php ne retourne pas du JSON valide"
    fi
else
    test_result "KO" "archives-list.php erreur HTTP $HTTP_CODE"
fi

# Test download-archive.php (sans paramètres, doit retourner 400)
echo "   🔍 Test HTTP download-archive.php..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php")

if [ "$HTTP_CODE" = "400" ]; then
    test_result "OK" "download-archive.php répond HTTP 400 (normal sans paramètres)"
elif [ "$HTTP_CODE" = "200" ]; then
    test_result "WARNING" "download-archive.php répond HTTP 200 (inattendu sans paramètres)"
else
    test_result "KO" "download-archive.php erreur HTTP $HTTP_CODE"
fi

rm -f /tmp/archives_test.json

echo ""

# ===============================================================================
# TEST 5 : CRÉATION DE DONNÉES DE TEST
# ===============================================================================

test_section "🧪 CRÉATION DE DONNÉES DE TEST"

echo "   📝 Création d'archives de test..."

# Créer le dossier Archives si nécessaire
mkdir -p "$ARCHIVES_DIR/2025"
chown -R prod:prod "$ARCHIVES_DIR"

# Créer quelques fichiers de test pour la semaine 28 de 2025
TEST_FILES=(
    "S28_2025_509.csv"
    "S28_2025_511.csv"
    "S28_2025_RPDT.csv"
)

for file in "${TEST_FILES[@]}"; do
    echo "date,heure,équipe,codebarre,résultat" > "$ARCHIVES_DIR/2025/$file"
    echo "14/07/2025,10H30,A,24042551110457205101005321,1" >> "$ARCHIVES_DIR/2025/$file"
    echo "14/07/2025,10H31,A,24042551110457205101005322,0" >> "$ARCHIVES_DIR/2025/$file"
    echo "14/07/2025,10H32,B,24042551110457205101005323,1" >> "$ARCHIVES_DIR/2025/$file"
done

# Permissions correctes
chown -R prod:prod "$ARCHIVES_DIR/2025"
chmod -R g+r "$ARCHIVES_DIR/2025"

test_result "OK" "Fichiers de test créés pour S28 2025"

# Créer aussi quelques fichiers pour 2024
mkdir -p "$ARCHIVES_DIR/2024"
for week in 50 51 52; do
    for machine in 509 511 RPDT; do
        file="S${week}_2024_${machine}.csv"
        echo "date,heure,équipe,codebarre,résultat" > "$ARCHIVES_DIR/2024/$file"
        echo "20/12/2024,14H15,C,24042551110457205101005400,1" >> "$ARCHIVES_DIR/2024/$file"
    done
done

chown -R prod:prod "$ARCHIVES_DIR/2024"
chmod -R g+r "$ARCHIVES_DIR/2024"

test_result "OK" "Fichiers de test créés pour S50-S52 2024"

echo ""

# ===============================================================================
# TEST 6 : TESTS AVEC DONNÉES
# ===============================================================================

test_section "🎯 TESTS AVEC DONNÉES DE TEST"

# Re-tester archives-list.php avec des données
echo "   🔍 Test archives-list.php avec données..."
HTTP_CODE=$(curl -s -o /tmp/archives_with_data.json -w "%{http_code}" "http://localhost/archives-list.php")

if [ "$HTTP_CODE" = "200" ]; then
    CONTENT=$(cat /tmp/archives_with_data.json)
    if echo "$CONTENT" | jq -e '.["2025"]' >/dev/null 2>&1; then
        test_result "OK" "archives-list.php détecte les archives 2025"
    else
        test_result "KO" "archives-list.php ne détecte pas les archives 2025"
    fi
    
    if echo "$CONTENT" | jq -e '.["2024"]' >/dev/null 2>&1; then
        test_result "OK" "archives-list.php détecte les archives 2024"
    else
        test_result "KO" "archives-list.php ne détecte pas les archives 2024"
    fi
    
    echo "   📊 Contenu retourné:"
    echo "$CONTENT" | jq .
else
    test_result "KO" "archives-list.php erreur avec données"
fi

# Test téléchargement
echo ""
echo "   🔍 Test téléchargement S28 2025..."
HTTP_CODE=$(curl -s -o /tmp/test_download.zip -w "%{http_code}" "http://localhost/download-archive.php?year=2025&week=28")

if [ "$HTTP_CODE" = "200" ]; then
    test_result "OK" "Téléchargement S28 2025 réussi"
    
    # Vérifier que c'est bien un ZIP
    if file /tmp/test_download.zip | grep -q "Zip archive"; then
        test_result "OK" "Fichier téléchargé est bien un ZIP"
        
        # Lister le contenu du ZIP
        echo "   📦 Contenu du ZIP:"
        unzip -l /tmp/test_download.zip | grep "\.csv" | awk '{print "      - " $4}'
        
        # Compter les fichiers
        FILE_COUNT=$(unzip -l /tmp/test_download.zip | grep "\.csv" | wc -l)
        test_result "OK" "ZIP contient $FILE_COUNT fichiers CSV"
    else
        test_result "KO" "Fichier téléchargé n'est pas un ZIP valide"
    fi
else
    test_result "KO" "Téléchargement S28 2025 erreur HTTP $HTTP_CODE"
fi

# Test téléchargement semaine inexistante
echo ""
echo "   🔍 Test téléchargement semaine inexistante..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/download-archive.php?year=2025&week=99")

if [ "$HTTP_CODE" = "404" ]; then
    test_result "OK" "Téléchargement semaine inexistante retourne 404 (correct)"
else
    test_result "KO" "Téléchargement semaine inexistante retourne $HTTP_CODE (attendu: 404)"
fi

# Nettoyer
rm -f /tmp/archives_with_data.json /tmp/test_download.zip

echo ""

# ===============================================================================
# RÉSUMÉ FINAL
# ===============================================================================

echo "========================================================================"
echo "📊 RÉSUMÉ DU DIAGNOSTIC"
echo "========================================================================"
echo ""

if [ $TESTS_KO -eq 0 ]; then
    echo -e "${GREEN}🎉 TOUS LES TESTS SONT PASSÉS !${NC}"
    echo ""
    echo -e "${GREEN}✅ Le système de téléchargement fonctionne parfaitement${NC}"
    echo "   • archives-list.php opérationnel"
    echo "   • download-archive.php opérationnel"
    echo "   • Widget downloadbutton configuré"
    echo "   • Données de test créées et validées"
    echo ""
    echo "🧪 Vous pouvez maintenant tester le widget dans le dashboard !"
    echo "   Cliquez sur le bouton download, vous devriez voir:"
    echo "   • S28 2025 (données de test)"
    echo "   • S50, S51, S52 2024 (données de test)"
elif [ $TESTS_KO -eq 1 ]; then
    echo -e "${YELLOW}⚠️  QUELQUES PROBLÈMES DÉTECTÉS${NC}"
    echo ""
    echo "Tests réussis: $TESTS_OK/$TESTS_TOTAL"
    echo "Tests échoués: $TESTS_KO"
    echo ""
    echo "Consultez les détails ci-dessus pour corriger les problèmes."
else
    echo -e "${RED}❌ PROBLÈMES IMPORTANTS DÉTECTÉS${NC}"
    echo ""
    echo "Tests réussis: $TESTS_OK/$TESTS_TOTAL"
    echo "Tests échoués: $TESTS_KO"
    echo ""
    echo "Le système nécessite des corrections avant d'être utilisable."
fi

echo ""
echo "==============================================================="
echo "🔧 COMMANDES UTILES POUR DEBUG"
echo "==============================================================="
echo ""
echo "• Tester archives-list.php:"
echo "  curl http://localhost/archives-list.php | jq ."
echo ""
echo "• Tester téléchargement:"
echo "  curl -o test.zip 'http://localhost/download-archive.php?year=2025&week=28'"
echo ""
echo "• Vérifier logs Nginx:"
echo "  tail -f /var/log/nginx/maxlink-error.log"
echo ""
echo "• Vérifier permissions traçabilité:"
echo "  ls -la /home/prod/Documents/traçabilité/"
echo ""
echo "• Nettoyer les données de test:"
echo "  rm -rf /home/prod/Documents/traçabilité/Archives/202*"
echo ""