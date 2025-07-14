#!/bin/bash
#
# Installation du widget Test Persist CSV
# Version 3.0 - Support traçabilité hebdomadaire avec archivage automatique
#

source "/opt/maxlink/scripts/_core/common_functions.sh"

WIDGET_NAME="testpersist"

# Vérifications préalables
echo "========================================================================"
echo "Installation du widget Test Persist CSV avec Traçabilité Hebdomadaire"
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
ARCHIVES_DIR="$STORAGE_DIR/Archives"

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

# Créer le répertoire d'archives
if [ ! -d "$ARCHIVES_DIR" ]; then
    mkdir -p "$ARCHIVES_DIR"
    log_info "Répertoire d'archives créé: $ARCHIVES_DIR"
fi

# Définir les permissions pour permettre à root (le service) d'écrire
# et à prod de lire/modifier via SSH
chown -R prod:prod "$STORAGE_DIR"
chmod 775 "$STORAGE_DIR"
chmod 775 "$ARCHIVES_DIR"
echo "  ↦ Répertoire principal: $STORAGE_DIR ✓"
echo "  ↦ Répertoire archives: $ARCHIVES_DIR ✓"
echo "  ↦ Propriétaire: prod:prod"
echo "  ↦ Permissions: 775 (lecture/écriture pour prod et root)"

# Gestion des anciens fichiers CSV (migration douce)
echo ""
echo "◦ Gestion de la migration vers la traçabilité hebdomadaire..."
OLD_CSV_FILES=("509.csv" "511.csv" "RPDT.csv")
MIGRATION_NEEDED=false

for csvfile in "${OLD_CSV_FILES[@]}"; do
    csv_filepath="$STORAGE_DIR/$csvfile"
    if [ -f "$csv_filepath" ]; then
        MIGRATION_NEEDED=true
        echo "  ↦ Ancien fichier CSV détecté: $csvfile"
    fi
done

if [ "$MIGRATION_NEEDED" = true ]; then
    echo ""
    echo "⚠️  MIGRATION AUTOMATIQUE VERS TRAÇABILITÉ HEBDOMADAIRE"
    echo ""
    echo "Des fichiers CSV de l'ancien système ont été détectés."
    echo "Ils vont être automatiquement archivés dans le nouveau système."
    echo ""
    echo "Structure avant migration:"
    echo "  • 509.csv, 511.csv, RPDT.csv (fichiers fixes)"
    echo ""
    echo "Structure après migration:"
    echo "  • S29_2025_509.csv, S29_2025_511.csv, S29_2025_RPDT.csv (semaine courante)"
    echo "  • Archives/2025/[anciens fichiers] (archivés automatiquement)"
    echo ""
    read -p "Continuer la migration automatique ? (o/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Oo]$ ]]; then
        echo "Installation annulée."
        exit 1
    fi
    
    # Calculer la semaine courante pour la migration
    CURRENT_YEAR=$(date +%Y)
    CURRENT_WEEK=$(date +%V)
    
    echo ""
    echo "◦ Migration des fichiers existants..."
    
    # Créer le répertoire d'archive pour l'année courante
    CURRENT_YEAR_ARCHIVE="$ARCHIVES_DIR/$CURRENT_YEAR"
    mkdir -p "$CURRENT_YEAR_ARCHIVE"
    chown prod:prod "$CURRENT_YEAR_ARCHIVE"
    chmod 775 "$CURRENT_YEAR_ARCHIVE"
    
    # Archiver les anciens fichiers CSV avec format de semaine
    for csvfile in "${OLD_CSV_FILES[@]}"; do
        csv_filepath="$STORAGE_DIR/$csvfile"
        if [ -f "$csv_filepath" ]; then
            # Déterminer le nouveau nom basé sur la machine
            if [ "$csvfile" = "509.csv" ]; then
                new_name="S${CURRENT_WEEK}_${CURRENT_YEAR}_509.csv"
            elif [ "$csvfile" = "511.csv" ]; then
                new_name="S${CURRENT_WEEK}_${CURRENT_YEAR}_511.csv"
            elif [ "$csvfile" = "RPDT.csv" ]; then
                new_name="S${CURRENT_WEEK}_${CURRENT_YEAR}_RPDT.csv"
            fi
            
            # Déplacer vers les archives
            archive_filepath="$CURRENT_YEAR_ARCHIVE/$new_name"
            mv "$csv_filepath" "$archive_filepath"
            chown prod:prod "$archive_filepath"
            chmod 664 "$archive_filepath"
            
            echo "  ↦ $csvfile → Archives/$CURRENT_YEAR/$new_name"
            log_info "Fichier migré: $csvfile → $new_name"
        fi
    done
    
    echo "  ↦ Migration terminée ✓"
