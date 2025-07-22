#!/bin/bash

# ===============================================================================
# MAXLINK - DIAGNOSTIC COMPLET UNIFIÉ (VERSION AMÉLIORÉE)
# Script unique pour diagnostic complet avec analyses détaillées des erreurs
# Version corrigée avec diagnostics SystemD approfondis
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Variables globales
MQTT_USER="${MQTT_USER:-mosquitto}"
MQTT_PASS="${MQTT_PASS:-mqtt}"
MQTT_PORT="${MQTT_PORT:-1883}"
ERRORS=0
WARNINGS=0
SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"

# Configuration des tests de stress
MQTT_STRESS_DURATION=10
MQTT_STRESS_MESSAGES=50
NETWORK_STRESS_DURATION=5

# Mode hors-ligne (pas de tests internet)
OFFLINE_MODE=true
if [ "$1" = "--online" ]; then
    OFFLINE_MODE=false
fi

# Variables pour analyser les erreurs en détail
DETAILED_ANALYSIS=true
if [ "$1" = "--quick" ]; then
    DETAILED_ANALYSIS=false
fi

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "========================================================================"
}

print_test() {
    printf "%-50s" "◦ $1"
}

print_result() {
    case $1 in
        "OK") echo -e "${GREEN}[OK]${NC}" ;;
        "FAIL") echo -e "${RED}[ÉCHEC]${NC}"; ((ERRORS++)) ;;
        "WARN") echo -e "${YELLOW}[AVERT]${NC}"; ((WARNINGS++)) ;;
        "INFO") echo -e "${CYAN}[INFO]${NC}" ;;
        *) echo -e "${CYAN}[$1]${NC}" ;;
    esac
}

print_detail() {
    echo "  ↦ $1"
}

print_error_detail() {
    echo -e "  ${RED}✗${NC} $1"
}

print_warning_detail() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_success_detail() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_info_detail() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

# Validation numérique sécurisée
is_number() {
    local value="$1"
    [ -n "$value" ] && [ "$value" -eq "$value" ] 2>/dev/null
}

# ===============================================================================
# FONCTIONS D'ANALYSE DÉTAILLÉE
# ===============================================================================

# Analyser les logs d'erreur d'un service
analyze_service_errors() {
    local service_name="$1"
    local display_name="$2"
    
    if [ "$DETAILED_ANALYSIS" != "true" ]; then
        return
    fi
    
    echo ""
    echo -e "${PURPLE}◦ Analyse détaillée du service $display_name${NC}"
    
    # Dernières erreurs (dernière heure)
    local recent_errors=$(journalctl -u "$service_name" --since "1 hour ago" -p err --no-pager -q 2>/dev/null)
    if [ -n "$recent_errors" ]; then
        print_error_detail "Erreurs récentes détectées:"
        echo "$recent_errors" | tail -3 | while read -r line; do
            if [ -n "$line" ]; then
                echo "    $(echo "$line" | cut -c1-100)"
            fi
        done
    fi
    
    # Avertissements récents
    local recent_warnings=$(journalctl -u "$service_name" --since "30 minutes ago" -p warning --no-pager -q 2>/dev/null)
    if [ -n "$recent_warnings" ]; then
        print_warning_detail "Avertissements récents:"
        echo "$recent_warnings" | tail -2 | while read -r line; do
            if [ -n "$line" ]; then
                echo "    $(echo "$line" | cut -c1-100)"
            fi
        done
    fi
    
    # État détaillé du service
    local service_status=$(systemctl status "$service_name" --no-pager -l 2>/dev/null)
    if echo "$service_status" | grep -q "failed\|error\|timeout"; then
        print_error_detail "Problèmes détectés dans l'état du service:"
        echo "$service_status" | grep -E "(failed|error|timeout|Active:|Main PID:)" | while read -r line; do
            echo "    $line"
        done
    fi
    
    # Restart count
    local restart_count=$(systemctl show "$service_name" --property=NRestarts --value 2>/dev/null)
    if [ -n "$restart_count" ] && [ "$restart_count" -gt 0 ]; then
        print_warning_detail "Service redémarré $restart_count fois"
    fi
}

# Analyser la configuration réseau en détail
analyze_network_config() {
    if [ "$DETAILED_ANALYSIS" != "true" ]; then
        return
    fi
    
    echo ""
    echo -e "${PURPLE}◦ Analyse détaillée de la configuration réseau${NC}"
    
    # Vérifier les connections NetworkManager
    local ap_connections=$(nmcli con show | grep -E "(MaxLink|AP)" || true)
    if [ -n "$ap_connections" ]; then
        print_success_detail "Connexions AP trouvées:"
        echo "$ap_connections" | while read -r line; do
            echo "    $line"
        done
    else
        print_error_detail "Aucune connexion AP trouvée dans NetworkManager"
    fi
    
    # État de l'interface WiFi
    if ip link show wlan0 >/dev/null 2>&1; then
        local wlan_state=$(ip addr show wlan0 2>/dev/null | grep -E "(state|inet)")
        if [ -n "$wlan_state" ]; then
            print_info_detail "État interface wlan0:"
            echo "$wlan_state" | while read -r line; do
                echo "    $line"
            done
        fi
    fi
    
    # Processus dnsmasq
    local dnsmasq_procs=$(ps aux | grep dnsmasq | grep -v grep || true)
    if [ -n "$dnsmasq_procs" ]; then
        print_success_detail "Processus dnsmasq actifs:"
        echo "$dnsmasq_procs" | while read -r line; do
            echo "    $(echo "$line" | awk '{print $1, $2, $11, $12, $13}')"
        done
    else
        print_error_detail "Aucun processus dnsmasq détecté"
    fi
}

