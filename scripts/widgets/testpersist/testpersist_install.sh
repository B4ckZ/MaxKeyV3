#!/bin/bash
#
# Installation du widget Test Persist CSV
# Version 2.0 - Support fichiers CSV sans en-têtes
#

source "/opt/maxlink/scripts/_core/common_functions.sh"

WIDGET_NAME="testpersist"

# Vérifications préalables
echo "========================================================================"
echo "Installation du widget Test Persist CSV"
echo "========================================================================"
echo ""
echo "◦ Vérification des prérequis..."

# Vérifier que le broker MQTT est actif
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

# Créer les fichiers CSV vides s'ils n'existent pas
echo ""
echo "◦ Initialisation des fichiers CSV..."
CSV_FILES=("509.csv" "511.csv" "RPDT.csv")

for csvfile in "${CSV_FILES[@]}"; do
    filepath="$STORAGE_DIR/$csvfile"
    if [ ! -f "$filepath" ]; then
        touch "$filepath"
        chown prod:prod "$filepath"
        chmod 664 "$filepath"
        echo "  ↦ Fichier créé: $csvfile"
        log_info "Fichier CSV créé: $filepath"
    else
        echo "  ↦ Fichier existant: $csvfile"
        # S'assurer que les permissions sont correctes même pour les fichiers existants
        chown prod:prod "$filepath"
        chmod 664 "$filepath"
    fi
done

# Migration des anciens fichiers JSON (si présents)
echo ""
echo "◦ Vérification de la migration JSON → CSV..."
OLD_JSON_FILES=("509.json" "511.json" "998.json" "999.json")
MIGRATION_NEEDED=false

for jsonfile in "${OLD_JSON_FILES[@]}"; do
    json_filepath="$STORAGE_DIR/$jsonfile"
    if [ -f "$json_filepath" ]; then
        MIGRATION_NEEDED=true
        echo "  ↦ Ancien fichier JSON détecté: $jsonfile"
    fi
done

if [ "$MIGRATION_NEEDED" = true ]; then
    echo ""
    echo "⚠️  ATTENTION: Anciens fichiers JSON détectés!"
    echo "   Vous devrez peut-être migrer les données manuellement."
    echo "   Les anciens fichiers seront renommés avec l'extension .old"
    echo ""
    read -p "Continuer l'installation? (o/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Oo]$ ]]; then
        echo "Installation annulée."
        exit 1
    fi
    
    # Renommer les anciens fichiers JSON
    for jsonfile in "${OLD_JSON_FILES[@]}"; do
        json_filepath="$STORAGE_DIR/$jsonfile"
        if [ -f "$json_filepath" ]; then
            mv "$json_filepath" "$json_filepath.old"
            echo "  ↦ $jsonfile → $jsonfile.old"
        fi
    done
fi

# Utiliser l'installation standard du core
if widget_standard_install "$WIDGET_NAME"; then
    echo ""
    echo "========================================================================"
    echo "Installation terminée avec succès !"
    echo "========================================================================"
    echo ""
    echo "Le widget collecte et persiste les résultats de tests CSV :"
    echo ""
    echo "◦ Topic écouté:"
    echo "  • SOUFFLAGE/ESP32/RTP (topic unique pour tous les ESP32)"
    echo ""
    echo "◦ Topics de confirmation:"
    echo "  • SOUFFLAGE/[machine]/ESP32/result/confirmed"
    echo ""
    echo "◦ Fichiers de stockage CSV (sans en-têtes):"
    echo "  • Machine 509 → $STORAGE_DIR/509.csv"
    echo "  • Machine 511 → $STORAGE_DIR/511.csv"
    echo "  • Machines 998 & 999 → $STORAGE_DIR/RPDT.csv"
    echo ""
    echo "◦ Format d'entrée: CSV"
    echo "  date,heure,équipe,codebarre,résultat"
    echo "  Exemple: 08/07/2025,14H46,B,24042551110457205101005321,1"
    echo ""
    echo "◦ Parsing automatique:"
    echo "  • Machine extraite des positions 7,8,9 du code-barres"
    echo "  • Routage automatique vers le bon fichier CSV"
    echo ""
    echo "◦ Accès SSH: Les fichiers sont directement accessibles"
    echo "  par l'utilisateur prod dans ~/Documents/traçabilité"
    echo "  Import direct possible dans Excel (pas d'en-têtes)"
    echo ""
    echo "IMPORTANT: Le widget mqttlogs509511 affichera maintenant"
    echo "uniquement les résultats confirmés (après persistance CSV)"
    echo ""
    
    log_success "Installation widget Test Persist CSV terminée"
    exit 0
else
    echo ""
    echo "✗ Échec de l'installation"
    log_error "Installation échouée"
    exit 1
fi