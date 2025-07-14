#!/bin/bash

# ===============================================================================
# MAXLINK - MODULE DE GESTION DES PAQUETS (VERSION CORRIGÉE)
# Centralise le téléchargement et l'installation des paquets
# Nouvelles fonctions pour installation simultanée et vérification avancée
# ===============================================================================

# Vérifier que les variables sont chargées
if [ -z "$BASE_DIR" ]; then
    echo "ERREUR: Ce module doit être sourcé après variables.sh"
    exit 1
fi

# ===============================================================================
# CONFIGURATION
# ===============================================================================

# Répertoire de cache des paquets
PACKAGE_CACHE_DIR="/var/cache/maxlink/packages"
PACKAGE_LIST_FILE="$BASE_DIR/scripts/common/packages.list"
PACKAGE_METADATA_FILE="$PACKAGE_CACHE_DIR/metadata.json"

# Durée de validité du cache (7 jours)
CACHE_VALIDITY_DAYS=7
CACHE_VALIDITY_SECONDS=$((CACHE_VALIDITY_DAYS * 86400))

# ===============================================================================
# FONCTIONS PRINCIPALES
# ===============================================================================

# Initialiser le système de cache
init_package_cache() {
    log_info "Initialisation du cache des paquets"
    
    # Créer le répertoire de cache
    if ! mkdir -p "$PACKAGE_CACHE_DIR"; then
        log_error "Impossible de créer $PACKAGE_CACHE_DIR"
        return 1
    fi
    
    # Définir les permissions appropriées
    chmod 755 "$PACKAGE_CACHE_DIR"
    
    log_success "Cache initialisé: $PACKAGE_CACHE_DIR"
    return 0
}

# Vérifier si le cache est valide
is_cache_valid() {
    # Vérifier l'existence du fichier metadata
    if [ ! -f "$PACKAGE_METADATA_FILE" ]; then
        log_info "Pas de métadonnées de cache trouvées"
        return 1
    fi
    
    # Vérifier l'âge du cache
    local cache_timestamp=$(stat -c %Y "$PACKAGE_METADATA_FILE" 2>/dev/null || echo 0)
    local current_timestamp=$(date +%s)
    local cache_age=$((current_timestamp - cache_timestamp))
    
    if [ $cache_age -gt $CACHE_VALIDITY_SECONDS ]; then
        log_info "Cache obsolète (âge: $(($cache_age / 86400)) jours)"
        return 1
    fi
    
    log_info "Cache valide (âge: $(($cache_age / 86400)) jours)"
    return 0
}

# Lire la liste des paquets requis
get_required_packages() {
    if [ ! -f "$PACKAGE_LIST_FILE" ]; then
        log_error "Fichier de liste des paquets non trouvé: $PACKAGE_LIST_FILE"
        return 1
    fi
    
    # Lire et filtrer les commentaires et lignes vides
    grep -v '^#' "$PACKAGE_LIST_FILE" 2>/dev/null | grep -v '^$' || true
}

