#!/bin/bash

# ===============================================================================
# MONITEUR CONNEXION TEMPS RÉEL - RASPBERRY PI
# Surveille exactement ce qui se passe quand Windows se connecte
# ===============================================================================

LOG_FILE="/tmp/connection_monitor.log"
RASPBERRY_IP="192.168.4.1"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "========================================================================"
echo "MONITEUR CONNEXION TEMPS RÉEL - RASPBERRY PI"
echo "========================================================================"
echo ""
echo "Ce script surveille ce qui se passe côté Raspberry Pi"
echo "quand un client Windows tente de se connecter."
echo ""
echo "INSTRUCTIONS:"
echo "1. Lancez ce script"
echo "2. Tentez de vous connecter au WiFi depuis Windows"
echo "3. Observez les délais et goulots d'étranglement"
echo ""
echo "Log détaillé: $LOG_FILE"
echo "========================================================================"
echo ""

# Initialiser le log
echo "=== DÉBUT MONITORING CONNEXION ===" > $LOG_FILE
echo "Date: $(date)" >> $LOG_FILE
echo "" >> $LOG_FILE

# Fonction pour logger avec timestamp
log_with_time() {
    local message="$1"
    local color="$2"
    local timestamp=$(date '+%H:%M:%S.%3N')
    
    if [ -n "$color" ]; then
        echo -e "${color}[$timestamp]${NC} $message"
    else
        echo "[$timestamp] $message"
    fi
    
    echo "[$timestamp] $message" >> $LOG_FILE
}

# Fonction pour tester la latence nginx
test_nginx_latency() {
    local start_time=$(date +%s%3N)
    local result=$(curl -s -w "%{http_code},%{time_total}" -o /dev/null "http://$RASPBERRY_IP/connecttest.txt" 2>/dev/null)
    local end_time=$(date +%s%3N)
    local total_time=$((end_time - start_time))
    
    if [ $? -eq 0 ]; then
        local http_code=$(echo $result | cut -d',' -f1)
        local curl_time=$(echo $result | cut -d',' -f2)
        echo "$http_code,$total_time,$curl_time"
    else
        echo "ERROR,$total_time,0"
    fi
}

# Fonction pour compter les clients DHCP
count_dhcp_clients() {
    local clients=$(awk '/^[0-9]/ {print $2}' /var/lib/dhcp/dhcpd.leases 2>/dev/null | sort | uniq | wc -l)
    echo $clients
}

# État initial
log_with_time "=== ÉTAT INITIAL ===" $CYAN

# Vérifier les services
services=("nginx" "NetworkManager" "mosquitto")
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        log_with_time "Service $service: ACTIF" $GREEN
    else
        log_with_time "Service $service: INACTIF" $RED
    fi
done

# Vérifier l'AP
if nmcli con show --active | grep -q "MaxLink-NETWORK"; then
    log_with_time "MaxLink-NETWORK: ACTIF" $GREEN
else
    log_with_time "MaxLink-NETWORK: INACTIF" $RED
fi

# Test initial nginx
nginx_test=$(test_nginx_latency)
log_with_time "Test nginx initial: $nginx_test" $BLUE

# Charge CPU initiale
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
log_with_time "CPU initial: ${cpu_usage}% - Load: $load_avg" $YELLOW

echo ""
log_with_time "=== SURVEILLANCE EN TEMPS RÉEL ===" $CYAN
log_with_time "Connectez-vous maintenant au WiFi depuis Windows..." $PURPLE
echo ""

# Variables de surveillance
last_client_count=0
last_dhcp_activity=""
last_nginx_status=""
connection_start_time=""
first_connection_detected=false

# Boucle de surveillance principale
while true; do
    current_time=$(date +%s%3N)
    
    # 1. Surveiller les nouveaux clients DHCP
    current_clients=$(count_dhcp_clients)
    if [ "$current_clients" -ne "$last_client_count" ]; then
        if [ "$current_clients" -gt "$last_client_count" ]; then
            log_with_time "NOUVEAU CLIENT DHCP détecté! Total: $current_clients" $GREEN
            connection_start_time=$current_time
            first_connection_detected=true
        else
            log_with_time "Client DHCP déconnecté. Total: $current_clients" $RED
        fi
        last_client_count=$current_clients
    fi
    
    # 2. Surveiller l'activité dnsmasq (dernières lignes de log)
    latest_dnsmasq=$(journalctl -u NetworkManager --since "5 seconds ago" -n 3 --no-pager -q 2>/dev/null | grep -i "dnsmasq\|dhcp" | tail -1)
    if [ -n "$latest_dnsmasq" ] && [ "$latest_dnsmasq" != "$last_dhcp_activity" ]; then
        log_with_time "DHCP: $(echo $latest_dnsmasq | cut -c1-80)..." $YELLOW
        last_dhcp_activity="$latest_dnsmasq"
    fi
    
    # 3. Tester nginx en continu (seulement si connexion détectée)
    if [ "$first_connection_detected" = true ]; then
        nginx_result=$(test_nginx_latency)
        IFS=',' read -r http_code total_time curl_time <<< "$nginx_result"
        
        if [ "$http_code" = "200" ]; then
            if [ "$total_time" -gt 1000 ]; then
                log_with_time "nginx: OK mais LENT (${total_time}ms)" $YELLOW
            elif [ "$total_time" -gt 500 ]; then
                log_with_time "nginx: OK (${total_time}ms)" $BLUE
            else
                log_with_time "nginx: OK rapide (${total_time}ms)" $GREEN
            fi
        else
            log_with_time "nginx: ÉCHEC (${http_code}) après ${total_time}ms" $RED
        fi
        
        # Calculer le temps depuis la première connexion
        if [ -n "$connection_start_time" ]; then
            time_since_connection=$(( (current_time - connection_start_time) / 1000 ))
            if [ $time_since_connection -gt 30 ]; then
                log_with_time "Plus de 30s depuis la connexion - reset surveillance" $PURPLE
                first_connection_detected=false
                connection_start_time=""
            fi
        fi
    fi
    
    # 4. Surveiller la charge CPU pendant les connexions
    if [ "$first_connection_detected" = true ]; then
        cpu_current=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
        cpu_int=${cpu_current%.*}  # Partie entière
        if [ "$cpu_int" -gt 70 ]; then
            log_with_time "CHARGE CPU ÉLEVÉE: ${cpu_current}%" $RED
            # Afficher les processus gourmands
            top_processes=$(ps aux --sort=-%cpu | head -4 | tail -3 | awk '{print $11}' | tr '\n' ', ')
            log_with_time "Processus: $top_processes" $RED
        fi
    fi
    
    # 5. Surveiller les connexions réseau actives
    active_connections=$(ss -tuln | grep ":80\|:443\|:1883" | wc -l)
    if [ "$first_connection_detected" = true ] && [ "$active_connections" -gt 5 ]; then
        log_with_time "Connexions réseau actives: $active_connections" $YELLOW
    fi
    
    # 6. Détecter les erreurs dans les logs système
    recent_errors=$(journalctl --since "2 seconds ago" -p err -q --no-pager | tail -1)
    if [ -n "$recent_errors" ]; then
        log_with_time "ERREUR SYSTÈME: $(echo $recent_errors | cut -c1-80)" $RED
    fi
    
    sleep 1
done