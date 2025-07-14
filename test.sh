#!/bin/bash
#
# Test rapide du service php_archives après correction
# Valide que le script d'installation peut fonctionner
#

echo "========================================================================"
echo "🧪 TEST RAPIDE SERVICE PHP_ARCHIVES APRÈS CORRECTION"
echo "========================================================================"
echo ""

# Vérifier privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Ce script doit être exécuté en tant que root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"

# Charger les fonctions communes pour tester
if [ -f "scripts/common/variables.sh" ]; then
    source scripts/common/variables.sh
    echo "✅ variables.sh chargé"
else
    echo "❌ variables.sh non trouvé"
    exit 1
fi

if [ -f "scripts/common/logging.sh" ]; then
    source scripts/common/logging.sh
    echo "✅ logging.sh chargé"
else
    echo "❌ logging.sh non trouvé"
    exit 1
fi

if [ -f "scripts/common/packages.sh" ]; then
    source scripts/common/packages.sh
    echo "✅ packages.sh chargé"
else
    echo "❌ packages.sh non trouvé"
    exit 1
fi

echo ""
echo "🔍 TESTS DE VALIDATION :"

# Test 1 : Vérifier que php_archives est dans SERVICES_LIST
echo -n "• Service php_archives dans SERVICES_LIST : "
if printf '%s\n' "${SERVICES_LIST[@]}" | grep -q "php_archives"; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

# Test 2 : Vérifier que le dossier web_files existe
echo -n "• Dossier web_files/ présent : "
if [ -d "$BASE_DIR/web_files" ]; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

# Test 3 : Vérifier archives-list.php
echo -n "• Fichier archives-list.php présent : "
if [ -f "$BASE_DIR/web_files/archives-list.php" ]; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

# Test 4 : Vérifier download-archive.php
echo -n "• Fichier download-archive.php présent : "
if [ -f "$BASE_DIR/web_files/download-archive.php" ]; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

# Test 5 : Vérifier syntaxe du script d'installation
echo -n "• Script php_archives_install.sh syntaxe : "
if [ -f "scripts/install/php_archives_install.sh" ]; then
    if bash -n scripts/install/php_archives_install.sh 2>/dev/null; then
        echo "✅ VALIDE"
    else
        echo "❌ ERREUR DE SYNTAXE"
    fi
else
    echo "❌ FICHIER MANQUANT"
fi

# Test 6 : Vérifier que nginx est installé (prérequis)
echo -n "• Nginx installé (prérequis) : "
if command -v nginx >/dev/null 2>&1; then
    echo "✅ OUI"
else
    echo "❌ NON (installer d'abord nginx_install.sh)"
fi

# Test 7 : Vérifier que packages.list contient php
echo -n "• Section php dans packages.list : "
if [ -f "scripts/common/packages.list" ]; then
    if grep -q "^php:" scripts/common/packages.list; then
        echo "✅ OUI"
    else
        echo "❌ NON (ajouter section php)"
    fi
else
    echo "❌ FICHIER MANQUANT"
fi

echo ""
echo "========================================================================"
echo "💡 PROCHAINES ÉTAPES :"
echo ""
echo "Si tous les tests sont ✅ :"
echo "1. Tester l'installation : sudo scripts/install/php_archives_install.sh"
echo "2. Vérifier le statut : cat /var/lib/maxlink/services_status.json"
echo "3. Tester les URLs :"
echo "   curl http://localhost/archives-list.php"
echo "   curl http://localhost/download-archive.php"
echo ""
echo "Si il y a des ❌ :"
echo "• Corriger les problèmes identifiés"
echo "• Relancer ce test jusqu'à avoir tout en ✅"
echo ""