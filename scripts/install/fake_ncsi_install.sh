#!/bin/bash

# ===============================================================================
# MAXLINK - INSTALLATION FAKE NCSI (CORRECTIF WINDOWS)
# Intégration du correctif Windows NCSI dans l'architecture MaxLink
# Basé sur fixwifi.sh - Fonctionnalité préservée intégralement
# ===============================================================================

# Définir le répertoire de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source des modules
source "$BASE_DIR/scripts/common/variables.sh"
source "$BASE_DIR/scripts/common/logging.sh"

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging
init_logging "Installation Fake NCSI (Correctif Windows)" "install"

# ===============================================================================
# FONCTIONS
# ===============================================================================

# Envoyer la progression
send_progress() {
    echo "PROGRESS:$1:$2"
    log_info "Progression: $1% - $2" false
}

# Attente simple
wait_silently() {
    sleep "$1"
}

# ===============================================================================
# VÉRIFICATIONS PRÉLIMINAIRES
# ===============================================================================

log_info "========== DÉBUT DE L'INSTALLATION FAKE NCSI =========="

echo "========================================================================"
echo "INSTALLATION FAKE NCSI - CORRECTIF WINDOWS"
echo "========================================================================"
echo ""

send_progress 5 "Vérifications initiales"

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "  ↦ Privilèges root requis ✗"
    log_error "Privilèges root requis - EUID: $EUID"
    exit 1
fi
log_info "Privilèges root confirmés"

echo "Cette correction utilise UNIQUEMENT nginx, AUCUNE modification DNS"
echo ""

# ===============================================================================
# ÉTAPE 1 : VÉRIFICATION ÉTAT MAXLINK
# ===============================================================================

echo "========================================================================"
echo "ÉTAPE 1 : VÉRIFICATION DE L'ÉTAT MAXLINK"
echo "========================================================================"
echo ""

send_progress 15 "Vérification état MaxLink"
log_info "Vérification de l'état MaxLink"

# Vérifier que MaxLink fonctionne
if ! nmcli con show --active | grep -q "MaxLink-NETWORK"; then
    echo "  ↦ MaxLink-NETWORK n'est pas actif ✗"
    log_error "MaxLink-NETWORK n'est pas actif"
    echo "  ↦ ERREUR: Assurez-vous que MaxLink est installé et opérationnel"
    exit 1
fi

echo "  ↦ MaxLink-NETWORK actif ✓"
log_info "MaxLink-NETWORK actif"

# Vérifier dnsmasq
if ! pgrep -f "dnsmasq.*NetworkManager" >/dev/null; then
    echo "  ↦ dnsmasq NetworkManager non actif ✗"
    log_error "dnsmasq NetworkManager non actif"
    exit 1
fi

echo "  ↦ dnsmasq NetworkManager actif ✓"
log_info "dnsmasq NetworkManager actif"

# Vérifier nginx
if ! systemctl is-active --quiet nginx; then
    echo "  ↦ nginx non actif ✗"
    log_error "nginx non actif"
    exit 1
fi

echo "  ↦ nginx actif ✓"
log_info "nginx actif"

# Vérifier l'IP AP
if ! ip addr show wlan0 | grep -q "192.168.4.1"; then
    echo "  ↦ IP AP 192.168.4.1 non configurée ✗"
    log_error "IP AP 192.168.4.1 non configurée"
    exit 1
fi

echo "  ↦ IP AP 192.168.4.1 configurée ✓"
echo "  ↦ État MaxLink validé ✓"
log_success "État MaxLink validé avec succès"

# ===============================================================================
# ÉTAPE 2 : CONFIGURATION NGINX UNIQUEMENT
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 2 : CONFIGURATION NGINX POUR WINDOWS NCSI"
echo "========================================================================"
echo ""

send_progress 35 "Configuration nginx NCSI"
log_info "Configuration nginx pour Windows NCSI"

NGINX_CONFIG="/etc/nginx/sites-available/maxlink-dashboard"

# Vérifier que le fichier existe
if [ ! -f "$NGINX_CONFIG" ]; then
    echo "  ↦ Configuration nginx MaxLink non trouvée ✗"
    log_error "Configuration nginx MaxLink non trouvée"
    exit 1