# Analyser les métriques MQTT en détail
analyze_mqtt_metrics() {
    if [ "$DETAILED_ANALYSIS" != "true" ]; then
        return
    fi
    
    echo ""
    echo -e "${PURPLE}◦ Analyse détaillée des métriques MQTT${NC}"
    
    # Topics système détaillés
    local sys_topics=$(timeout 3 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/+' -C 5 2>/dev/null || true)
    if [ -n "$sys_topics" ]; then
        print_success_detail "Métriques broker disponibles:"
        echo "$sys_topics" | while read -r line; do
            echo "    $line"
        done
    fi
    
    # Widgets actifs
    local widget_topics=$(timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t 'rpi/+/+/+' -C 3 2>/dev/null || true)
    if [ -n "$widget_topics" ]; then
        print_success_detail "Widgets actifs détectés:"
        echo "$widget_topics" | cut -d' ' -f1 | sort -u | while read -r topic; do
            echo "    $topic"
        done
    fi
    
    # Connexions clients MQTT
    local mqtt_clients=$(netstat -tan 2>/dev/null | grep ":$MQTT_PORT " | wc -l)
    if [ "$mqtt_clients" -gt 0 ]; then
        print_success_detail "Connexions MQTT actives: $mqtt_clients"
    fi
}

# Suggestions de résolution automatique
suggest_fixes() {
    local problem_type="$1"
    
    echo ""
    echo -e "${CYAN}◦ Suggestions de résolution pour: $problem_type${NC}"
    
    case "$problem_type" in
        "ap_healthcheck")
            print_info_detail "Le healthcheck AP cherche probablement le mauvais nom de connexion"
            print_info_detail "Actions possibles:"
            echo "    • Vérifier: nmcli con show"
            echo "    • Redémarrer NetworkManager: systemctl restart NetworkManager"
            echo "    • Réactiver l'AP: nmcli con up MaxLink-NETWORK"
            ;;
        "service_errors")
            print_info_detail "Erreurs détectées dans les services SystemD"
            print_info_detail "Actions possibles:"
            echo "    • Voir logs détaillés: journalctl -u [service] -f"
            echo "    • Redémarrer service: systemctl restart [service]"
            echo "    • Vérifier config: systemctl status [service]"
            ;;
        "mqtt_issues")
            print_info_detail "Problèmes de connexion MQTT détectés"
            print_info_detail "Actions possibles:"
            echo "    • Redémarrer broker: systemctl restart mosquitto"
            echo "    • Vérifier auth: mosquitto_pub -h localhost -u $MQTT_USER -P $MQTT_PASS -t test -m test"
            echo "    • Voir logs: journalctl -u mosquitto -f"
            ;;
        "network_issues")
            print_info_detail "Problèmes réseau détectés"
            print_info_detail "Actions possibles:"
            echo "    • Redémarrer réseau: systemctl restart NetworkManager"
            echo "    • Vérifier interface: ip addr show wlan0"
            echo "    • Relancer AP: nmcli con down MaxLink-NETWORK && nmcli con up MaxLink-NETWORK"
            ;;
    esac
}

# ===============================================================================
# ÉTAT DE L'INSTALLATION (VERSION AMÉLIORÉE)
# ===============================================================================

check_installation_status() {
    print_header "ÉTAT DE L'INSTALLATION MAXLINK"
    
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        print_test "Fichier de statuts"
        print_result "OK"
        
        echo ""
        python3 << EOF
import json
from datetime import datetime

with open('$SERVICES_STATUS_FILE', 'r') as f:
    data = json.load(f)

# Services attendus dans l'ordre complet
expected_services = [
    ('update', 'Mise à jour système'),
    ('ap', 'Point d\'accès WiFi'),
    ('nginx', 'Serveur Web'),
    ('fake_ncsi', 'Fake NCSI'),
    ('mqtt', 'Broker MQTT'),
    ('mqtt_wgs', 'Widgets MQTT'),
    ('php_archives', 'Archives PHP'),
    ('orchestrator', 'Orchestrateur')
]

print("  État des composants :")
print("")

all_active = True
inactive_services = []

for service_id, service_name in expected_services:
    if service_id in data:
        info = data[service_id]
        status = info.get('status', 'inactive')
        
        if status == 'active':
            symbol = '✓'
            color = '\033[0;32m'  # Green
        else:
            symbol = '✗'
            color = '\033[0;31m'  # Red
            all_active = False
            inactive_services.append(service_name)
            
        print(f"    {color}{symbol}\033[0m {service_name:20} : {status}")
        
        # Afficher la date de mise à jour si disponible
        if 'last_update' in info:
            try:
                dt = datetime.fromisoformat(info['last_update'])
                print(f"      ↦ Mis à jour: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
            except:
                pass
        
        # Afficher message d'erreur si présent
        if 'message' in info and info['message']:
            print(f"      ↦ Message: {info['message']}")
    else:
        all_active = False
        inactive_services.append(service_name)
        print(f"    ○ {service_name:20} : non installé")

print("")
if all_active:
    print("    \033[0;32m✓ Installation complète réussie !\033[0m")
else:
    print("    \033[1;33m⚠ Installation incomplète\033[0m")
    print(f"    Services inactifs: {', '.join(inactive_services)}")
EOF
    else
        print_test "Fichier de statuts"
        print_result "FAIL"
        print_detail "Aucune installation détectée"
        
        echo ""
        echo "  Pour lancer l'installation complète :"
        echo "    sudo bash /media/prod/USBTOOL/full_install.sh"
    fi
}

# ===============================================================================
# TESTS DES SERVICES MAXLINK (VERSION AMÉLIORÉE)
# ===============================================================================

test_maxlink_services() {
    print_header "SERVICES MAXLINK"
    
    local services=(
        "update:Update RPI"
        "ap:Network AP"  
        "nginx:NginX Web"
        "fake_ncsi:Fake NCSI"
        "mqtt:MQTT BKR"
        "mqtt_wgs:MQTT WGS"
        "php_archives:PHP Archives"
        "orchestrator:Orchestrateur"
    )
    
    local has_errors=false
    
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        for service_info in "${services[@]}"; do
            IFS=':' read -r service_id service_name <<< "$service_info"
            
            print_test "$service_name"
            
            local status=$(python3 -c "
import json
try:
    with open('$SERVICES_STATUS_FILE', 'r') as f:
        data = json.load(f)
    print(data.get('$service_id', {}).get('status', 'unknown'))
except:
    print('error')
")
            
            case "$status" in
                "active") 
                    print_result "OK"
                    case "$service_id" in
                        "nginx") test_nginx_detailed ;;
                        "mqtt") test_mqtt_detailed ;;
                        "php_archives") test_php_archives_detailed ;;
                        "fake_ncsi") test_fake_ncsi_detailed ;;
                        "ap") test_ap_detailed ;;
                    esac
                    ;;
                "inactive") 
                    print_result "FAIL"
                    has_errors=true
                    ;;
                "error") 
                    print_result "WARN"
                    print_detail "Erreur lecture statut"
                    has_errors=true
                    ;;
                *) 
                    print_result "WARN"
                    print_detail "Statut: $status"
                    has_errors=true
                    ;;
            esac
        done
        
        if [ "$has_errors" = true ]; then
            suggest_fixes "service_errors"
        fi
    else
        print_test "Fichier de statuts"
        print_result "FAIL"
        print_detail "Fichier $SERVICES_STATUS_FILE non trouvé"
    fi
}

