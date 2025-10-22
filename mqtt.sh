#!/bin/bash

# ===============================================================================
# DIAGNOSTIC MOSQUITTO - Déboguer libwebsockets et dépendances
# Pour Debian 13 Trixie
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fichier de rapport
REPORT_FILE="/tmp/mosquitto_diagnostic_$(date +%Y%m%d_%H%M%S).txt"

# ===============================================================================
# FONCTIONS D'AFFICHAGE
# ===============================================================================

log_section() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "$1" >> "$REPORT_FILE"
    echo "════════════════════════════════════════════════════════════" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
    echo "✓ $1" >> "$REPORT_FILE"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
    echo "✗ $1" >> "$REPORT_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    echo "⚠ $1" >> "$REPORT_FILE"
}

log_info() {
    echo "  $1"
    echo "  $1" >> "$REPORT_FILE"
}

log_command() {
    local cmd="$1"
    local description="$2"
    
    echo "  → $description"
    echo "  → Commande: $cmd" >> "$REPORT_FILE"
    
    local output=$(eval "$cmd" 2>&1)
    echo "$output"
    echo "$output" >> "$REPORT_FILE"
}

# ===============================================================================
# VÉRIFICATIONS PRÉLIMINAIRES
# ===============================================================================

initialize() {
    echo -e "${BLUE}Initialisation du diagnostic...${NC}"
    
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Ce script doit être exécuté en tant que root${NC}"
        exit 1
    fi
    
    # Créer le fichier de rapport
    touch "$REPORT_FILE"
    
    echo -e "${GREEN}Fichier de rapport: $REPORT_FILE${NC}"
    echo "Diagnostic Mosquitto - Debian 13 Trixie" > "$REPORT_FILE"
    echo "Généré le: $(date)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
}

# ===============================================================================
# SECTION 1 : INFORMATION SYSTÈME
# ===============================================================================

check_system_info() {
    log_section "1. INFORMATION SYSTÈME"
    
    log_info "OS:"
    log_command "cat /etc/os-release | grep -E '(PRETTY_NAME|VERSION)'" "Version du système"
    
    log_info "Architecture:"
    log_command "uname -m" "Architecture processeur"
    
    log_info "Kernel:"
    log_command "uname -r" "Version du kernel"
    
    log_info "Mémoire disponible:"
    log_command "free -h | head -2" "Mémoire"
    
    log_info "Espace disque:"
    log_command "df -h / | tail -1" "Espace disque racine"
}

# ===============================================================================
# SECTION 2 : RECHERCHE DE LIBWEBSOCKETS
# ===============================================================================

check_libwebsockets() {
    log_section "2. RECHERCHE LIBWEBSOCKETS"
    
    echo "Recherche de toutes les versions de libwebsockets disponibles..."
    echo "" >> "$REPORT_FILE"
    
    # Vérifier les versions installées
    log_info "Packages libwebsockets installés:"
    local installed=$(dpkg -l | grep -i libwebsockets)
    
    if [ -z "$installed" ]; then
        log_warning "Aucun package libwebsockets n'est installé"
    else
        echo "$installed" | while read line; do
            log_info "$line"
        done
    fi
    
    # Vérifier les fichiers .so
    log_info "Fichiers .so de libwebsockets:"
    local so_files=$(find /usr -name "libwebsockets.so*" 2>/dev/null)
    
    if [ -z "$so_files" ]; then
        log_error "AUCUN fichier libwebsockets.so trouvé!"
    else
        echo "$so_files" | while read file; do
            log_success "Trouvé: $file"
            
            # Vérifier les symboles
            if file "$file" | grep -q "ELF"; then
                local version=$(strings "$file" 2>/dev/null | grep "^libwebsockets" | head -1)
                [ -n "$version" ] && log_info "  Version trouvée: $version"
            fi
        done
    fi
    
    # Vérifier dans le cache ldconfig
    log_info "Vérification du cache ldconfig:"
    ldconfig -p | grep libwebsockets >> "$REPORT_FILE"
    local ldconfig_result=$(ldconfig -p | grep libwebsockets)
    
    if [ -z "$ldconfig_result" ]; then
        log_error "libwebsockets NOT dans le cache ldconfig"
    else
        echo "$ldconfig_result" | while read line; do
            log_info "$line"
        done
    fi
    
    # Vérifier les versions disponibles dans apt
    log_info "Versions disponibles dans apt:"
    log_command "apt-cache search libwebsockets" "Packages disponibles"
    
    # Vérifier la version actuelle de libwebsockets
    log_info "Version recommandée pour Debian 13:"
    log_command "apt-cache policy libwebsockets" "Politique libwebsockets"
}

