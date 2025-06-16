#!/bin/bash

# ===============================================================================
# MAXLINK - LANCEUR DE L'INTERFACE D'ADMINISTRATION SIMPLIFIÉE
# Script pour démarrer l'interface avec installation complète uniquement
# Version 3.0 - © 2025 WERIT. Tous droits réservés.
# ===============================================================================

# Détection du répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    clear
    echo "========================================================================"
    echo "  MaxLink™ Admin Panel - Erreur"
    echo "========================================================================"
    echo ""
    echo "◦ Ce script doit être exécuté avec des privilèges sudo."
    echo ""
    echo "  Usage: sudo bash $0"
    echo ""
    echo "========================================================================"
    exit 1
fi

# Header d'accueil
clear
echo "========================================================================"
echo "  MaxLink™ Admin Panel - Installation Complète"
echo "  © 2025 WERIT. Tous droits réservés."
echo "========================================================================"
echo ""
echo "  Version simplifiée avec installation complète uniquement"
echo ""

# Vérifications système
echo "◦ Vérifications système..."

# Vérifier Python3
if ! command -v python3 &> /dev/null; then
    echo "  ↦ Python3 non installé ✗"
    echo ""
    echo "Veuillez installer Python3 avant de continuer."
    echo ""
    exit 1
fi
echo "  ↦ Python3 disponible ✓"

# Vérifier l'interface
if [ ! -f "$SCRIPT_DIR/interface.py" ]; then
    echo "  ↦ Interface non trouvée ✗"
    echo ""
    echo "Fichier interface.py manquant dans: $SCRIPT_DIR"
    echo ""
    exit 1
fi
echo "  ↦ Interface trouvée ✓"

# Vérifier le script d'installation complète
if [ ! -f "$SCRIPT_DIR/scripts/install/full_install_install.sh" ]; then
    echo "  ↦ Script d'installation complète non trouvé ✗"
    echo ""
    echo "Fichier full_install_install.sh manquant"
    echo ""
    exit 1
fi
echo "  ↦ Script d'installation complète trouvé ✓"

# Créer les répertoires nécessaires
mkdir -p "$SCRIPT_DIR/logs/python" 2>/dev/null
mkdir -p "/var/lib/maxlink" 2>/dev/null

echo ""
echo "◦ Démarrage de l'interface simplifiée..."
echo "  ↦ Mode privilégié actif (root)"
echo "  ↦ Installation complète disponible"
echo "  ↦ Logs: $SCRIPT_DIR/logs/"
echo ""

# Permettre l'affichage X11 si nécessaire
if [ -n "$DISPLAY" ] && [ -n "$SUDO_USER" ]; then
    xhost +local: > /dev/null 2>&1 || true
fi

# Petit délai avant le lancement
echo "Lancement dans 3 secondes..."
sleep 3

# Lancer l'interface Python
cd "$SCRIPT_DIR"
python3 interface.py

# Code de retour
exit_code=$?

# Message de fin
echo ""
echo "========================================================================"
echo "  MaxLink™ Admin Panel - Session terminée"
echo "========================================================================"

exit $exit_code