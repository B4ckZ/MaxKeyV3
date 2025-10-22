#!/bin/bash

set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

SERVICES_STATUS_FILE="/var/lib/maxlink/services_status.json"
MQTT_USER="${MQTT_USER:-mosquitto}"
MQTT_PASS="${MQTT_PASS:-mqtt}"
MQTT_PORT="${MQTT_PORT:-1883}"
MQTT_WEBSOCKET_PORT="${MQTT_WEBSOCKET_PORT:-9001}"

REPORT_FILE="/tmp/maxlink_diag_$(date +%Y%m%d_%H%M%S).json"
QUIET_MODE=0
TEST_FILTER=""

print_header() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "========================================================================"
}

print_test() {
    printf "%-55s" "◦ $1"
    ((TESTS_TOTAL++))
}

print_result() {
    local status=$1
    case $status in
        "OK")
            echo -e "${GREEN}[OK]${NC}"
            ((TESTS_PASSED++))
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC}"
            ((TESTS_FAILED++))
            ((ERRORS++))
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC}"
            ((TESTS_FAILED++))
            ((WARNINGS++))
            ;;
        "SKIP")
            echo -e "${CYAN}[SKIP]${NC}"
            ;;
        *)
            echo -e "${CYAN}[$status]${NC}"
            ;;
    esac
}

print_detail() {
    echo "    ↦ $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "⚠ Ce script nécessite les privilèges root"
        exit 1
    fi
}

should_run_test() {
    [ -z "$TEST_FILTER" ] && return 0
    [[ "$1" == *"$TEST_FILTER"* ]] && return 0
    return 1
}

check_installation_status() {
    should_run_test "installation" || return 0
    print_header "ÉTAT DE L'INSTALLATION"

    print_test "Fichier de statuts"
    if [ -f "$SERVICES_STATUS_FILE" ]; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Fichier manquant: $SERVICES_STATUS_FILE"
        return 1
    fi

    print_test "Répertoire /var/lib/maxlink"
    if [ -d "/var/lib/maxlink" ]; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Répertoire manquant"
        ((ERRORS++))
    fi

    print_test "Cache système"
    if [ -d "/var/cache/maxlink" ]; then
        local cache_size=$(du -sh /var/cache/maxlink 2>/dev/null | cut -f1)
        print_result "OK"
        print_detail "Taille: $cache_size"
    else
        print_result "WARN"
        print_detail "Répertoire cache absent"
    fi

    print_test "Dashboard installé"
    if [ -d "/var/www/maxlink-dashboard" ]; then
        local dashboard_files=$(find /var/www/maxlink-dashboard -type f | wc -l)
        print_result "OK"
        print_detail "Fichiers: $dashboard_files"
    else
        print_result "FAIL"
        print_detail "Dashboard manquant"
        ((ERRORS++))
    fi

    print_test "Logs centralisés"
    if [ -d "/var/log/maxlink" ]; then
        local log_size=$(du -sh /var/log/maxlink 2>/dev/null | cut -f1)
        print_result "OK"
        print_detail "Taille: $log_size"
    else
        print_result "WARN"
        print_detail "Répertoire logs absent"
    fi
}

check_core_services() {
    should_run_test "services" || return 0
    print_header "SERVICES CRITIQUES"

    local services=(
        "mosquitto:Broker MQTT:mqtt"
        "nginx:Serveur Web:web"
        "NetworkManager:Gestionnaire Réseau:network"
        "php8.2-fpm:PHP-FPM:php"
    )

    for service_info in "${services[@]}"; do
        IFS=':' read -r service_name service_desc service_tag <<< "$service_info"

        print_test "$service_desc"

        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
            print_result "OK"

            local since=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value 2>/dev/null | cut -d' ' -f1-2)
            [ -n "$since" ] && print_detail "Actif depuis: $since"

            local failed_count=$(journalctl -u "$service_name" --since "1 hour ago" -p err --no-pager 2>/dev/null | wc -l)
            if [ "$failed_count" -gt 0 ]; then
                print_detail "⚠ $failed_count erreurs (1h)"
                ((WARNINGS++))
            fi
        else
            print_result "FAIL"
            print_detail "Service inactif"
            ((ERRORS++))
        fi
    done
}