fi

# Sauvegarde
BACKUP_FILE="$NGINX_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
cp "$NGINX_CONFIG" "$BACKUP_FILE"
echo "  ↦ Sauvegarde nginx créée: $(basename "$BACKUP_FILE") ✓"
log_info "Sauvegarde nginx créée: $BACKUP_FILE"

# Vérifier si déjà configuré
if grep -q "connecttest.txt" "$NGINX_CONFIG"; then
    echo "  ↦ Endpoints Windows NCSI déjà présents"
    log_info "Endpoints Windows NCSI déjà présents - mise à jour"
    
    # Mettre à jour le message
    sed -i '/location \/connecttest.txt/,/}/ s/return 200 \".*\";/return 200 "Bonjour ! Vous etes bien connecte a un serveur Microsoft (Ou presque...)";/' "$NGINX_CONFIG"
    sed -i '/location \/ncsi.txt/,/}/ s/return 200 \".*\";/return 200 "Bonjour ! Vous etes bien connecte a un serveur Microsoft (Ou presque...)";/' "$NGINX_CONFIG"
    
    echo "  ↦ Message personnalisé mis à jour ✓"
    log_info "Message personnalisé mis à jour"
else
    echo "  ↦ Ajout des endpoints Windows NCSI..."
    log_info "Ajout des endpoints Windows NCSI"
    
    # Insérer les endpoints avant la dernière accolade
    sed -i '$i\
\    # ===============================================================================\
\    # ENDPOINTS WINDOWS NCSI - Solution sans DNS\
\    # ===============================================================================\
\    \
\    # Test principal Microsoft Windows\
\    location /connecttest.txt {\
\        add_header Content-Type text/plain;\
\        add_header Cache-Control "no-cache, no-store, must-revalidate";\
\        add_header Pragma "no-cache";\
\        add_header Expires "0";\
\        add_header Access-Control-Allow-Origin "*";\
\        return 200 "Bonjour ! Vous etes bien connecte a un serveur Microsoft (Ou presque...)";\
\    }\
\    \
\    # Test NCSI Windows 10/11\
\    location /ncsi.txt {\
\        add_header Content-Type text/plain;\
\        add_header Cache-Control "no-cache, no-store, must-revalidate";\
\        add_header Pragma "no-cache";\
\        add_header Expires "0";\
\        add_header Access-Control-Allow-Origin "*";\
\        return 200 "Bonjour ! Vous etes bien connecte a un serveur Microsoft (Ou presque...)";\
\    }\
\    \
\    # Test générique de connectivité\
\    location /generate_204 {\
\        add_header Cache-Control "no-cache, no-store, must-revalidate";\
\        add_header Pragma "no-cache";\
\        add_header Expires "0";\
\        add_header Access-Control-Allow-Origin "*";\
\        return 204;\
\    }\
\    \
\    # Test DNS over HTTPS (parfois utilisé)\
\    location /dns-query {\
\        add_header Content-Type application/dns-message;\
\        add_header Cache-Control "no-cache, no-store, must-revalidate";\
\        return 200 "DNS OK";\
\    }\
\    \
\    # Captive portal detection\
\    location /hotspot-detect.html {\
\        add_header Content-Type text/html;\
\        return 200 "<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>";\
\    }\
\
' "$NGINX_CONFIG"
    
    echo "  ↦ Endpoints Windows NCSI ajoutés ✓"
    log_success "Endpoints Windows NCSI ajoutés avec succès"
fi

# ===============================================================================
# ÉTAPE 3 : CONFIGURATION DHCP POUR FORCER L'IP
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 3 : CONFIGURATION DHCP POUR GUIDER WINDOWS"
echo "========================================================================"
echo ""

send_progress 55 "Configuration DHCP"
log_info "Configuration DHCP pour guider Windows"

# Ajouter une option DHCP pour indiquer aux clients où tester la connectivité
DNSMASQ_SHARED_DIR="/etc/NetworkManager/dnsmasq-shared.d"
WINDOWS_HINT_FILE="$DNSMASQ_SHARED_DIR/01-windows-connectivity-hint.conf"