fi

# Migration des anciens fichiers JSON (si présents)
echo ""
echo "◦ Nettoyage des anciens fichiers JSON..."
OLD_JSON_FILES=("509.json" "511.json" "998.json" "999.json")
JSON_FOUND=false

for jsonfile in "${OLD_JSON_FILES[@]}"; do
    json_filepath="$STORAGE_DIR/$jsonfile"
    if [ -f "$json_filepath" ]; then
        JSON_FOUND=true
        mv "$json_filepath" "$json_filepath.old"
        echo "  ↦ $jsonfile → $jsonfile.old"
    fi
done

if [ "$JSON_FOUND" = true ]; then
    echo "  ↦ Anciens fichiers JSON archivés avec extension .old"
else
    echo "  ↦ Aucun ancien fichier JSON trouvé"
fi

# Créer le répertoire pour l'année courante dans les archives
CURRENT_YEAR=$(date +%Y)
CURRENT_YEAR_ARCHIVE="$ARCHIVES_DIR/$CURRENT_YEAR"
if [ ! -d "$CURRENT_YEAR_ARCHIVE" ]; then
    mkdir -p "$CURRENT_YEAR_ARCHIVE"
    chown prod:prod "$CURRENT_YEAR_ARCHIVE"
    chmod 775 "$CURRENT_YEAR_ARCHIVE"
    echo ""
    echo "◦ Répertoire d'archive créé pour l'année $CURRENT_YEAR"
fi

# Utiliser l'installation standard du core
if widget_standard_install "$WIDGET_NAME"; then
    echo ""
    echo "========================================================================"
    echo "Installation terminée avec succès !"
    echo "========================================================================"
    echo ""
    echo "Widget Test Persist CSV avec Traçabilité Hebdomadaire v3.0 :"
    echo ""
    echo "◦ Topic écouté:"
    echo "  • SOUFFLAGE/ESP32/RTP (topic unique pour tous les ESP32)"
    echo ""
    echo "◦ Topics de confirmation:"
    echo "  • SOUFFLAGE/ESP32/RTP/CONFIRMED"
    echo ""
    echo "◦ Nouveau système de fichiers par semaine:"
    CURRENT_WEEK=$(date +%V)
    CURRENT_YEAR=$(date +%Y)
    echo "  • Semaine courante S$CURRENT_WEEK/$CURRENT_YEAR:"
    echo "    - Machine 509 → S${CURRENT_WEEK}_${CURRENT_YEAR}_509.csv"
    echo "    - Machine 511 → S${CURRENT_WEEK}_${CURRENT_YEAR}_511.csv"
    echo "    - Machines 998 & 999 → S${CURRENT_WEEK}_${CURRENT_YEAR}_RPDT.csv"
    echo ""
    echo "◦ Archivage automatique:"
    echo "  • À chaque nouvelle semaine, les fichiers précédents sont"
    echo "    automatiquement déplacés vers Archives/ANNÉE/"
    echo "  • Structure: $STORAGE_DIR/Archives/2025/S24_2025_509.csv"
    echo ""
    echo "◦ Fonctionnalités avancées:"
    echo "  • Détection automatique de changement de semaine"
    echo "  • Archivage transparent sans interruption de service"
    echo "  • Migration automatique des anciens fichiers"
    echo "  • API de téléchargement des archives (pour dashboard)"
    echo ""
    echo "◦ Format d'entrée: CSV (inchangé)"
    echo "  date,heure,équipe,codebarre,résultat"
    echo "  Exemple: 08/07/2025,14H46,B,24042551110457205101005321,1"
    echo ""
    echo "◦ Parsing automatique: (inchangé)"
    echo "  • Machine extraite des positions 7,8,9 du code-barres"
    echo "  • Routage automatique vers le bon fichier CSV de semaine"
    echo ""
    echo "◦ Accès SSH: Les fichiers sont directement accessibles"
    echo "  par l'utilisateur prod dans ~/Documents/traçabilité"
    echo "  • Fichiers courants dans le répertoire principal"
    echo "  • Archives organisées par année dans Archives/"
    echo ""
    echo "IMPORTANT: Les ESP32 n'ont AUCUNE modification à faire."
    echo "Le système est 100% compatible avec l'existant."
    echo ""
    
    log_success "Installation widget Test Persist CSV v3.0 terminée"
    exit 0
else
    echo ""
    echo "✗ Échec de l'installation"
    log_error "Installation échouée"
    exit 1
fi