# Test détaillé de l'AP
test_ap_detailed() {
    local ap_connections=$(nmcli con show --active | grep -E "(MaxLink|AP)" || true)
    if [ -n "$ap_connections" ]; then
        print_detail "✓ Connexion AP active détectée"
        print_detail "  $(echo "$ap_connections" | head -1)"
    else
        print_detail "✗ Aucune connexion AP active"
        suggest_fixes "ap_healthcheck"
    fi
    
    # Vérifier les clients connectés
    if command -v iw >/dev/null 2>&1; then
        local client_count=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station" || echo "0")
        print_detail "Clients WiFi connectés: $client_count"
    fi
}

test_nginx_detailed() {
    print_detail "Test dashboard principal"
    local response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
    if [ "$response" = "200" ]; then
        print_detail "  ✓ Dashboard accessible (HTTP $response)"
    else
        print_detail "  ✗ Dashboard inaccessible (HTTP $response)"
        if [ "$response" = "000" ]; then
            print_detail "    Nginx probablement arrêté"
        fi
    fi
    
    print_detail "Test API archives PHP"
    local api_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/archives-list.php 2>/dev/null || echo "000")
    if [ "$api_response" = "200" ]; then
        print_detail "  ✓ API archives accessible (HTTP $api_response)"
    else
        print_detail "  ⚠ API archives problématique (HTTP $api_response)"
    fi
}

test_mqtt_detailed() {
    print_detail "Test publication MQTT"
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/diagnostic" -m "$(date)" 2>/dev/null; then
        print_detail "  ✓ Publication réussie"
    else
        print_detail "  ✗ Échec publication"
        suggest_fixes "mqtt_issues"
    fi
    
    print_detail "Test souscription MQTT"
    if timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/diagnostic" -C 1 2>/dev/null | grep -q "$(date +%Y)"; then
        print_detail "  ✓ Souscription réussie"
    else
        print_detail "  ⚠ Souscription problématique"
    fi
    
    # Test des topics système
    print_detail "Test topics système"
    local sys_version=$(timeout 1 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null || echo "")
    if [ -n "$sys_version" ]; then
        print_detail "  ✓ Topics système: $sys_version"
    else
        print_detail "  ⚠ Topics système non accessibles"
    fi
}

test_fake_ncsi_detailed() {
    print_detail "Test endpoints Windows NCSI"
    
    if curl -s --connect-timeout 3 "http://localhost/connecttest.txt" | grep -q "Microsoft" 2>/dev/null; then
        print_detail "  ✓ connecttest.txt fonctionnel"
    else
        print_detail "  ✗ connecttest.txt non accessible"
    fi
    
    if curl -s --connect-timeout 3 "http://localhost/generate_204" >/dev/null 2>&1; then
        print_detail "  ✓ generate_204 fonctionnel"
    else
        print_detail "  ✗ generate_204 non accessible"
    fi
    
    if [ -f "/etc/NetworkManager/dnsmasq-shared.d/01-windows-connectivity-hint.conf" ]; then
        print_detail "  ✓ Options DHCP Windows configurées"
    else
        print_detail "  ⚠ Options DHCP Windows absentes"
    fi
}

test_php_archives_detailed() {
    print_detail "Test répertoire archives"
    if [ -d "/var/www/maxlink-dashboard/archives" ]; then
        local archive_count=$(find /var/www/maxlink-dashboard/archives -name "*.csv" 2>/dev/null | wc -l)
        print_detail "  ✓ $archive_count fichiers CSV trouvés"
        
        # Test des permissions
        if [ -r "/var/www/maxlink-dashboard/archives" ] && [ -w "/var/www/maxlink-dashboard/archives" ]; then
            print_detail "  ✓ Permissions d'accès correctes"
        else
            print_detail "  ⚠ Problème de permissions"
        fi
    else
        print_detail "  ✗ Répertoire archives manquant"
    fi
}

# ===============================================================================
# TESTS DES SERVICES SYSTEMD (VERSION AMÉLIORÉE)
# ===============================================================================

