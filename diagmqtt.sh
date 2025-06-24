#!/bin/bash

# ==============================================================================
# DIAGNOSTIC DU SYSTÈME DE PERSISTANCE DES RÉSULTATS DE TESTS
# Script de vérification complète du widget testpersist
# ==============================================================================

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
STORAGE_DIR="/var/www/traçabilité"
SERVICE_NAME="maxlink-widget-testpersist"
MQTT_USER="mosquitto"
MQTT_PASS="mqtt"
MQTT_PORT="1883"
ERRORS=0
WARNINGS=0

# Fonction d'affichage
print_header() {
    echo ""
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}  DIAGNOSTIC SYSTÈME DE PERSISTANCE MAXLINK${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo ""
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

# ===============================================================================
# 1. VÉRIFICATION DU SERVICE
# ===============================================================================

check_service() {
    echo -e "${BLUE}▶ VÉRIFICATION DU SERVICE${NC}"
    echo "========================================"
    
    # État du service
    printf "%-40s" "◦ Service testpersist"
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[ACTIF]${NC}"
    else
        echo -e "${RED}[INACTIF]${NC}"
        ((ERRORS++))
        
        # Afficher les dernières lignes du journal
        echo ""
        echo "Dernières lignes du journal :"
        journalctl -u "$SERVICE_NAME" -n 10 --no-pager
        echo ""
    fi
    
    # Vérifier si le service est activé
    printf "%-40s" "◦ Démarrage automatique"
    if systemctl is-enabled --quiet "$SERVICE_NAME"; then
        echo -e "${GREEN}[ACTIVÉ]${NC}"
    else
        echo -e "${YELLOW}[DÉSACTIVÉ]${NC}"
        ((WARNINGS++))
    fi
    
    # Temps de fonctionnement
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        uptime=$(systemctl show "$SERVICE_NAME" --property=ActiveEnterTimestamp | cut -d'=' -f2)
        if [ -n "$uptime" ]; then
            echo "  ↦ Démarré depuis: $uptime"
        fi
    fi
    
    echo ""
}

# ===============================================================================
# 2. VÉRIFICATION DES FICHIERS DE STOCKAGE
# ===============================================================================

check_storage() {
    echo -e "${BLUE}▶ VÉRIFICATION DU STOCKAGE${NC}"
    echo "========================================"
    
    # Répertoire de stockage
    printf "%-40s" "◦ Répertoire $STORAGE_DIR"
    if [ -d "$STORAGE_DIR" ]; then
        echo -e "${GREEN}[EXISTE]${NC}"
        
        # Permissions
        perms=$(stat -c %a "$STORAGE_DIR")
        owner=$(stat -c %U:%G "$STORAGE_DIR")
        echo "  ↦ Permissions: $perms ($owner)"
    else
        echo -e "${RED}[MANQUANT]${NC}"
        ((ERRORS++))
    fi
    
    # Vérifier chaque fichier JSON
    echo ""
    echo "◦ Fichiers de données:"
    for machine in 509 511 998 999; do
        filepath="$STORAGE_DIR/${machine}.json"
        printf "  • %-30s" "${machine}.json"
        
        if [ -f "$filepath" ]; then
            size=$(stat -c%s "$filepath" 2>/dev/null || echo "0")
            lines=$(wc -l < "$filepath" 2>/dev/null || echo "0")
            
            # Convertir la taille en format lisible
            if [ "$size" -gt 1048576 ]; then
                size_h=$(echo "scale=2; $size/1048576" | bc)
                size_unit="MB"
            elif [ "$size" -gt 1024 ]; then
                size_h=$(echo "scale=2; $size/1024" | bc)
                size_unit="KB"
            else
                size_h=$size
                size_unit="B"
            fi
            
            echo -e "${GREEN}[OK]${NC} - $lines lignes, ${size_h}${size_unit}"
            
            # Vérifier la dernière ligne si le fichier n'est pas vide
            if [ "$lines" -gt 0 ]; then
                last_line=$(tail -1 "$filepath" 2>/dev/null)
                if echo "$last_line" | python3 -m json.tool >/dev/null 2>&1; then
                    # Extraire le timestamp de la dernière entrée
                    timestamp=$(echo "$last_line" | python3 -c "import json,sys; print(json.load(sys.stdin).get('timestamp', 'N/A'))" 2>/dev/null)
                    echo "    ↦ Dernière entrée: $timestamp"
                else
                    echo -e "    ↦ ${YELLOW}Dernière ligne invalide${NC}"
                    ((WARNINGS++))
                fi
            fi
        else
            echo -e "${YELLOW}[ABSENT]${NC}"
            ((WARNINGS++))
        fi
    done
    
    echo ""
}

# ===============================================================================
# 3. TEST DE CONNEXION MQTT
# ===============================================================================

check_mqtt() {
    echo -e "${BLUE}▶ VÉRIFICATION MQTT${NC}"
    echo "========================================"
    
    # Test de connexion au broker
    printf "%-40s" "◦ Connexion au broker MQTT"
    if mosquitto_pub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "test/diag/ping" -m "test" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}"
    else
        echo -e "${RED}[ÉCHEC]${NC}"
        ((ERRORS++))
    fi
    
    # Vérifier l'écoute des topics
    echo ""
    echo "◦ Test d'écoute des topics (5 secondes)..."
    
    # Créer un fichier temporaire pour stocker les résultats
    TEMP_FILE=$(mktemp)
    
    # Écouter les topics pendant 5 secondes
    timeout 5 mosquitto_sub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "SOUFFLAGE/+/ESP32/result/confirmed" -v 2>/dev/null > "$TEMP_FILE" &
    
    SUB_PID=$!
    
    # Afficher une barre de progression
    echo -n "  "
    for i in {1..5}; do
        echo -n "."
        sleep 1
    done
    echo ""
    
    # Analyser les résultats
    if [ -s "$TEMP_FILE" ]; then
        echo -e "  ↦ ${GREEN}Messages confirmés reçus :${NC}"
        cat "$TEMP_FILE" | while read line; do
            echo "    • $line"
        done
    else
        echo -e "  ↦ ${YELLOW}Aucun message confirmé reçu${NC}"
    fi
    
    rm -f "$TEMP_FILE"
    
    echo ""
}