# ===============================================================================
# SECTION 3 : MOSQUITTO - INSTALLATION ET VERSIONS
# ===============================================================================

check_mosquitto_installation() {
    log_section "3. MOSQUITTO - INSTALLATION ET VERSIONS"
    
    log_info "Status du package mosquitto:"
    log_command "dpkg -l | grep mosquitto" "Packages mosquitto installés"
    
    log_info "Empreinte digitale du binaire mosquitto:"
    if [ -f "/usr/sbin/mosquitto" ]; then
        log_success "Binaire mosquitto trouvé: /usr/sbin/mosquitto"
        
        log_command "file /usr/sbin/mosquitto" "Type du fichier"
        log_command "ldd /usr/sbin/mosquitto" "Dépendances directes du binaire"
        
        log_info "Librairies manquantes:"
        local missing=$(ldd /usr/sbin/mosquitto 2>&1 | grep "not found")
        if [ -z "$missing" ]; then
            log_success "Toutes les dépendances sont présentes"
        else
            log_error "Dépendances manquantes détectées:"
            echo "$missing" | while read line; do
                log_error "  $line"
            done
        fi
    else
        log_error "Binaire mosquitto NOT trouvé"
    fi
    
    log_info "Informations détaillées du package mosquitto:"
    log_command "apt-cache show mosquitto | head -20" "Infos package"
}

# ===============================================================================
# SECTION 4 : ANALYSE DES DÉPENDANCES MANQUANTES
# ===============================================================================

check_missing_deps() {
    log_section "4. ANALYSE DES DÉPENDANCES MANQUANTES"
    
    if [ ! -f "/usr/sbin/mosquitto" ]; then
        log_warning "Mosquitto non installé - impossible d'analyser"
        return
    fi
    
    log_info "Exécution de ldd avec analyse complète:"
    local ldd_output=$(ldd /usr/sbin/mosquitto 2>&1)
    echo "$ldd_output" >> "$REPORT_FILE"
    
    # Chercher spécifiquement libwebsockets.so.19
    log_info "Recherche de libwebsockets.so.19:"
    local has_19=$(echo "$ldd_output" | grep "libwebsockets.so.19")
    
    if [ -n "$has_19" ]; then
        log_warning "Le binaire cherche libwebsockets.so.19"
        
        # Vérifier si elle existe
        if [ -f "/usr/lib/arm-linux-gnueabihf/libwebsockets.so.19" ] || \
           [ -f "/usr/lib/aarch64-linux-gnu/libwebsockets.so.19" ] || \
           [ -f "/usr/lib/libwebsockets.so.19" ]; then
            log_success "libwebsockets.so.19 EXISTE"
        else
            log_error "libwebsockets.so.19 MANQUANTE"
            
            # Chercher les alternatives
            log_info "Alternatives disponibles:"
            find /usr/lib -name "libwebsockets.so*" 2>/dev/null | while read f; do
                log_info "  $f"
            done
            
            # Tenter de créer un lien symbolique
            log_warning "Tentative de création d'un lien symbolique..."
            local existing=$(find /usr/lib -name "libwebsockets.so.*" 2>/dev/null | head -1)
            
            if [ -n "$existing" ]; then
                log_info "Fichier trouvé: $existing"
                log_info "Vous pouvez créer un lien avec:"
                log_info "  sudo ln -s $existing /usr/lib/$(uname -m)-linux-gnu/libwebsockets.so.19"
            fi
        fi
    else
        log_success "Le binaire ne cherche pas libwebsockets.so.19"
    fi
}

# ===============================================================================
# SECTION 5 : STATUT DU SERVICE MOSQUITTO
# ===============================================================================