test_systemd_services() {
    print_header "SERVICES SYSTEMD"
    
    local critical_services=(
        "mosquitto:Broker MQTT"
        "nginx:Serveur Web"
        "NetworkManager:Gestionnaire réseau"
        "php8.2-fpm:PHP-FPM"
    )
    
    local services_with_errors=()
    
    for service_info in "${critical_services[@]}"; do
        IFS=':' read -r service_name service_desc <<< "$service_info"
        
        print_test "$service_desc"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            print_result "OK"
            
            local uptime=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value 2>/dev/null)
            if [ -n "$uptime" ] && [ "$uptime" != "n/a" ]; then
                print_detail "Actif depuis: $(echo $uptime | cut -d' ' -f1-2)"
            fi
            
            # Analyse détaillée des erreurs
            local failed_count=$(journalctl -u "$service_name" --since "1 hour ago" -p err --no-pager -q 2>/dev/null | wc -l)
            local warning_count=$(journalctl -u "$service_name" --since "1 hour ago" -p warning --no-pager -q 2>/dev/null | wc -l)
            
            if [ "$failed_count" -gt 0 ]; then
                print_detail "⚠ $failed_count erreurs dans la dernière heure"
                services_with_errors+=("$service_name")
            fi
            
            if [ "$warning_count" -gt 0 ]; then
                print_detail "⚠ $warning_count avertissements dans la dernière heure"
            fi
            
            # État mémoire si disponible
            local memory_usage=$(systemctl show "$service_name" --property=MemoryCurrent --value 2>/dev/null)
            if [ -n "$memory_usage" ] && [ "$memory_usage" != "18446744073709551615" ] && [ "$memory_usage" != "0" ]; then
                local memory_mb=$((memory_usage / 1024 / 1024))
                print_detail "Mémoire utilisée: ${memory_mb}MB"
            fi
        else
            print_result "FAIL"
            print_detail "Service inactif ou inexistant"
            services_with_errors+=("$service_name")
        fi
    done
    
    # Analyse détaillée des services avec erreurs
    for service in "${services_with_errors[@]}"; do
        analyze_service_errors "$service" "$service"
    done
    
    print_test "Widgets MaxLink"
    local widget_services=($(systemctl list-unit-files | grep "maxlink-widget-" | awk '{print $1}'))
    local active_widgets=0
    local total_widgets=${#widget_services[@]}
    local failed_widgets=()
    
    for widget in "${widget_services[@]}"; do
        if systemctl is-active --quiet "$widget" 2>/dev/null; then
            ((active_widgets++))
        else
            failed_widgets+=("$widget")
        fi
    done
    
    if [ "$total_widgets" -eq 0 ]; then
        print_result "WARN"
        print_detail "Aucun widget installé"
    elif [ "$active_widgets" -eq "$total_widgets" ]; then
        print_result "OK"
        print_detail "$active_widgets/$total_widgets widgets actifs"
    else
        print_result "WARN"
        print_detail "$active_widgets/$total_widgets widgets actifs"
        
        if [ ${#failed_widgets[@]} -gt 0 ]; then
            print_detail "Widgets inactifs:"
            for widget in "${failed_widgets[@]}"; do
                print_detail "  • $widget"
            done
        fi
    fi
}

# ===============================================================================
# TESTS DE L'ORCHESTRATEUR (VERSION CORRIGÉE)
# ===============================================================================

test_orchestrator() {
    print_header "ORCHESTRATEUR MAXLINK"
    
    print_test "Binaire orchestrateur"
    if [ -x "/usr/local/bin/maxlink-orchestrator" ]; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Binaire manquant ou non exécutable"
        return
    fi
    
    print_test "Commande status"
    if /usr/local/bin/maxlink-orchestrator status >/dev/null 2>&1; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Commande status échouée"
    fi
    
    # Healthchecks corrigés avec diagnostics détaillés
    print_test "Healthcheck Point d'accès"
    if [ -x "/usr/local/bin/maxlink-check-ap" ]; then
        # Exécuter le healthcheck et capturer la sortie
        local ap_check_output=$(/usr/local/bin/maxlink-check-ap 2>&1)
        local ap_check_result=$?
        
        if [ $ap_check_result -eq 0 ]; then
            print_result "OK"
        else
            print_result "WARN"
            print_detail "Healthcheck échoué (code: $ap_check_result)"
            
            # Diagnostic détaillé de l'AP
            print_detail "Diagnostic AP détaillé:"
            
            # Chercher toutes les connexions qui pourraient être l'AP
            local all_ap_connections=$(nmcli con show --active | grep -iE "(maxlink|ap|network)" || true)
            if [ -n "$all_ap_connections" ]; then
                print_detail "  Connexions AP/réseau trouvées:"
                echo "$all_ap_connections" | while read -r line; do
                    print_detail "    $line"
                done
            else
                print_detail "  ✗ Aucune connexion AP active détectée"
            fi
            
            # Vérifier le contenu du script healthcheck
            if [ -f "/usr/local/bin/maxlink-check-ap" ]; then
                local check_content=$(cat /usr/local/bin/maxlink-check-ap 2>/dev/null | grep -v "^#" | grep -v "^$")
                print_detail "  Script healthcheck:"
                echo "$check_content" | while read -r line; do
                    print_detail "    $line"
                done
            fi
            
            suggest_fixes "ap_healthcheck"
        fi
    else
        print_result "FAIL"
        print_detail "Script healthcheck manquant"
    fi
    
    print_test "Healthcheck Nginx"
    if [ -x "/usr/local/bin/maxlink-check-nginx" ]; then
        if timeout 5 "/usr/local/bin/maxlink-check-nginx" >/dev/null 2>&1; then
            print_result "OK"
        else
            print_result "WARN"
            print_detail "Healthcheck échoué"
            
            # Test nginx manuel
            if systemctl is-active --quiet nginx; then
                print_detail "  ✓ Service nginx actif"
            else
                print_detail "  ✗ Service nginx inactif"
            fi
            
            local nginx_test=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null || echo "000")
            print_detail "  Test HTTP: $nginx_test"
        fi
    else
        print_result "FAIL"
        print_detail "Script manquant: /usr/local/bin/maxlink-check-nginx"
    fi
    
    print_test "Healthcheck MQTT"
    if [ -x "/usr/local/bin/maxlink-check-mqtt" ]; then
        if timeout 5 "/usr/local/bin/maxlink-check-mqtt" >/dev/null 2>&1; then
            print_result "OK"
        else
            print_result "WARN"
            print_detail "Healthcheck échoué"
            analyze_mqtt_metrics
        fi
    else
        print_result "FAIL"
        print_detail "Script manquant: /usr/local/bin/maxlink-check-mqtt"
    fi
}

# ===============================================================================
# TESTS RÉSEAU AVANCÉS (VERSION AMÉLIORÉE)
# ===============================================================================

test_network_advanced() {
    print_header "TESTS RÉSEAU AVANCÉS"
    
    print_test "Interface WiFi (wlan0)"
    if ip link show wlan0 >/dev/null 2>&1; then
        print_result "OK"
        
        local wlan_info=$(ip addr show wlan0 2>/dev/null)
        if echo "$wlan_info" | grep -q "state UP"; then
            print_detail "Interface: UP"
        else
            print_detail "Interface: DOWN"
        fi
        
        if iw dev wlan0 info 2>/dev/null | grep -q "type AP"; then
            print_detail "Mode: Access Point"
            local client_count=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station" || echo "0")
            print_detail "Clients WiFi: $client_count"
            
            # Informations SSID
            local ssid=$(iw dev wlan0 info 2>/dev/null | grep ssid | awk '{print $2}')
            if [ -n "$ssid" ]; then
                print_detail "SSID diffusé: $ssid"
            fi
        else
            print_detail "Mode: Client ou inactif"
        fi
        
        # Adresses IP
        local ip_addrs=$(echo "$wlan_info" | grep "inet " | awk '{print $2}')
        if [ -n "$ip_addrs" ]; then
            print_detail "Adresses IP:"
            echo "$ip_addrs" | while read -r addr; do
                print_detail "  $addr"
            done
        fi
    else
        print_result "FAIL"
        print_detail "Interface WiFi absente"
        suggest_fixes "network_issues"
    fi
    
    local ports=(
        "80:HTTP (Nginx)"
        "1883:MQTT"
        "9001:WebSocket MQTT"
    )
    
    local port_issues=false
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port_num port_desc <<< "$port_info"
        
        print_test "Port $port_num ($port_desc)"
        if netstat -tlnp 2>/dev/null | grep -q ":$port_num " || ss -tlnp 2>/dev/null | grep -q ":$port_num "; then
            print_result "OK"
            
            # Processus qui écoute
            local process=$(netstat -tlnp 2>/dev/null | grep ":$port_num " | awk '{print $7}' | head -1)
            if [ -n "$process" ]; then
                print_detail "Processus: $process"
            fi
        else
            print_result "FAIL"
            print_detail "Port fermé ou service arrêté"
            port_issues=true
        fi
    done
    
    if [ "$port_issues" = true ]; then
        suggest_fixes "network_issues"
    fi
    
    print_test "Connectivité locale"
    if ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Problème réseau local"
    fi
    
    # Analyse réseau détaillée
    analyze_network_config
}

# ===============================================================================
# FLUX DE DONNÉES MQTT (VERSION AMÉLIORÉE)
# ===============================================================================

test_mqtt_data_flow() {
    print_header "FLUX DE DONNÉES MQTT"
    
    print_test "Connexion broker"
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/connection" -m "test" 2>/dev/null; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Impossible de se connecter au broker"
        suggest_fixes "mqtt_issues"
        return
    fi
    
    print_test "Topics système (\$SYS)"
    local version=$(timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null)
    if [ -n "$version" ]; then
        print_result "OK"
        print_detail "Version: $version"
        
        # Métriques supplémentaires
        local uptime=$(timeout 1 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/uptime' -C 1 2>/dev/null)
        if [ -n "$uptime" ]; then
            print_detail "Uptime broker: $uptime"
        fi
        
        local clients=$(timeout 1 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/clients/connected' -C 1 2>/dev/null)
        if [ -n "$clients" ]; then
            print_detail "Clients connectés: $clients"
        fi
    else
        print_result "WARN"
        print_detail "Topics système indisponibles"
    fi
    
    print_test "Collecte de données (5s)"
    local temp_file=$(mktemp)
    timeout 5 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '#' -v 2>/dev/null > "$temp_file" &
    local sub_pid=$!
    
    for i in {1..5}; do
        echo -ne "\r  ↦ Collecte... [$i/5s]"
        sleep 1
    done
    echo ""
    
    wait $sub_pid 2>/dev/null
    local message_count=$(wc -l < "$temp_file")
    
    if [ "$message_count" -gt 0 ]; then
        print_result "OK"
        print_detail "$message_count messages collectés"
        
        local unique_topics=$(cut -d' ' -f1 "$temp_file" | sort -u | wc -l)
        print_detail "$unique_topics topics uniques détectés"
        
        # Afficher les topics les plus actifs
        print_detail "Topics les plus actifs:"
        cut -d' ' -f1 "$temp_file" | sort | uniq -c | sort -nr | head -5 | while read -r count topic; do
            print_detail "  $topic: $count messages"
        done
    else
        print_result "WARN"
        print_detail "Aucun message collecté"
    fi
    
    rm -f "$temp_file"
    
    # Analyse MQTT détaillée
    analyze_mqtt_metrics
}

# ===============================================================================
# TESTS DE PERFORMANCE (VERSION AMÉLIORÉE - INCHANGÉE)
# ===============================================================================

test_performance() {
    print_header "TESTS DE PERFORMANCE LOCALE"
    
    print_test "Dashboard principal"
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" http://localhost/ 2>/dev/null)
    
    if [ -n "$response_time" ] && command -v bc >/dev/null 2>&1; then
        local response_ms=$(echo "$response_time * 1000" | bc 2>/dev/null | cut -d. -f1)
        
        if is_number "$response_ms"; then
            if [ "$response_ms" -lt 100 ]; then
                print_result "OK"
                print_detail "Dashboard: ${response_ms}ms (excellent)"
            elif [ "$response_ms" -lt 500 ]; then
                print_result "WARN"
                print_detail "Dashboard: ${response_ms}ms (acceptable)"
            else
                print_result "FAIL"
                print_detail "Dashboard: ${response_ms}ms (lent)"
            fi
        else
            print_result "INFO"
            print_detail "Mesure dashboard impossible"
        fi
    else
        print_result "INFO"
        print_detail "curl ou bc non disponible"
    fi
    
    print_test "API Archives PHP"
    local api_response=$(curl -s -o /dev/null -w "%{http_code},%{time_total}" http://localhost/archives-list.php 2>/dev/null)
    
    if [ -n "$api_response" ]; then
        local api_code=$(echo $api_response | cut -d',' -f1)
        local api_time=$(echo $api_response | cut -d',' -f2)
        
        if [ "$api_code" = "200" ]; then
            if command -v bc >/dev/null 2>&1; then
                local api_ms=$(echo "$api_time * 1000" | bc 2>/dev/null | cut -d. -f1)
                if is_number "$api_ms"; then
                    print_result "OK"
                    print_detail "API PHP: ${api_ms}ms"
                else
                    print_result "OK"
                    print_detail "API PHP: réponse OK"
                fi
            else
                print_result "OK"
                print_detail "API PHP: réponse OK"
            fi
        else
            print_result "WARN"
            print_detail "API PHP: HTTP $api_code"
        fi
    else
        print_result "INFO"
        print_detail "API PHP non testée"
    fi
    
    print_test "Accès via IP AP"
    local ap_response=$(curl -s -o /dev/null -w "%{time_total}" http://192.168.4.1/ 2>/dev/null)
    
    if [ -n "$ap_response" ] && command -v bc >/dev/null 2>&1; then
        local ap_ms=$(echo "$ap_response * 1000" | bc 2>/dev/null | cut -d. -f1)
        
        if is_number "$ap_ms"; then
            if [ "$ap_ms" -lt 200 ]; then
                print_result "OK"
                print_detail "Via WiFi: ${ap_ms}ms"
            else
                print_result "WARN"
                print_detail "Via WiFi: ${ap_ms}ms (lent)"
            fi
        else
            print_result "INFO"
            print_detail "Mesure via WiFi impossible"
        fi
    else
        print_result "INFO"
        print_detail "Test via IP AP non disponible"
    fi
    
    print_test "Latence MQTT"
    local mqtt_start=$(date +%s%N)
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "perf/test" -m "$(date +%s%N)" 2>/dev/null; then
        local mqtt_end=$(date +%s%N)
        local mqtt_latency=$(( (mqtt_end - mqtt_start) / 1000000 ))
        
        if is_number "$mqtt_latency"; then
            if [ "$mqtt_latency" -lt 10 ]; then
                print_result "OK"
                print_detail "Latence: ${mqtt_latency}ms"
            elif [ "$mqtt_latency" -lt 50 ]; then
                print_result "WARN"
                print_detail "Latence élevée: ${mqtt_latency}ms"
            else
                print_result "FAIL"
                print_detail "Latence critique: ${mqtt_latency}ms"
            fi
        else
            print_result "INFO"
            print_detail "Latence MQTT non mesurable"
        fi
    else
        print_result "FAIL"
        print_detail "Échec test latence MQTT"
    fi
    
    print_test "Débit des données widgets"
    local temp_file=$(mktemp)
    timeout 3 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t 'rpi/+/+/+' -v 2>/dev/null > "$temp_file" &
    local sub_pid=$!
    
    sleep 3
    wait $sub_pid 2>/dev/null
    
    local widget_messages=$(wc -l < "$temp_file")
    
    if is_number "$widget_messages" && [ "$widget_messages" -gt 0 ]; then
        local messages_per_sec=$((widget_messages / 3))
        
        if [ "$messages_per_sec" -gt 5 ]; then
            print_result "OK"
            print_detail "$messages_per_sec msg/s"
        elif [ "$messages_per_sec" -gt 2 ]; then
            print_result "WARN"
            print_detail "Débit faible: $messages_per_sec msg/s"
        else
            print_result "FAIL"
            print_detail "Débit critique: $messages_per_sec msg/s"
        fi
    else
        print_result "INFO"
        print_detail "Impossible de mesurer le débit"
    fi
    
    rm -f "$temp_file"
}

# ===============================================================================
# TESTS DE STABILITÉ (INCHANGÉS)
# ===============================================================================

test_stability() {
    print_header "TESTS DE STABILITÉ"
    
    print_test "Stress MQTT (${MQTT_STRESS_DURATION}s, ${MQTT_STRESS_MESSAGES} msg)"
    local start_time=$(date +%s)
    local success_count=0
    
    for i in $(seq 1 $MQTT_STRESS_MESSAGES); do
        if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "stress/test" -m "message_$i" 2>/dev/null; then
            ((success_count++))
        fi
        
        local current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $MQTT_STRESS_DURATION ]; then
            break
        fi
        
        sleep 0.1
    done
    
    if is_number "$success_count" && is_number "$MQTT_STRESS_MESSAGES" && [ "$MQTT_STRESS_MESSAGES" -gt 0 ]; then
        local success_rate=$((success_count * 100 / MQTT_STRESS_MESSAGES))
        if [ "$success_rate" -ge 95 ]; then
            print_result "OK"
            print_detail "$success_count/$MQTT_STRESS_MESSAGES messages (${success_rate}%)"
        elif [ "$success_rate" -ge 80 ]; then
            print_result "WARN"
            print_detail "Performance dégradée: ${success_rate}%"
        else
            print_result "FAIL"
            print_detail "Échec stress test: ${success_rate}%"
        fi
    else
        print_result "INFO"
        print_detail "Test de stress impossible"
    fi
    
    print_test "Stress HTTP (${NETWORK_STRESS_DURATION}s)"
    local http_success=0
    local http_total=0
    local http_start=$(date +%s)
    
    while [ $(($(date +%s) - http_start)) -lt $NETWORK_STRESS_DURATION ]; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200"; then
            ((http_success++))
        fi
        ((http_total++))
        sleep 0.2
    done
    
    if is_number "$http_total" && [ "$http_total" -gt 0 ]; then
        local http_rate=$((http_success * 100 / http_total))
        if [ "$http_rate" -ge 95 ]; then
            print_result "OK"
            print_detail "$http_success/$http_total requêtes (${http_rate}%)"
        else
            print_result "WARN"
            print_detail "Performance HTTP: ${http_rate}%"
        fi
    else
        print_result "INFO"
        print_detail "Test de stress HTTP impossible"
    fi
    
    print_test "Intégrité post-stress"
    local services_ok=true
    
    for service in mosquitto nginx; do
        if ! systemctl is-active --quiet "$service" 2>/dev/null; then
            services_ok=false
            break
        fi
    done
    
    if $services_ok; then
        print_result "OK"
        print_detail "Tous les services restent actifs"
    else
        print_result "FAIL"
        print_detail "Un ou plusieurs services ont échoué"
    fi
}

# ===============================================================================
# TESTS DE RESSOURCES SYSTÈME (INCHANGÉS)
# ===============================================================================

test_system_resources() {
    print_header "RESSOURCES SYSTÈME"
    
    print_test "Charge CPU"
    if command -v bc >/dev/null 2>&1; then
        cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        if [ -n "$cpu_load" ]; then
            cpu_load_int=$(echo "$cpu_load * 100" | bc 2>/dev/null | cut -d. -f1)
            
            if is_number "$cpu_load_int"; then
                if [ "$cpu_load_int" -lt 80 ]; then
                    print_result "OK"
                    print_detail "Charge: ${cpu_load}"
                elif [ "$cpu_load_int" -lt 150 ]; then
                    print_result "WARN"
                    print_detail "Charge élevée: ${cpu_load}"
                else
                    print_result "FAIL"
                    print_detail "Charge critique: ${cpu_load}"
                fi
            else
                print_result "INFO"
                print_detail "Impossible de calculer la charge CPU"
            fi
        else
            print_result "INFO"
            print_detail "Charge CPU non disponible"
        fi
    else
        print_result "INFO"
        print_detail "bc non disponible pour calcul charge CPU"
    fi
    
    print_test "Mémoire disponible"
    mem_info=$(free -m | grep '^Mem:')
    if [ -n "$mem_info" ]; then
        mem_total=$(echo $mem_info | awk '{print $2}')
        mem_used=$(echo $mem_info | awk '{print $3}')
        
        if is_number "$mem_total" && is_number "$mem_used" && [ "$mem_total" -gt 0 ]; then
            mem_percent=$((mem_used * 100 / mem_total))
            
            if [ "$mem_percent" -lt 80 ]; then
                print_result "OK"
                print_detail "Utilisée: ${mem_percent}% (${mem_used}/${mem_total}MB)"
            elif [ "$mem_percent" -lt 90 ]; then
                print_result "WARN"
                print_detail "Utilisation élevée: ${mem_percent}%"
            else
                print_result "FAIL"
                print_detail "Mémoire critique: ${mem_percent}%"
            fi
        else
            print_result "INFO"
            print_detail "Impossible de calculer l'utilisation mémoire"
        fi
    else
        print_result "INFO"
        print_detail "Informations mémoire non disponibles"
    fi
    
    print_test "Espace disque racine"
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if is_number "$disk_usage"; then
        if [ "$disk_usage" -lt 80 ]; then
            print_result "OK"
            print_detail "Utilisé: ${disk_usage}%"
        elif [ "$disk_usage" -lt 90 ]; then
            print_result "WARN"
            print_detail "Espace faible: ${disk_usage}%"
        else
            print_result "FAIL"
            print_detail "Espace critique: ${disk_usage}%"
        fi
    else
        print_result "INFO"
        print_detail "Impossible de mesurer l'espace disque"
    fi
    
    print_test "Température CPU"
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        if is_number "$temp" && [ "$temp" -gt 0 ]; then
            temp_c=$((temp / 1000))
            
            if [ "$temp_c" -lt 60 ]; then
                print_result "OK"
                print_detail "Température: ${temp_c}°C"
            elif [ "$temp_c" -lt 70 ]; then
                print_result "WARN"
                print_detail "Température élevée: ${temp_c}°C"
            else
                print_result "FAIL"
                print_detail "Surchauffe: ${temp_c}°C"
            fi
        else
            print_result "INFO"
            print_detail "Lecture température impossible"
        fi
    else
        print_result "INFO"
        print_detail "Capteur température non disponible"
    fi
    
    # Test spécifique clé USB
    print_test "Clé USB MaxLink"
    if [ -d "/media/prod/USBTOOL" ]; then
        print_result "OK"
        print_detail "Clé USB montée"
    elif [ -d "/media/*/USBTOOL" ]; then
        print_result "OK"
        print_detail "Clé USB trouvée (autre montage)"
    else
        print_result "WARN"
        print_detail "Clé USB non détectée"
    fi
}

# ===============================================================================
# COMPTE RENDU FINAL (VERSION AMÉLIORÉE)
# ===============================================================================

generate_final_report() {
    print_header "COMPTE RENDU DIAGNOSTIC MAXLINK"
    
    local total_issues=$((ERRORS + WARNINGS))
    
    echo "Résultats du diagnostic complet :"
    echo -e "  • Erreurs critiques : ${RED}$ERRORS${NC}"
    echo -e "  • Avertissements    : ${YELLOW}$WARNINGS${NC}"
    echo -e "  • Total problèmes   : $total_issues"
    echo ""
    
    if [ "$OFFLINE_MODE" = true ]; then
        echo -e "  ${CYAN}Mode : Environnement hors-ligne (optimal pour MaxLink)${NC}"
        echo ""
    fi
    
    # Déterminer l'état global de l'installation
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        local all_active=$(python3 -c "
import json
with open('$SERVICES_STATUS_FILE', 'r') as f:
    data = json.load(f)
expected = ['update', 'ap', 'nginx', 'fake_ncsi', 'mqtt', 'mqtt_wgs', 'php_archives', 'orchestrator']
all_active = all(data.get(s, {}).get('status') == 'active' for s in expected)
print('yes' if all_active else 'no')
")
        
        if [ "$all_active" = "yes" ] && [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
            echo -e "${GREEN}✓ SYSTÈME MAXLINK OPTIMAL${NC}"
            echo "  Installation complète et tous les tests sont passés."
            echo "  Le système est stable et performant."
            echo ""
            echo "Accès au système :"
            echo "  • Dashboard    : http://192.168.4.1"
            echo "  • WiFi         : MaxLink-NETWORK"
            echo "  • MQTT         : localhost:1883 (mosquitto/mqtt)"
            echo "  • Archives API : http://192.168.4.1/archives-list.php"
            echo "  • Fake NCSI    : http://192.168.4.1/connecttest.txt"
        elif [ "$all_active" = "yes" ] && [ $ERRORS -eq 0 ]; then
            echo -e "${YELLOW}⚠ SYSTÈME MAXLINK STABLE${NC}"
            echo "  Installation complète avec quelques avertissements mineurs."
            echo "  Le système fonctionne correctement mais surveillance recommandée."
        elif [ "$all_active" = "no" ]; then
            echo -e "${YELLOW}⚠ INSTALLATION INCOMPLÈTE${NC}"
            echo "  Certains composants ne sont pas installés ou inactifs."
            echo ""
            echo "Actions recommandées :"
            echo "  1. Relancer l'installation complète :"
            echo "     sudo bash /media/prod/USBTOOL/scripts/install/full_install_install.sh"
        else
            echo -e "${RED}✗ SYSTÈME MAXLINK CRITIQUE${NC}"
            echo "  Dysfonctionnements majeurs détectés."
            echo "  Intervention urgente requise."
        fi
    else
        echo -e "${YELLOW}⚠ AUCUNE INSTALLATION DÉTECTÉE${NC}"
        echo ""
        echo "Pour installer MaxLink, exécutez :"
        echo "  sudo bash /media/prod/USBTOOL/scripts/install/full_install_install.sh"
    fi
    
    echo ""
    echo "Actions de maintenance disponibles :"
    if [ $ERRORS -gt 0 ]; then
        echo "  • Analyser les logs critiques   : journalctl -u 'maxlink-*' -p err -f"
        echo "  • Redémarrer les services        : /usr/local/bin/maxlink-orchestrator restart"
    fi
    if [ $WARNINGS -gt 0 ]; then
        echo "  • Surveiller les avertissements  : journalctl -u 'maxlink-*' -p warning -f"
        echo "  • Surveiller les performances    : watch -n 2 '/usr/local/bin/maxlink-orchestrator status'"
    fi
    echo "  • État orchestrateur             : /usr/local/bin/maxlink-orchestrator status"
    echo "  • Test MQTT en temps réel        : mosquitto_sub -h localhost -u $MQTT_USER -P $MQTT_PASS -t '#' -v"
    echo "  • Relancer ce diagnostic         : sudo $0"
    
    if [ "$OFFLINE_MODE" = true ]; then
        echo ""
        echo "Mode en ligne (avec tests internet) :"
        echo "  • sudo $0 --online"
    fi
    
    echo ""
    echo "Mode diagnostic rapide (sans analyses détaillées) :"
    echo "  • sudo $0 --quick"
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

main() {
    # Header
    clear
    echo ""
    echo "========================================================================"
    echo "DIAGNOSTIC MAXLINK COMPLET AMÉLIORÉ - $(date)"
    if [ "$OFFLINE_MODE" = true ]; then
        echo "Mode : Environnement hors-ligne (recommandé pour MaxLink)"
    else
        echo "Mode : Tests avec connectivité internet"
    fi
    if [ "$DETAILED_ANALYSIS" = true ]; then
        echo "Analyse : Détaillée (logs et diagnostics approfondis)"
    else
        echo "Analyse : Rapide (tests basiques uniquement)"
    fi
    echo "========================================================================"
    
    # Vérifier les privilèges
    if [ "$EUID" -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠ Ce script nécessite les privilèges root pour un diagnostic complet${NC}"
        echo "  Usage: sudo $0 [--online] [--quick]"
        echo ""
        exit 1
    fi
    
    # Vérifier la disponibilité des outils critiques
    local missing_critical=()
    for tool in python3 curl; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing_critical+=($tool)
        fi
    done
    
    if [ ${#missing_critical[@]} -gt 0 ]; then
        echo -e "${RED}✗ Outils critiques manquants: ${missing_critical[*]}${NC}"
        echo "  Installation de MaxLink impossible à vérifier."
        echo ""
        exit 1
    fi
    
    # Vérifier les outils optionnels
    local missing_optional=()
    for tool in bc mosquitto_pub mosquitto_sub; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing_optional+=($tool)
        fi
    done
    
    if [ ${#missing_optional[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠ Outils optionnels manquants: ${missing_optional[*]}${NC}"
        echo "  Certains tests avancés seront sautés."
        echo ""
    fi
    
    # Exécuter tous les tests dans l'ordre
    check_installation_status
    test_maxlink_services
    test_systemd_services
    test_orchestrator
    test_network_advanced
    test_mqtt_data_flow
    test_performance
    test_stability
    test_system_resources
    
    # Compte rendu final
    generate_final_report
    
    echo ""
    echo "========================================================================"
    echo "DIAGNOSTIC TERMINÉ"
    echo "========================================================================"
    echo ""
    
    # Code de sortie basé sur les erreurs
    exit $ERRORS
}

# Lancer le diagnostic complet
main "$@"