if [ ! -f "$WINDOWS_HINT_FILE" ]; then
    echo "  ↦ Création du fichier d'aide Windows..."
    log_info "Création du fichier d'aide Windows"
    
    cat > "$WINDOWS_HINT_FILE" << 'EOF'
# Configuration d'aide pour la connectivité Windows
# Force Windows à utiliser notre gateway comme serveur de test

# Option DHCP pour indiquer le serveur de captive portal
dhcp-option=114,"http://192.168.4.1/generate_204"

# Option pour forcer les tests de connectivité vers notre IP
dhcp-option=252,"http://192.168.4.1/"
EOF
    
    echo "  ↦ Fichier d'aide Windows créé ✓"
    log_success "Fichier d'aide Windows créé"
else
    echo "  ↦ Fichier d'aide Windows déjà présent ✓"
    log_info "Fichier d'aide Windows déjà présent"
fi

# ===============================================================================
# ÉTAPE 4 : TESTS ET APPLICATION
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 4 : TESTS ET APPLICATION"
echo "========================================================================"
echo ""

send_progress 75 "Tests et application"
log_info "Tests et application des configurations"

# Test de la configuration nginx
echo "  ↦ Test de la configuration nginx..."
if nginx -t >/dev/null 2>&1; then
    echo "  ↦ Configuration nginx valide ✓"
    log_success "Configuration nginx valide"
else
    echo "  ↦ ERREUR: Configuration nginx invalide ✗"
    log_error "Configuration nginx invalide"
    echo "  ↦ Restauration de la sauvegarde..."
    cp "$BACKUP_FILE" "$NGINX_CONFIG"
    exit 1
fi

# Rechargement nginx (sans interruption)
echo "  ↦ Rechargement nginx..."
systemctl reload nginx
echo "  ↦ Nginx rechargé ✓"
log_success "Nginx rechargé avec succès"

# Rechargement dnsmasq via NetworkManager (sans casser l'AP)
echo "  ↦ Rechargement de la configuration dnsmasq..."
systemctl reload NetworkManager
sleep 2
echo "  ↦ Configuration dnsmasq rechargée ✓"
log_success "Configuration dnsmasq rechargée"

# ===============================================================================
# ÉTAPE 5 : TESTS DE VALIDATION
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 5 : TESTS DE VALIDATION"
echo "========================================================================"
echo ""

send_progress 90 "Tests de validation"
log_info "Tests de validation"

# Vérifier que l'AP est toujours actif
echo "  ↦ Vérification AP après modifications..."
sleep 3

if nmcli con show --active | grep -q "MaxLink-NETWORK"; then
    echo "  ↦ MaxLink-NETWORK toujours actif ✓"
    log_success "MaxLink-NETWORK toujours actif"
else
    echo "  ↦ ATTENTION: MaxLink-NETWORK inactif - réactivation..."
    log_warn "MaxLink-NETWORK inactif - tentative de réactivation"
    nmcli con up "MaxLink-NETWORK" >/dev/null 2>&1
    sleep 3
    
    if nmcli con show --active | grep -q "MaxLink-NETWORK"; then
        echo "  ↦ MaxLink-NETWORK réactivé ✓"
        log_success "MaxLink-NETWORK réactivé"
    else
        echo "  ↦ ERREUR: Impossible de réactiver MaxLink-NETWORK ✗"
        log_error "Impossible de réactiver MaxLink-NETWORK"
        exit 1
    fi
fi

# Test des endpoints
echo "  ↦ Test des endpoints Windows..."
log_info "Test des endpoints Windows"

if curl -s --connect-timeout 3 "http://192.168.4.1/connecttest.txt" | grep -q "Microsoft" >/dev/null 2>&1; then
    echo "  ↦ Endpoint connecttest.txt fonctionnel ✓"
    log_success "Endpoint connecttest.txt fonctionnel"
else
    echo "  ↦ ATTENTION: Endpoint connecttest.txt non accessible ⚠"
    log_warn "Endpoint connecttest.txt non accessible"
fi

if curl -s --connect-timeout 3 "http://192.168.4.1/generate_204" >/dev/null 2>&1; then
    echo "  ↦ Endpoint generate_204 fonctionnel ✓"
    log_success "Endpoint generate_204 fonctionnel"
