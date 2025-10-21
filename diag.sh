#!/bin/bash

# ===============================================================================
# MAXLINK - DIAGNOSTIC COMPLET UNIFIÉ
# Script unique pour diagnostic complet avec tests de stabilité
# Une commande, un compte rendu complet automatique
# ===============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# ===============================================================================
# ÉTAT DE L'INSTALLATION
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
            
        print(f"    {color}{symbol}\033[0m {service_name:20} : {status}")
        
        # Afficher la date de mise à jour si disponible
        if 'last_update' in info:
            try:
                dt = datetime.fromisoformat(info['last_update'])
                print(f"      ↦ Mis à jour: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
            except:
                pass
    else:
        all_active = False
        print(f"    ○ {service_name:20} : non installé")

print("")
if all_active:
    print("    \033[0;32m✓ Installation complète réussie !\033[0m")
else:
    print("    \033[1;33m⚠ Installation incomplète\033[0m")
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
# TESTS DES SERVICES MAXLINK
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
                    esac
                    ;;
                "inactive") print_result "FAIL" ;;
                "error") print_result "WARN"; print_detail "Erreur lecture statut" ;;
                *) print_result "WARN"; print_detail "Statut: $status" ;;
            esac
        done
    else
        print_test "Fichier de statuts"
        print_result "FAIL"
        print_detail "Fichier $SERVICES_STATUS_FILE non trouvé"
    fi
}

test_nginx_detailed() {
    print_detail "Test dashboard principal"
    if curl -s -o /dev/null -w "%{http_code}" http://localhost/ | grep -q "200"; then
        print_detail "  ✓ Dashboard accessible"
    else
        print_detail "  ✗ Dashboard inaccessible"
        ((WARNINGS++))
    fi
    
    print_detail "Test API archives PHP"
    if curl -s -o /dev/null -w "%{http_code}" http://localhost/archives-list.php | grep -q "200"; then
        print_detail "  ✓ API archives accessible"
    else
        print_detail "  ⚠ API archives problématique"
    fi
}

test_mqtt_detailed() {
    print_detail "Test publication MQTT"
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/diagnostic" -m "$(date)" 2>/dev/null; then
        print_detail "  ✓ Publication réussie"
    else
        print_detail "  ✗ Échec publication"
        ((WARNINGS++))
    fi
    
    print_detail "Test souscription MQTT"
    if timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/diagnostic" -C 1 2>/dev/null | grep -q "$(date +%Y)"; then
        print_detail "  ✓ Souscription réussie"
    else
        print_detail "  ⚠ Souscription problématique"
    fi
}

test_fake_ncsi_detailed() {
    print_detail "Test endpoints Windows NCSI"
    
    if curl -s --connect-timeout 3 "http://localhost/connecttest.txt" | grep -q "Microsoft" 2>/dev/null; then
        print_detail "  ✓ connecttest.txt fonctionnel"
    else
        print_detail "  ✗ connecttest.txt non accessible"
        ((WARNINGS++))
    fi
    
    if curl -s --connect-timeout 3 "http://localhost/generate_204" >/dev/null 2>&1; then
        print_detail "  ✓ generate_204 fonctionnel"
    else
        print_detail "  ✗ generate_204 non accessible"
        ((WARNINGS++))
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
    else
        print_detail "  ✗ Répertoire archives manquant"
        ((WARNINGS++))
    fi
}

# ===============================================================================
# TESTS DES SERVICES SYSTEMD
# ===============================================================================

test_systemd_services() {
    print_header "SERVICES SYSTEMD"
    
    local critical_services=(
        "mosquitto:Broker MQTT"
        "nginx:Serveur Web"
        "NetworkManager:Gestionnaire réseau"
        "php8.2-fpm:PHP-FPM"
    )
    
    for service_info in "${critical_services[@]}"; do
        IFS=':' read -r service_name service_desc <<< "$service_info"
        
        print_test "$service_desc"
        
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            print_result "OK"
            
            local uptime=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value 2>/dev/null)
            if [ -n "$uptime" ] && [ "$uptime" != "n/a" ]; then
                print_detail "Actif depuis: $(echo $uptime | cut -d' ' -f1-2)"
            fi
            
            local failed_count=$(journalctl -u "$service_name" --since "1 hour ago" -p err --no-pager | wc -l)
            if [ "$failed_count" -gt 0 ]; then
                print_detail "⚠ $failed_count erreurs dans la dernière heure"
            fi
        else
            print_result "FAIL"
            print_detail "Service inactif ou inexistant"
        fi
    done
    
    print_test "Widgets MaxLink"
    local widget_services=($(systemctl list-unit-files | grep "maxlink-widget-" | awk '{print $1}'))
    local active_widgets=0
    local total_widgets=${#widget_services[@]}
    
    for widget in "${widget_services[@]}"; do
        if systemctl is-active --quiet "$widget" 2>/dev/null; then
            ((active_widgets++))
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
    fi
}