check_orchestrator() {
    should_run_test "orchestrator" || return 0
    print_header "ORCHESTRATEUR MAXLINK"

    print_test "Binaire orchestrateur"
    if [ -x "/usr/local/bin/maxlink-orchestrator" ]; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Binaire manquant ou non exécutable"
        return 1
    fi

    print_test "Commande status"
    if timeout 5 /usr/local/bin/maxlink-orchestrator status >/dev/null 2>&1; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Commande status échouée"
    fi

    local healthchecks=(
        "/usr/local/bin/maxlink-check-ap:AP WiFi"
        "/usr/local/bin/maxlink-check-nginx:Nginx"
        "/usr/local/bin/maxlink-check-mqtt:MQTT"
    )

    for check_info in "${healthchecks[@]}"; do
        IFS=':' read -r script_path script_name <<< "$check_info"

        print_test "Healthcheck: $script_name"
        if [ -x "$script_path" ]; then
            if timeout 5 "$script_path" >/dev/null 2>&1; then
                print_result "OK"
            else
                print_result "WARN"
                print_detail "Healthcheck échoué"
                ((WARNINGS++))
            fi
        else
            print_result "FAIL"
            print_detail "Script manquant"
            ((ERRORS++))
        fi
    done

    print_test "Targets systemd"
    local targets=(
        "maxlink-early.target"
        "maxlink-pre-network.target"
        "maxlink-network.target"
        "maxlink-post-network.target"
    )

    local missing_targets=0
    for target in "${targets[@]}"; do
        [ -f "/etc/systemd/system/$target" ] || ((missing_targets++))
    done

    if [ "$missing_targets" -eq 0 ]; then
        print_result "OK"
        print_detail "4/4 targets détectés"
    else
        print_result "WARN"
        print_detail "$missing_targets targets manquants"
        ((WARNINGS++))
    fi
}

check_network() {
    should_run_test "network" || return 0
    print_header "CONFIGURATION RÉSEAU"

    print_test "Interface WiFi (wlan0)"
    if ip link show wlan0 >/dev/null 2>&1; then
        print_result "OK"

        local mode="Unknown"
        if iw dev wlan0 info 2>/dev/null | grep -q "type AP"; then
            mode="Access Point"
            local clients=$(iw dev wlan0 station dump 2>/dev/null | grep -c "Station")
            print_detail "Mode: $mode | Clients: $clients"
        else
            mode="Client/Inactif"
            print_detail "Mode: $mode"
        fi
    else
        print_result "FAIL"
        print_detail "Interface wlan0 absente"
        ((ERRORS++))
    fi

    print_test "Point d'accès MaxLink"
    if nmcli con show --active 2>/dev/null | grep -q "MaxLink-AP" || nmcli con show --active 2>/dev/null | grep -q "MaxLink-NETWORK"; then
        print_result "OK"
        local ssid=$(nmcli con show --active 2>/dev/null | grep -E "MaxLink-AP|MaxLink-NETWORK" | awk '{print $1}')
        print_detail "SSID: $ssid"
    else
        print_result "WARN"
        print_detail "Point d'accès pas en mode actif"
        ((WARNINGS++))
    fi

    print_test "Résolveur DNS"
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "systemd-resolved inactif"
        ((WARNINGS++))
    fi

    local ports=(
        "80:HTTP (Nginx)"
        "443:HTTPS"
        "1883:MQTT"
        "9001:WebSocket MQTT"
    )

    print_test "Ports réseau"
    local open_ports=0
    for port_info in "${ports[@]}"; do
        IFS=':' read -r port_num port_desc <<< "$port_info"
        if ss -tlnp 2>/dev/null | grep -q ":$port_num " || netstat -tlnp 2>/dev/null | grep -q ":$port_num "; then
            ((open_ports++))
        fi
    done

    if [ "$open_ports" -ge 3 ]; then
        print_result "OK"
        print_detail "$open_ports/4 ports ouverts"
    else
        print_result "WARN"
        print_detail "$open_ports/4 ports ouverts"
        ((WARNINGS++))
    fi
}