else
    echo "  ↦ ATTENTION: Endpoint generate_204 non accessible ⚠"
    log_warn "Endpoint generate_204 non accessible"
fi

# Test que dnsmasq fonctionne toujours
if pgrep -f "dnsmasq.*NetworkManager" >/dev/null; then
    echo "  ↦ Service dnsmasq toujours actif ✓"
    log_success "Service dnsmasq toujours actif"
else
    echo "  ↦ ATTENTION: Service dnsmasq non actif ⚠"
    log_warn "Service dnsmasq non actif"
fi

# ===============================================================================
# ÉTAPE 6 : SURVEILLANCE COURTE
# ===============================================================================

echo ""
echo "========================================================================"
echo "ÉTAPE 6 : SURVEILLANCE DE LA STABILITÉ"
echo "========================================================================"
echo ""

send_progress 95 "Surveillance stabilité"
log_info "Surveillance de la stabilité (30 secondes)"

echo "Surveillance de la stabilité MaxLink..."
STABLE_COUNT=0
for i in {1..15}; do
    if nmcli con show --active | grep -q "MaxLink-NETWORK"; then
        echo "  $(date '+%H:%M:%S'): Stable ✓"
        ((STABLE_COUNT++))
    else
        echo "  $(date '+%H:%M:%S'): INSTABLE ✗"
        log_error "Instabilité détectée à $(date '+%H:%M:%S')"
        break
    fi
    sleep 2
done

if [ $STABLE_COUNT -eq 15 ]; then
    log_success "Surveillance complète - système stable"
else
    log_warn "Surveillance interrompue - instabilité détectée"
fi

# ===============================================================================
# FINALISATION
# ===============================================================================

send_progress 100 "Installation terminée"

echo ""
echo "========================================================================"
echo "CORRECTION WINDOWS NCSI APPLIQUÉE AVEC SUCCÈS"
echo "========================================================================"
echo ""
echo "✓ Endpoints nginx Windows NCSI configurés"
echo "✓ Message personnalisé appliqué"
echo "✓ Options DHCP d'aide ajoutées"
echo "✓ Configuration MaxLink préservée"
echo "✓ Aucune modification DNS (pas de boucle)"
echo ""
echo "PRINCIPE DE FONCTIONNEMENT:"
echo "  → Windows teste la connectivité"
echo "  → DHCP lui suggère d'utiliser 192.168.4.1"
echo "  → nginx répond avec votre message personnalisé"
echo "  → Windows considère le réseau comme 'Connecté'"
echo "  → Raspberry Pi reste stable (pas de redirection DNS)"
echo ""
echo "TESTS MANUELS:"
echo "  → curl http://192.168.4.1/connecttest.txt"
echo "  → curl http://192.168.4.1/generate_204"
echo "  → Connecter un PC Windows et observer le statut"
echo ""
echo "SURVEILLANCE:"
echo "  → Surveillez pendant 5-10 minutes"
echo "  → Redémarrage test: sudo reboot"
echo ""
echo "Sauvegarde disponible: $BACKUP_FILE"
echo ""

log_success "Installation Fake NCSI terminée avec succès"

# Signal pour l'interface de rafraîchir les indicateurs (si mode interface)
if [ "$INTERFACE_MODE" = "true" ]; then
    echo "REFRESH_INDICATORS"
fi

log_info "========== FIN DE L'INSTALLATION FAKE NCSI =========="

# Ne pas redémarrer automatiquement si SKIP_REBOOT est défini
if [ "$SKIP_REBOOT" != "true" ]; then
    echo ""
    echo "========================================================================"
    echo "REDÉMARRAGE RECOMMANDÉ"
    echo "========================================================================"
    echo ""
    echo "Un redémarrage est recommandé pour valider la stabilité complète."
    echo "Redémarrage automatique dans 10 secondes..."
    echo "Appuyez sur Ctrl+C pour annuler."
    echo ""
    
    for i in {10..1}; do
        echo -n "$i "
        sleep 1
    done
    
    echo ""
    echo "Redémarrage en cours..."
    log_info "Redémarrage automatique du système"
    reboot
else
    log_info "Redémarrage ignoré (SKIP_REBOOT=true)"
fi