# ===============================================================================
# TESTS DE L'ORCHESTRATEUR
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
    
    local healthcheck_scripts=(
        "/usr/local/bin/maxlink-check-ap:Point d'accès"
        "/usr/local/bin/maxlink-check-nginx:Nginx"
        "/usr/local/bin/maxlink-check-mqtt:MQTT"
    )
    
    for script_info in "${healthcheck_scripts[@]}"; do
        IFS=':' read -r script_path script_desc <<< "$script_info"
        
        print_test "Healthcheck $script_desc"
        if [ -x "$script_path" ]; then
            if timeout 5 "$script_path" >/dev/null 2>&1; then
                print_result "OK"
            else
                print_result "WARN"
                print_detail "Healthcheck échoué"
            fi
        else
            print_result "FAIL"
            print_detail "Script manquant: $script_path"
        fi
    done
}

# ===============================================================================
# TESTS RÉSEAU AVANCÉS
# ===============================================================================

test_network_advanced() {
    print_header "TESTS RÉSEAU AVANCÉS"
    
    print_test "Interface WiFi (wlan0)"
    if ip link show wlan0 >/dev/null 2>&1; then
        print_result "OK"
        
        if iw dev wlan0 info 2>/dev/null | grep -q "type AP"; then
            print_detail "Mode: Access Point"
            local client_count=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station")
            print_detail "Clients WiFi: $client_count"
        else
            print_detail "Mode: Client ou inactif"
        fi
    else
        print_result "FAIL"
        print_detail "Interface WiFi absente"
    fi
    
    local ports=(
        "80:HTTP (Nginx)"
        "1883:MQTT"
        "9001:WebSocket MQTT"
    )
    
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port_num port_desc <<< "$port_info"
        
        print_test "Port $port_num ($port_desc)"
        if netstat -tlnp 2>/dev/null | grep -q ":$port_num " || ss -tlnp 2>/dev/null | grep -q ":$port_num "; then
            print_result "OK"
        else
            print_result "FAIL"
            print_detail "Port fermé ou service arrêté"
        fi
    done
    
    print_test "Connectivité locale"
    if ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Problème réseau local"
    fi
}

# ===============================================================================
# TESTS DE DONNÉES MQTT
# ===============================================================================

test_mqtt_data_flow() {
    print_header "FLUX DE DONNÉES MQTT"
    
    print_test "Connexion broker"
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "test/connection" -m "test" 2>/dev/null; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Impossible de se connecter au broker"
        return
    fi
    
    print_test "Topics système (\$SYS)"
    local version=$(timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null)
    if [ -n "$version" ]; then
        print_result "OK"
        print_detail "Version: $version"
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
    else
        print_result "WARN"
        print_detail "Aucun message collecté"
    fi
    
    rm -f "$temp_file"
}

# ===============================================================================
# TESTS DE PERFORMANCE
# ===============================================================================