# ===============================================================================
# 4. TEST D'ENVOI ET PERSISTANCE
# ===============================================================================

test_persistence() {
    echo -e "${BLUE}▶ TEST DE PERSISTANCE${NC}"
    echo "========================================"
    
    echo "◦ Envoi d'un message de test..."
    
    # Générer un code-barres de test avec timestamp
    TIMESTAMP=$(date '+%d-%m-%YT%H:%M:%S')
    TEST_BARCODE="15052551100000000$(date +%s)"
    TEST_MACHINE="511"
    
    # Créer le JSON de test
    TEST_JSON="{\"timestamp\":\"$TIMESTAMP\",\"team\":\"TEST\",\"barcode\":\"$TEST_BARCODE\",\"result\":\"OK\"}"
    
    echo "  • Machine: $TEST_MACHINE"
    echo "  • Barcode: $TEST_BARCODE"
    echo "  • JSON: $TEST_JSON"
    echo ""
    
    # Compter les lignes avant
    LINES_BEFORE=$(wc -l < "$STORAGE_DIR/${TEST_MACHINE}.json" 2>/dev/null || echo "0")
    
    # Envoyer le message
    printf "%-40s" "◦ Envoi sur MQTT"
    if mosquitto_pub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "SOUFFLAGE/$TEST_MACHINE/ESP32/result" -m "$TEST_JSON" 2>/dev/null; then
        echo -e "${GREEN}[ENVOYÉ]${NC}"
    else
        echo -e "${RED}[ÉCHEC]${NC}"
        ((ERRORS++))
        return
    fi
    
    # Attendre un peu pour la persistance
    echo "  ↦ Attente de la persistance (3 sec)..."
    sleep 3
    
    # Vérifier la persistance
    LINES_AFTER=$(wc -l < "$STORAGE_DIR/${TEST_MACHINE}.json" 2>/dev/null || echo "0")
    
    printf "%-40s" "◦ Vérification de la persistance"
    if [ "$LINES_AFTER" -gt "$LINES_BEFORE" ]; then
        echo -e "${GREEN}[RÉUSSI]${NC}"
        echo "  ↦ Lignes avant: $LINES_BEFORE"
        echo "  ↦ Lignes après: $LINES_AFTER"
        
        # Vérifier que notre test est bien présent
        if grep -q "$TEST_BARCODE" "$STORAGE_DIR/${TEST_MACHINE}.json"; then
            echo -e "  ↦ ${GREEN}Message de test trouvé dans le fichier${NC}"
        else
            echo -e "  ↦ ${RED}Message de test non trouvé${NC}"
            ((ERRORS++))
        fi
    else
        echo -e "${RED}[ÉCHEC]${NC}"
        echo "  ↦ Aucune nouvelle ligne ajoutée"
        ((ERRORS++))
    fi
    
    # Écouter la confirmation
    echo ""
    echo "◦ Écoute de la confirmation (5 sec)..."
    CONFIRM_RECEIVED=false
    
    timeout 5 mosquitto_sub -h localhost -p "$MQTT_PORT" -u "$MQTT_USER" -P "$MQTT_PASS" \
        -t "SOUFFLAGE/$TEST_MACHINE/ESP32/result/confirmed" -C 1 2>/dev/null | grep -q "$TEST_BARCODE"
    
    if [ $? -eq 0 ]; then
        echo -e "  ↦ ${GREEN}Confirmation reçue${NC}"
    else
        echo -e "  ↦ ${YELLOW}Pas de confirmation reçue${NC}"
        ((WARNINGS++))
    fi
    
    echo ""
}