check_mosquitto_service() {
    log_section "5. STATUT DU SERVICE MOSQUITTO"
    
    log_info "Statut systemd:"
    log_command "systemctl status mosquitto" "Status mosquitto"
    
    log_info "Est actif:"
    if systemctl is-active --quiet mosquitto; then
        log_success "Mosquitto est ACTIF"
    else
        log_error "Mosquitto est INACTIF"
    fi
    
    log_info "Est activé au démarrage:"
    if systemctl is-enabled --quiet mosquitto; then
        log_success "Mosquitto est ACTIVÉ au démarrage"
    else
        log_warning "Mosquitto n'est pas activé au démarrage"
    fi
    
    log_info "Derniers logs (journalctl):"
    log_command "journalctl -u mosquitto -n 30 --no-pager" "Logs mosquitto"
    
    log_info "Écoute réseau:"
    log_command "netstat -tlnp | grep mosquitto || ss -tlnp | grep mosquitto" "Ports écoutés par mosquitto"
}

# ===============================================================================
# SECTION 6 : TENTATIVE DE DÉMARRAGE MANUEL
# ===============================================================================

check_manual_start() {
    log_section "6. TENTATIVE DE DÉMARRAGE MANUEL"
    
    log_info "Arrêt du service (s'il est actif):"
    systemctl stop mosquitto 2>/dev/null
    sleep 1
    
    log_info "Exécution directe du binaire:"
    log_command "/usr/sbin/mosquitto -h 2>&1 | head -20" "Test: mosquitto -h"
    
    log_info "Exécution verbose (1 seconde):"
    timeout 1 /usr/sbin/mosquitto -v 2>&1 >> "$REPORT_FILE" || true
    log_info "Voir le rapport pour les détails"
    
    log_info "Vérification des fichiers de configuration:"
    log_command "ls -la /etc/mosquitto/" "Fichiers de config"
    
    if [ -f "/etc/mosquitto/mosquitto.conf" ]; then
        log_info "Configuration mosquitto.conf (premiers 50 lignes):"
        head -50 /etc/mosquitto/mosquitto.conf >> "$REPORT_FILE"
    fi
}

# ===============================================================================
# SECTION 7 : CACHE DE PAQUETS
# ===============================================================================

check_package_cache() {
    log_section "7. CACHE DE PAQUETS MAXLINK"
    
    local cache_dir="/var/cache/maxlink/packages"
    
    if [ ! -d "$cache_dir" ]; then
        log_warning "Cache MaxLink non trouvé: $cache_dir"
        return
    fi
    
    log_success "Cache MaxLink trouvé"
    
    log_info "Packages mosquitto dans le cache:"
    local mosquitto_packages=$(find "$cache_dir" -name "mosquitto*.deb" 2>/dev/null)
    
    if [ -z "$mosquitto_packages" ]; then
        log_warning "Aucun package mosquitto dans le cache"
    else
        echo "$mosquitto_packages" | while read pkg; do
            log_success "  $(basename "$pkg")"
            
            # Vérifier l'intégrité
            dpkg-deb --info "$pkg" >/dev/null 2>&1 && log_info "    ✓ Intégrité OK" || log_error "    ✗ Package corrompu"
        done
    fi
    
    log_info "Packages libwebsockets dans le cache:"
    local websocket_packages=$(find "$cache_dir" -name "*websocket*.deb" 2>/dev/null)
    
    if [ -z "$websocket_packages" ]; then
        log_warning "Aucun package websocket dans le cache"
    else
        echo "$websocket_packages" | while read pkg; do
            log_success "  $(basename "$pkg")"
        done
    fi
    
    log_info "Statistiques du cache:"
    log_command "du -sh $cache_dir" "Taille du cache"
    log_command "ls -1 $cache_dir | wc -l" "Nombre de packages"
}

# ===============================================================================
# SECTION 8 : DÉPENDANCES APT
# ===============================================================================

check_apt_dependencies() {
    log_section "8. DÉPENDANCES APT"
    
    log_info "Dépendances de mosquitto selon apt:"
    log_command "apt-cache depends mosquitto" "Dépendances mosquitto"
    
    log_info "Dépendances de libwebsockets selon apt:"
    log_command "apt-cache depends libwebsockets" "Dépendances libwebsockets"
    
    log_info "Vérification si libwebsockets est installé:"
    if dpkg -l | grep -q "libwebsockets"; then
        log_success "libwebsockets est installé"
        log_command "apt-cache policy libwebsockets" "Version installée"
    else
        log_warning "libwebsockets n'est pas installé"
    fi
}