test_performance() {
    print_header "TESTS DE PERFORMANCE"
    
    print_test "Temps de réponse HTTP"
    local response_time=$(curl -s -o /dev/null -w "%{time_total}" http://localhost/ 2>/dev/null)
    
    if [ -n "$response_time" ] && command -v bc >/dev/null 2>&1; then
        local response_ms=$(echo "$response_time * 1000" | bc 2>/dev/null | cut -d. -f1)
        
        if [ "$response_ms" -lt 100 ]; then
            print_result "OK"
            print_detail "Temps: ${response_ms}ms"
        elif [ "$response_ms" -lt 500 ]; then
            print_result "WARN"
            print_detail "Lent: ${response_ms}ms"
        else
            print_result "FAIL"
            print_detail "Très lent: ${response_ms}ms"
        fi
    else
        print_result "INFO"
        print_detail "Impossible de mesurer le temps de réponse"
    fi
    
    print_test "Latence MQTT"
    local mqtt_start=$(date +%s%N)
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "perf/test" -m "$(date +%s%N)" 2>/dev/null; then
        local mqtt_end=$(date +%s%N)
        local mqtt_latency=$(( (mqtt_end - mqtt_start) / 1000000 ))
        
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
    
    rm -f "$temp_file"
}

# ===============================================================================
# TESTS DE STABILITÉ ET STRESS
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
    
    if [ "$http_total" -gt 0 ]; then
        local http_rate=$((http_success * 100 / http_total))
        if [ "$http_rate" -ge 95 ]; then
            print_result "OK"
            print_detail "$http_success/$http_total requêtes (${http_rate}%)"
        else
            print_result "WARN"
            print_detail "Performance HTTP: ${http_rate}%"
        fi
    else
        print_result "FAIL"
        print_detail "Aucune requête HTTP réussie"
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
# TESTS DE RESSOURCES SYSTÈME
# ===============================================================================

test_system_resources() {
    print_header "RESSOURCES SYSTÈME"
    
    print_test "Charge CPU"
    if command -v bc >/dev/null 2>&1; then
        cpu_load=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        cpu_load_int=$(echo "$cpu_load * 100" | bc 2>/dev/null | cut -d. -f1)
        
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
        print_detail "bc non disponible pour calcul charge CPU"
    fi
    
    print_test "Mémoire disponible"
    mem_info=$(free -m | grep '^Mem:')
    mem_total=$(echo $mem_info | awk '{print $2}')
    mem_used=$(echo $mem_info | awk '{print $3}')
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
    
    print_test "Espace disque racine"
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
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
    
    print_test "Température CPU"
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
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
        print_detail "Capteur température non disponible"
    fi
}

# ===============================================================================
# COMPTE RENDU FINAL
# ===============================================================================

generate_final_report() {
    print_header "COMPTE RENDU DIAGNOSTIC MAXLINK"
    
    local total_issues=$((ERRORS + WARNINGS))
    
    echo "Résultats du diagnostic complet :"
    echo -e "  • Erreurs critiques : ${RED}$ERRORS${NC}"
    echo -e "  • Avertissements    : ${YELLOW}$WARNINGS${NC}"
    echo -e "  • Total problèmes   : $total_issues"
    echo ""
    
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
            echo "     sudo bash /media/prod/USBTOOL/full_install.sh"
        else
            echo -e "${RED}✗ SYSTÈME MAXLINK CRITIQUE${NC}"
            echo "  Dysfonctionnements majeurs détectés."
            echo "  Intervention urgente requise."
        fi
    else
        echo -e "${YELLOW}⚠ AUCUNE INSTALLATION DÉTECTÉE${NC}"
        echo ""
        echo "Pour installer MaxLink, exécutez :"
        echo "  sudo bash /media/prod/USBTOOL/full_install.sh"
    fi
    
    echo ""
    echo "Actions de maintenance disponibles :"
    if [ $ERRORS -gt 0 ]; then
        echo "  • Analyser les logs        : journalctl -u 'maxlink-*' -f"
        echo "  • Redémarrer les services  : /usr/local/bin/maxlink-orchestrator restart-all"
    fi
    if [ $WARNINGS -gt 0 ]; then
        echo "  • Surveiller les performances : watch -n 2 '/usr/local/bin/maxlink-orchestrator status'"
    fi
    echo "  • État orchestrateur       : /usr/local/bin/maxlink-orchestrator status"
    echo "  • Test MQTT en temps réel  : mosquitto_sub -h localhost -u $MQTT_USER -P $MQTT_PASS -t '#' -v"
    echo "  • Relancer ce diagnostic   : sudo $0"
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

main() {
    # Header
    clear
    echo ""
    echo "========================================================================"
    echo "DIAGNOSTIC MAXLINK COMPLET - $(date)"
    echo "========================================================================"
    
    # Vérifier les privilèges
    if [ "$EUID" -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠ Ce script nécessite les privilèges root pour un diagnostic complet${NC}"
        echo "  Usage: sudo $0"
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
main