# ===============================================================================
# 5. VÉRIFICATION DES LOGS
# ===============================================================================

check_logs() {
    echo -e "${BLUE}▶ ANALYSE DES LOGS${NC}"
    echo "========================================"
    
    echo "◦ Derniers logs du service (20 lignes):"
    echo ""
    
    journalctl -u "$SERVICE_NAME" -n 20 --no-pager | while IFS= read -r line; do
        if echo "$line" | grep -q "ERROR"; then
            echo -e "${RED}$line${NC}"
        elif echo "$line" | grep -q "WARNING"; then
            echo -e "${YELLOW}$line${NC}"
        elif echo "$line" | grep -q "persisté et confirmé"; then
            echo -e "${GREEN}$line${NC}"
        else
            echo "$line"
        fi
    done
    
    echo ""
}

# ===============================================================================
# 6. RÉSUMÉ
# ===============================================================================

print_summary() {
    echo -e "${BLUE}▶ RÉSUMÉ DU DIAGNOSTIC${NC}"
    echo "========================================"
    
    TOTAL_ISSUES=$((ERRORS + WARNINGS))
    
    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        echo -e "${GREEN}✓ Système opérationnel - Aucun problème détecté${NC}"
    else
        if [ $ERRORS -gt 0 ]; then
            echo -e "${RED}✗ $ERRORS erreur(s) critique(s) détectée(s)${NC}"
        fi
        if [ $WARNINGS -gt 0 ]; then
            echo -e "${YELLOW}⚠ $WARNINGS avertissement(s)${NC}"
        fi
    fi
    
    echo ""
    echo "Recommandations:"
    
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "• Le service est actif ✓"
    else
        echo -e "• ${RED}Démarrer le service: sudo systemctl start $SERVICE_NAME${NC}"
    fi
    
    if [ ! -d "$STORAGE_DIR" ]; then
        echo -e "• ${RED}Créer le répertoire: sudo mkdir -p $STORAGE_DIR${NC}"
    fi
    
    if [ $WARNINGS -gt 0 ]; then
        echo -e "• ${YELLOW}Vérifier les permissions des fichiers${NC}"
        echo -e "• ${YELLOW}Consulter les logs pour plus de détails${NC}"
    fi
    
    echo ""
}

# ===============================================================================
# PROGRAMME PRINCIPAL
# ===============================================================================

# Vérifier les privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté avec sudo"
    exit 1
fi

# Exécuter le diagnostic
print_header
check_service
check_storage
check_mqtt
test_persistence
check_logs
print_summary

# Code de sortie basé sur les erreurs
exit $ERRORS