check_mqtt_broker() {
    should_run_test "mqtt" || return 0
    print_header "BROKER MQTT"

    print_test "Service Mosquitto"
    if systemctl is-active --quiet mosquitto; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Service inactif"
        return 1
    fi

    print_test "Connexion MQTT"
    if mosquitto_pub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "diag/test" -m "test" 2>/dev/null; then
        print_result "OK"
    else
        print_result "FAIL"
        print_detail "Impossible de publier"
        ((ERRORS++))
        return 1
    fi

    print_test "Topics système (\$SYS)"
    local broker_version=$(timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '$SYS/broker/version' -C 1 2>/dev/null)
    if [ -n "$broker_version" ]; then
        print_result "OK"
        print_detail "Version: $broker_version"
    else
        print_result "WARN"
        print_detail "Topics système inaccessibles"
        ((WARNINGS++))
    fi

    print_test "Collecte données (3s)"
    local temp_file=$(mktemp)
    timeout 3 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t '#' 2>/dev/null > "$temp_file" &
    sleep 3.5
    wait 2>/dev/null
    local msg_count=$(wc -l < "$temp_file" 2>/dev/null || echo 0)
    rm -f "$temp_file"

    if [ "$msg_count" -gt 0 ]; then
        print_result "OK"
        print_detail "$msg_count messages reçus"
    else
        print_result "WARN"
        print_detail "Aucun message reçu"
        ((WARNINGS++))
    fi

    print_test "WebSocket MQTT (port 9001)"
    if nc -z -w 2 localhost $MQTT_WEBSOCKET_PORT 2>/dev/null || ss -tlnp 2>/dev/null | grep -q ":$MQTT_WEBSOCKET_PORT "; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "WebSocket non accessible"
        ((WARNINGS++))
    fi

    print_test "Topics réels - Résultats tests"
    local test_results=$(timeout 2 mosquitto_sub -h localhost -p $MQTT_PORT -u "$MQTT_USER" -P "$MQTT_PASS" -t "SOUFFLAGE/+/ESP32/result" -C 1 2>/dev/null)
    if [ -n "$test_results" ]; then
        print_result "OK"
        print_detail "Données reçues des ESP32"
    else
        print_result "INFO"
        print_detail "Aucune donnée ESP32 actuellement"
    fi
}

check_web_services() {
    should_run_test "web" || return 0
    print_header "SERVICES WEB"

    print_test "Nginx - Port 80"
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/ 2>/dev/null)
    if [ "$http_code" = "200" ]; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Code HTTP: $http_code"
        ((WARNINGS++))
    fi

    print_test "Dashboard principal"
    if [ -f "/var/www/maxlink-dashboard/index.html" ]; then
        print_result "OK"
        local size=$(stat -f%z /var/www/maxlink-dashboard/index.html 2>/dev/null || stat -c%s /var/www/maxlink-dashboard/index.html 2>/dev/null)
        print_detail "Taille: $size bytes"
    else
        print_result "FAIL"
        print_detail "Fichier manquant"
        ((ERRORS++))
    fi

    print_test "WebSocket Dashboard"
    if grep -r "WebSocket\|websocket" /var/www/maxlink-dashboard/ 2>/dev/null | grep -q "js"; then
        print_result "OK"
        print_detail "Support WebSocket détecté"
    else
        print_result "WARN"
        print_detail "Configuration WebSocket douteuse"
        ((WARNINGS++))
    fi

    print_test "Widgets installés"
    local widget_services=($(systemctl list-unit-files 2>/dev/null | grep "maxlink-widget-" | awk '{print $1}' | wc -l))
    if [ "$widget_services" -gt 0 ]; then
        print_result "OK"
        print_detail "$widget_services widgets détectés"
    else
        print_result "WARN"
        print_detail "Aucun widget systemd trouvé"
        ((WARNINGS++))
    fi

    print_test "API Archives PHP"
    local archive_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/archives-list.php 2>/dev/null)
    if [ "$archive_code" = "200" ]; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Code HTTP: $archive_code"
        ((WARNINGS++))
    fi

    print_test "Répertoire archives"
    if [ -d "/var/www/maxlink-dashboard/archives" ]; then
        local archive_count=$(find /var/www/maxlink-dashboard/archives -name "*.csv" 2>/dev/null | wc -l)
        print_result "OK"
        print_detail "$archive_count fichiers CSV"
    else
        print_result "WARN"
        print_detail "Répertoire manquant"
        ((WARNINGS++))
    fi
}

