#!/bin/bash

# ===============================================================================
# WIDGET TEST PERSIST - INSTALLATION
# Service de persistance des résultats de tests de pression
# Version utilisant /home/prod/Documents pour éviter les conflits de permissions
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIDGET_DIR="$SCRIPT_DIR"
WIDGETS_DIR="$(dirname "$WIDGET_DIR")"
SCRIPTS_DIR="$(dirname "$WIDGETS_DIR")"
BASE_DIR="$(dirname "$SCRIPTS_DIR")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"
source "$BASE_DIR/scripts/widgets/_core/widget_common.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Installation widget Test Persist" "widgets"

WIDGET_NAME="testpersist"

# ===============================================================================
# VÉRIFICATIONS SPÉCIFIQUES
# ===============================================================================

check_mqtt_broker() {
    log_info "Vérification du broker MQTT"
    
    if ! systemctl is-active --quiet mosquitto; then
        log_error "Mosquitto n'est pas actif"
        return 1
    fi
    
    # Test de connexion avec les bonnes credentials
    if mosquitto_pub -h localhost -p 1883 -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/widget/install" -m "test" 2>/dev/null; then
        log_success "Connexion MQTT fonctionnelle"
        return 0
    else
        log_error "Impossible de se connecter au broker MQTT"
        return 1
    fi
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION WIDGET TEST PERSIST =========="

echo ""
echo "========================================================================"
echo "Installation du widget Test Results Persistence"
echo "========================================================================"
echo ""

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "  ↦ Ce script doit être exécuté avec des privilèges root ✗"
    log_error "Privilèges root requis"
    exit 1
fi

# Vérifier MQTT
echo "◦ Vérification du broker MQTT..."
if ! check_mqtt_broker; then
    echo "  ↦ Le broker MQTT doit être installé et actif ✗"
    echo ""
    echo "Veuillez d'abord installer MQTT avec mqtt_install.sh"
    exit 1
fi
echo "  ↦ Broker MQTT actif ✓"

# Créer le répertoire de stockage des données dans le home de prod
STORAGE_DIR="/home/prod/Documents/traçabilité"
echo ""
echo "◦ Préparation du répertoire de stockage..."

# Créer le répertoire Documents s'il n'existe pas
if [ ! -d "/home/prod/Documents" ]; then
    mkdir -p "/home/prod/Documents"
    chown prod:prod "/home/prod/Documents"
    chmod 755 "/home/prod/Documents"
    log_info "Répertoire Documents créé"
fi

# Créer le répertoire de traçabilité
if [ ! -d "$STORAGE_DIR" ]; then
    mkdir -p "$STORAGE_DIR"
    log_info "Répertoire créé: $STORAGE_DIR"
fi

# Définir les permissions pour permettre à root (le service) d'écrire
# et à prod de lire/modifier via SSH
chown prod:prod "$STORAGE_DIR"
chmod 775 "$STORAGE_DIR"
echo "  ↦ Répertoire: $STORAGE_DIR ✓"
echo "  ↦ Propriétaire: prod:prod"
echo "  ↦ Permissions: 775 (lecture/écriture pour prod et root)"

# Créer les fichiers JSON vides s'ils n'existent pas
echo ""
echo "◦ Initialisation des fichiers de données..."
for machine in "509" "511" "998" "999"; do
    filepath="$STORAGE_DIR/${machine}.json"
    if [ ! -f "$filepath" ]; then
        touch "$filepath"
        chown prod:prod "$filepath"
        chmod 664 "$filepath"
        echo "  ↦ Fichier créé: ${machine}.json"
        log_info "Fichier créé: $filepath"
    else
        echo "  ↦ Fichier existant: ${machine}.json"
        # S'assurer que les permissions sont correctes même pour les fichiers existants
        chown prod:prod "$filepath"
        chmod 664 "$filepath"
    fi
done

# Utiliser l'installation standard du core
if widget_standard_install "$WIDGET_NAME"; then
    echo ""
    echo "========================================================================"
    echo "Installation terminée avec succès !"
    echo "========================================================================"
    echo ""
    echo "Le widget collecte et persiste les résultats de tests :"
    echo ""
    echo "◦ Topics écoutés:"
    echo "  • SOUFFLAGE/509/ESP32/result"
    echo "  • SOUFFLAGE/511/ESP32/result"
    echo "  • SOUFFLAGE/998/ESP32/result"
    echo "  • SOUFFLAGE/999/ESP32/result"
    echo ""
    echo "◦ Topics de confirmation:"
    echo "  • SOUFFLAGE/[machine]/ESP32/result/confirmed"
    echo ""
    echo "◦ Fichiers de stockage:"
    echo "  • Machine 509 → $STORAGE_DIR/509.json"
    echo "  • Machine 511 → $STORAGE_DIR/511.json"
    echo "  • Machine 998 → $STORAGE_DIR/998.json"
    echo "  • Machine 999 → $STORAGE_DIR/999.json"
    echo ""
    echo "◦ Format: NDJSON (une ligne JSON par résultat)"
    echo ""
    echo "◦ Accès SSH: Les fichiers sont directement accessibles"
    echo "  par l'utilisateur prod dans ~/Documents/traçabilité"
    echo ""
    echo "IMPORTANT: Le widget mqttlogs509511 affichera maintenant"
    echo "uniquement les résultats confirmés (après persistance)"
    echo ""
    
    log_success "Installation widget Test Persist terminée"
    exit 0
else
    echo ""
    echo "✗ Échec de l'installation"
    log_error "Installation échouée"
    exit 1
fi