# ===============================================================================
# SECTION 9 : COMPARAISON AVEC DÉPÔTS OFFICIELS
# ===============================================================================

check_official_repos() {
    log_section "9. COMPARAISON AVEC DÉPÔTS OFFICIELS"
    
    log_info "Mosquitto disponible dans les dépôts:"
    log_command "apt-cache policy mosquitto" "Disponibilité mosquitto"
    
    log_info "Vérification de la source du package mosquitto:"
    if dpkg -l | grep -q "mosquitto"; then
        log_command "apt-cache show mosquitto | grep -E '^(Package|Version|Architecture)'" "Info package"
    fi
    
    log_info "Dépôt officiellement recommandé:"
    echo "  Pour Debian 13 Trixie, mosquitto devrait venir de:" | tee -a "$REPORT_FILE"
    log_command "cat /etc/apt/sources.list | grep -v '^#'" "Sources APT"
}

# ===============================================================================
# SECTION 10 : RECOMMANDATIONS
# ===============================================================================

generate_recommendations() {
    log_section "10. RECOMMANDATIONS DE DÉPANNAGE"
    
    echo "Basé sur le diagnostic:" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Vérifier les problèmes détectés
    local missing_libwebsockets=false
    local mosquitto_not_installed=false
    local mosquitto_not_running=false
    
    if ! find /usr/lib -name "libwebsockets.so.19" >/dev/null 2>&1; then
        missing_libwebsockets=true
    fi
    
    if [ ! -f "/usr/sbin/mosquitto" ]; then
        mosquitto_not_installed=true
    fi
    
    if ! systemctl is-active --quiet mosquitto; then
        mosquitto_not_running=true
    fi
    
    # Générer recommandations
    if [ "$mosquitto_not_installed" = true ]; then
        log_warning "Mosquitto n'est pas installé"
        echo "Solution: sudo apt-get install -y mosquitto mosquitto-clients" >> "$REPORT_FILE"
    fi
    
    if [ "$missing_libwebsockets" = true ]; then
        log_warning "libwebsockets.so.19 manquante"
        echo "Solution 1: Installer une version compatible de libwebsockets" >> "$REPORT_FILE"
        echo "  sudo apt-get install -y libwebsockets-dev" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "Solution 2: Créer un lien symbolique vers la version existante" >> "$REPORT_FILE"
        echo "  Voir section 4 du rapport pour les détails" >> "$REPORT_FILE"
    fi
    
    echo "" >> "$REPORT_FILE"
    echo "Commandes de diagnostic supplémentaires:" >> "$REPORT_FILE"
    echo "  ldd /usr/sbin/mosquitto" >> "$REPORT_FILE"
    echo "  strace -e trace=open,openat mosquitto 2>&1 | head -50" >> "$REPORT_FILE"
    echo "  apt-get install -f" >> "$REPORT_FILE"
}

# ===============================================================================
# RÉSUMÉ FINAL
# ===============================================================================

print_summary() {
    log_section "RÉSUMÉ DU DIAGNOSTIC"
    
    echo "Le rapport complet a été sauvegardé ici:"
    echo -e "${GREEN}$REPORT_FILE${NC}"
    echo ""
    echo "Commandes pour voir le rapport:"
    echo "  cat $REPORT_FILE"
    echo "  less $REPORT_FILE"
    echo ""
    
    # Afficher les points critiques
    if grep -q "✗" "$REPORT_FILE"; then
        echo -e "${RED}Points critiques trouvés:${NC}"
        grep "✗" "$REPORT_FILE" | head -10
        echo ""
    fi
    
    echo -e "${YELLOW}Prochaines étapes:${NC}"
    echo "1. Examinez le rapport complet"
    echo "2. Identifiez les dépendances manquantes"
    echo "3. Installez les packages requis"
    echo "4. Redémarrez mosquitto"
    echo "5. Relancez ce diagnostic pour vérifier"
}

# ===============================================================================
# EXÉCUTION PRINCIPALE
# ===============================================================================

main() {
    initialize
    
    check_system_info
    check_libwebsockets
    check_mosquitto_installation
    check_missing_deps
    check_mosquitto_service
    check_manual_start
    check_package_cache
    check_apt_dependencies
    check_official_repos
    generate_recommendations
    
    print_summary
}

# Lancer le diagnostic
main