check_fake_ncsi() {
    should_run_test "ncsi" || return 0
    print_header "FAKE NCSI (CONNECTIVITÉ WINDOWS)"

    print_test "Point de terminaison connecttest.txt"
    local ncsi_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost/connecttest.txt 2>/dev/null)
    if [ "$ncsi_code" = "200" ]; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Code HTTP: $ncsi_code"
        ((WARNINGS++))
    fi

    print_test "Configuration DHCP Windows"
    if [ -f "/etc/NetworkManager/dnsmasq-shared.d/01-windows-connectivity-hint.conf" ]; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Configuration DHCP manquante"
        ((WARNINGS++))
    fi
}

check_system_resources() {
    should_run_test "resources" || return 0
    print_header "RESSOURCES SYSTÈME"

    print_test "CPU utilization"
    local cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
    print_result "OK"
    print_detail "CPU: ${cpu}%"

    print_test "Mémoire disponible"
    local mem_available=$(free -m | awk 'NR==2 {print int($7)}')
    local mem_total=$(free -m | awk 'NR==2 {print $2}')
    print_result "OK"
    if [ "$mem_available" -lt 200 ]; then
        print_detail "Mémoire: ${mem_available}/${mem_total}MB (⚠ faible)"
        ((WARNINGS++))
    else
        print_detail "Mémoire: ${mem_available}/${mem_total}MB"
    fi

    print_test "Espace disque"
    local disk_free=$(df / | awk 'NR==2 {print int($4/1024)}')
    local disk_total=$(df / | awk 'NR==2 {print int($2/1024)}')
    print_result "OK"
    if [ "$disk_free" -lt 500 ]; then
        print_detail "Disque: ${disk_free}/${disk_total}MB (⚠ faible)"
        ((WARNINGS++))
    else
        print_detail "Disque: ${disk_free}/${disk_total}MB"
    fi

    print_test "Température CPU"
    local temp=$(vcgencmd measure_temp 2>/dev/null | grep -oP '\d+\.\d+' || echo "N/A")
    if [ "$temp" != "N/A" ]; then
        print_result "OK"
        if (( $(echo "$temp > 70" | bc -l) )); then
            print_detail "Température: ${temp}°C (⚠ élevée)"
            ((WARNINGS++))
        else
            print_detail "Température: ${temp}°C"
        fi
    else
        print_result "SKIP"
        print_detail "Capteur non disponible"
    fi

    print_test "Uptime système"
    local uptime=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}')
    print_result "OK"
    print_detail "$uptime"
}