# Télécharger tous les paquets requis avec métadonnées enrichies
download_all_packages() {
    log_info "Téléchargement de tous les paquets requis"
    
    # Nettoyer l'ancien cache
    rm -rf "$PACKAGE_CACHE_DIR"/*
    
    # Créer les métadonnées enrichies
    cat > "$PACKAGE_METADATA_FILE" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "version": "$MAXLINK_VERSION",
    "packages": [],
    "categories": {},
    "dependency_order": {}
}
EOF
    
    # Mettre à jour les listes de paquets
    log_info "Mise à jour des listes de paquets APT"
    if ! apt-get update -qq; then
        log_error "Échec de la mise à jour APT"
        return 1
    fi
    
    # IMPORTANT: Se déplacer dans le répertoire de cache
    local CURRENT_DIR=$(pwd)
    cd "$PACKAGE_CACHE_DIR" || {
        log_error "Impossible d'accéder au répertoire de cache: $PACKAGE_CACHE_DIR"
        return 1
    }
    
    # Télécharger chaque paquet
    local packages=$(get_required_packages)
    
    # Compter le nombre total de paquets
    local total_packages=0
    while IFS=: read -r category package_list; do
        [ -z "$package_list" ] && continue
        for package in $package_list; do
            [ -z "$package" ] && continue
            ((total_packages++))
        done
    done <<< "$packages"
    
    # Si le comptage retourne 0, utiliser une méthode alternative
    if [ $total_packages -eq 0 ]; then
        total_packages=$(echo "$packages" | cut -d: -f2 | wc -w)
    fi
    
    local current_package=0
    local failed_packages=""
    
    echo "$packages" | while IFS=: read -r category package_list; do
        [ -z "$package_list" ] && continue
        
        for package in $package_list; do
            [ -z "$package" ] && continue
            
            ((current_package++))
            local progress=$((current_package * 100 / total_packages))
            
            echo "◦ Téléchargement [$current_package/$total_packages]: $package"
            log_info "Téléchargement du paquet: $package (catégorie: $category)"
            
            # Télécharger le paquet et ses dépendances avec résolution récursive améliorée
            if apt-get download \
               $(apt-cache depends --recurse --no-recommends --no-suggests \
               --no-conflicts --no-breaks --no-replaces --no-enhances \
               $package 2>/dev/null | grep "^\w" | sort -u) \
               >/dev/null 2>&1; then
                echo "  ↦ $package téléchargé ✓"
                log_success "Paquet téléchargé: $package"
                
                # Mettre à jour les métadonnées enrichies
                python3 -c "
import json
with open('$PACKAGE_METADATA_FILE', 'r') as f:
    data = json.load(f)
data['packages'].append('$package')
if '$category' not in data['categories']:
    data['categories']['$category'] = []
data['categories']['$category'].append('$package')
data['dependency_order']['$package'] = $current_package
with open('$PACKAGE_METADATA_FILE', 'w') as f:
    json.dump(data, f, indent=2)
"
            else
                echo "  ↦ $package échec ✗"
                log_error "Échec du téléchargement: $package"
                failed_packages="$failed_packages $package"
            fi
        done
    done
    
    # IMPORTANT: Retourner au répertoire d'origine
    cd "$CURRENT_DIR"
    
    # Résumé
    local downloaded_count=$(ls -1 "$PACKAGE_CACHE_DIR"/*.deb 2>/dev/null | wc -l)
    echo ""
    echo "◦ Téléchargement terminé"
    echo "  ↦ Paquets téléchargés: $downloaded_count"
    log_info "Total paquets téléchargés: $downloaded_count"
    
    if [ -n "$failed_packages" ]; then
        echo "  ↦ Paquets échoués:$failed_packages"
        log_warn "Paquets non téléchargés:$failed_packages"
        return 1
    fi
    
    return 0
}

# ===============================================================================
# NOUVELLES FONCTIONS CORRIGÉES
# ===============================================================================

# Vérifier que tous les paquets d'une catégorie sont présents dans le cache
verify_category_cache_complete() {
    local category="$1"
    
    log_info "Vérification complète du cache pour la catégorie: $category"
    
    # Extraire les paquets requis
    local packages=$(grep "^$category:" "$PACKAGE_LIST_FILE" 2>/dev/null | cut -d: -f2)
    
    if [ -z "$packages" ]; then
        log_warn "Aucun paquet défini pour la catégorie: $category"
        return 0
    fi
    
    local missing_packages=""
    local found_packages=""
    local total_found=0
    local total_required=0
    
    echo "  ↦ Vérification de la présence de tous les paquets $category..."
    
    for package in $packages; do
        ((total_required++))
        local deb_files=$(find "$PACKAGE_CACHE_DIR" -name "${package}*.deb" 2>/dev/null)
        if [ -z "$deb_files" ]; then
            missing_packages="$missing_packages $package"
            echo "    ✗ Manquant: $package"
            log_error "Paquet manquant dans cache: $package"
        else
            found_packages="$found_packages $package"
            ((total_found++))
            echo "    ✓ Présent: $package ($(echo $deb_files | wc -w) fichier(s))"
            log_success "Paquet trouvé dans cache: $package"
        fi
    done
    
    echo "  ↦ Résumé: $total_found/$total_required paquets présents"
    
    if [ -n "$missing_packages" ]; then
        echo "  ↦ ❌ Paquets manquants:$missing_packages"
        log_error "Cache incomplet pour $category:$missing_packages"
        return 1
    else
        echo "  ↦ ✅ Tous les paquets $category sont présents dans le cache"
        log_success "Cache complet pour $category"
        return 0
    fi
}

# Installer tous les paquets d'une catégorie simultanément pour éviter les conflits de dépendances
install_packages_by_category_simultaneously() {
    local category="$1"
    
    log_info "Installation simultanée des paquets de la catégorie: $category"
    
    # Extraire les paquets de la catégorie
    local packages=$(grep "^$category:" "$PACKAGE_LIST_FILE" 2>/dev/null | cut -d: -f2)
    
    if [ -z "$packages" ]; then
        log_warn "Aucun paquet trouvé pour la catégorie: $category"
        return 0
    fi
    
    # Collecter TOUS les fichiers .deb de la catégorie
    local all_deb_files=""
    local missing_packages=""
    local found_count=0
    
    echo "  ↦ Collecte des fichiers .deb pour installation simultanée..."
    
    for package in $packages; do
        local deb_files=$(find "$PACKAGE_CACHE_DIR" -name "${package}*.deb" 2>/dev/null)
        if [ -z "$deb_files" ]; then
            missing_packages="$missing_packages $package"
            echo "    ✗ Fichier manquant: $package"
        else
            all_deb_files="$all_deb_files $deb_files"
            ((found_count++))
            echo "    ✓ Fichier trouvé: $package"
        fi
    done
    
    # Vérifier que tous les paquets sont présents
    if [ -n "$missing_packages" ]; then
        echo "  ↦ ❌ Impossible d'installer: paquets manquants:$missing_packages"
        log_error "Paquets manquants dans le cache:$missing_packages"
        return 1
    fi
    
    echo "  ↦ Fichiers collectés: $found_count paquets prêts"
    log_info "Fichiers .deb collectés pour installation: $all_deb_files"
    
    # Installation simultanée avec dpkg
    echo "  ↦ Installation simultanée de tous les paquets $category..."
    log_info "Lancement installation dpkg simultanée"
    
    # Capturer la sortie détaillée de dpkg
    local dpkg_output
    local dpkg_temp_log="/tmp/dpkg_install_$category.log"
    
    # Exécuter dpkg avec capture détaillée
    dpkg_output=$(dpkg -i $all_deb_files 2>&1 | tee "$dpkg_temp_log")
    local dpkg_exit=$?
    
    if [ $dpkg_exit -eq 0 ]; then
        echo "    ✓ Tous les paquets $category installés simultanément"
        log_success "Installation simultanée réussie pour $category"
        rm -f "$dpkg_temp_log"
        return 0
    else
        echo "    ⚠ Erreur dpkg détectée - tentative de correction..."
        log_warn "Erreur dpkg pour $category (code: $dpkg_exit)"
        log_warn "Détails dpkg: $dpkg_output"
        
        # Correction hors ligne uniquement avec dpkg --configure
        echo "    ↦ Configuration des paquets partiellement installés..."
        local configure_output
        configure_output=$(dpkg --configure -a 2>&1)
        local configure_exit=$?
        
        if [ $configure_exit -eq 0 ]; then
            echo "    ✓ Dépendances corrigées - installation réussie"
            log_success "Correction réussie pour $category"
            rm -f "$dpkg_temp_log"
            return 0
        else
            echo "    ✗ Échec de la correction des dépendances"
            log_error "Échec final pour $category"
            log_error "Détails correction: $configure_output"
            
            # Garder les logs pour diagnostic
            if [ -f "$dpkg_temp_log" ]; then
                echo "    ↦ Logs détaillés sauvegardés: $dpkg_temp_log"
                log_error "Logs dpkg complets disponibles: $dpkg_temp_log"
            fi
            return 1
        fi
    fi
}

# Installer un paquet depuis le cache avec diagnostics détaillés
install_package_from_cache() {
    local package_name="$1"
    
    log_info "Installation du paquet depuis le cache: $package_name"
    
    # Vérifier si le paquet est dans le cache
    local deb_files=$(find "$PACKAGE_CACHE_DIR" -name "${package_name}*.deb" 2>/dev/null)
    
    if [ -z "$deb_files" ]; then
        log_error "Paquet non trouvé dans le cache: $package_name"
        return 1
    fi
    
    # Diagnostic pré-installation
    local file_count=$(echo $deb_files | wc -w)
    log_info "Fichiers .deb trouvés pour $package_name: $file_count fichier(s)"
    log_info "Fichiers: $deb_files"
    
    # Installer avec dpkg et capturer détails
    local dpkg_output
    local dpkg_temp_log="/tmp/dpkg_single_$package_name.log"
    
    dpkg_output=$(dpkg -i $deb_files 2>&1 | tee "$dpkg_temp_log")
    local dpkg_exit=$?
    
    if [ $dpkg_exit -eq 0 ]; then
        log_success "Paquet installé depuis le cache: $package_name"
        rm -f "$dpkg_temp_log"
        return 0
    else
        # Logs détaillés de l'erreur
        log_error "Échec dpkg pour $package_name (code de sortie: $dpkg_exit)"
        log_error "Sortie dpkg: $dpkg_output"
        
        # Essayer de corriger les dépendances hors ligne
        echo "  ↦ Tentative de correction des dépendances pour $package_name"
        log_warn "Tentative de correction des dépendances pour $package_name"
        
        local fix_output
        fix_output=$(dpkg --configure -a 2>&1)
        local fix_exit=$?
        
        if [ $fix_exit -eq 0 ]; then
            log_success "Correction réussie pour $package_name"
            rm -f "$dpkg_temp_log"
            return 0
        else
            log_error "Échec de la correction pour $package_name: $fix_output"
            echo "  ↦ Logs détaillés disponibles: $dpkg_temp_log"
            return 1
        fi
    fi
}

# ===============================================================================
# FONCTIONS EXISTANTES (maintenues pour compatibilité)
# ===============================================================================

# Installer tous les paquets d'une catégorie (méthode séquentielle - gardée pour compatibilité)
install_packages_by_category() {
    local category="$1"
    
    log_info "Installation des paquets de la catégorie: $category"
    
    # Extraire les paquets de la catégorie
    local packages=$(grep "^$category:" "$PACKAGE_LIST_FILE" 2>/dev/null | cut -d: -f2)
    
    if [ -z "$packages" ]; then
        log_warn "Aucun paquet trouvé pour la catégorie: $category"
        return 0
    fi
    
    # Variable pour suivre les échecs
    local any_failed=0
    
    # Installer chaque paquet
    for package in $packages; do
        echo "  ↦ Installation de $package..."
        if install_package_from_cache "$package"; then
            echo "    ✓ $package installé"
        else
            echo "    ✗ Échec pour $package"
            log_error "Échec d'installation: $package"
            any_failed=1
        fi
    done
    
    # Retourner 1 si au moins un paquet a échoué
    return $any_failed
}

# Nettoyer le cache
clean_package_cache() {
    log_info "Nettoyage du cache des paquets"
    
    if [ -d "$PACKAGE_CACHE_DIR" ]; then
        local size=$(du -sh "$PACKAGE_CACHE_DIR" 2>/dev/null | cut -f1)
        rm -rf "$PACKAGE_CACHE_DIR"/*
        echo "  ↦ Cache nettoyé ($size libérés)"
        log_success "Cache nettoyé: $size libérés"
    fi
    
    return 0
}

# Obtenir des statistiques sur le cache
get_cache_stats() {
    if [ ! -d "$PACKAGE_CACHE_DIR" ]; then
        echo "Cache non initialisé"
        return 1
    fi
    
    local total_size=$(du -sh "$PACKAGE_CACHE_DIR" 2>/dev/null | cut -f1)
    local deb_count=$(ls -1 "$PACKAGE_CACHE_DIR"/*.deb 2>/dev/null | wc -l)
    local cache_age="N/A"
    
    if [ -f "$PACKAGE_METADATA_FILE" ]; then
        local cache_timestamp=$(stat -c %Y "$PACKAGE_METADATA_FILE")
        local current_timestamp=$(date +%s)
        cache_age="$((($current_timestamp - $cache_timestamp) / 86400)) jours"
    fi
    
    echo "=== Statistiques du cache ==="
    echo "Emplacement : $PACKAGE_CACHE_DIR"
    echo "Taille      : $total_size"
    echo "Paquets     : $deb_count"
    echo "Âge         : $cache_age"
    echo "=========================="
}

# ===============================================================================
# EXPORT DES FONCTIONS
# ===============================================================================

export -f init_package_cache
export -f is_cache_valid
export -f get_required_packages
export -f download_all_packages
export -f verify_category_cache_complete
export -f install_packages_by_category_simultaneously
export -f install_package_from_cache
export -f install_packages_by_category
export -f clean_package_cache
export -f get_cache_stats