check_dependency_chain() {
    should_run_test "dependencies" || return 0
    print_header "CHAÎNE DE DÉPENDANCES"

    print_test "NetworkManager → Système"
    if systemctl show NetworkManager -p Requires | grep -q "system-online.target"; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "Dépendance réseau douteuse"
        ((WARNINGS++))
    fi

    print_test "MQTT → Network target"
    if systemctl show mosquitto -p After 2>/dev/null | grep -q "network"; then
        print_result "OK"
    else
        print_result "WARN"
        print_detail "MQTT ne dépend pas du réseau"
        ((WARNINGS++))
    fi

    print_test "Nginx → MQTT"
    if systemctl show nginx -p After 2>/dev/null | grep -q "mosquitto"; then
        print_result "OK"
    else
        print_result "INFO"
        print_detail "Nginx indépendant de MQTT (comportement normal)"
    fi

    print_test "Ordre de démarrage séquencé"
    if [ -f "/etc/systemd/system/maxlink-early.target" ] && [ -f "/etc/systemd/system/maxlink-post-network.target" ]; then
        print_result "OK"
        print_detail "Targets présents"
    else
        print_result "WARN"
        print_detail "Targets manquants"
        ((WARNINGS++))
    fi
}

generate_report() {
    cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname)",
  "summary": {
    "tests_total": $TESTS_TOTAL,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "errors": $ERRORS,
    "warnings": $WARNINGS,
    "success_rate": $(( TESTS_PASSED * 100 / TESTS_TOTAL ))
  },
  "status": "$([ $ERRORS -eq 0 ] && echo 'OK' || echo 'ERRORS')"
}
EOF
}

print_summary() {
    echo ""
    print_header "RÉSUMÉ DIAGNOSTIC"
    echo ""
    echo "  Tests exécutés:  $TESTS_TOTAL"
    echo "  Réussis:         $TESTS_PASSED"
    echo "  Échoués:         $TESTS_FAILED"
    echo "  Erreurs:         $ERRORS"
    echo "  Avertissements:  $WARNINGS"
    echo ""

    local success_rate=$(( TESTS_PASSED * 100 / TESTS_TOTAL ))
    echo -n "  Taux de réussite: "
    if [ $success_rate -ge 90 ]; then
        echo -e "${GREEN}${success_rate}%${NC}"
    elif [ $success_rate -ge 70 ]; then
        echo -e "${YELLOW}${success_rate}%${NC}"
    else
        echo -e "${RED}${success_rate}%${NC}"
    fi

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "\n${GREEN}✓ Système en bon état${NC}"
    elif [ $ERRORS -eq 0 ]; then
        echo -e "\n${YELLOW}⚠ Système fonctionnel avec avertissements${NC}"
    else
        echo -e "\n${RED}✗ Problèmes détectés${NC}"
    fi

    echo ""
    echo "Rapport JSON: $REPORT_FILE"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help          Affiche cette aide
  -q, --quiet         Mode silencieux (JSON uniquement)
  -f, --filter TEST   Exécute uniquement le test spécifié
  -r, --report        Génère le rapport JSON complet

Filtres disponibles:
  installation    État d'installation
  services        Services critiques
  orchestrator    Orchestrateur et healthchecks
  network         Configuration réseau
  mqtt            Broker MQTT
  web             Services web
  ncsi            Fake NCSI
  resources       Ressources système
  dependencies    Chaîne de dépendances

Exemples:
  sudo $0
  sudo $0 --filter mqtt
  sudo $0 --filter network --report
EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -q|--quiet)
                QUIET_MODE=1
                ;;
            -f|--filter)
                TEST_FILTER="$2"
                shift
                ;;
            -r|--report)
                ;;
            *)
                echo "Option inconnue: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done

    check_root

    if [ $QUIET_MODE -eq 0 ]; then
        clear
        echo ""
        echo "========================================================================"
        echo " MAXLINK™ - DIAGNOSTIC COMPLET V2"
        echo " © 2025 WERIT - Diagnostic amélioré du système"
        echo "========================================================================"
    fi

    check_installation_status
    check_core_services
    check_orchestrator
    check_network
    check_mqtt_broker
    check_web_services
    check_fake_ncsi
    check_system_resources
    check_dependency_chain

    generate_report

    if [ $QUIET_MODE -eq 0 ]; then
        print_summary
    fi

    exit $([ $ERRORS -eq 0 ] && echo 0 || echo 1)
}

main "$@"