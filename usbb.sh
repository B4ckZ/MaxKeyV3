#!/bin/bash

echo "============================================================"
echo " DEBUG MQTT USB - $(date)"
echo "============================================================"

echo ""
echo "1. VÉRIFICATION DES TOPICS MQTT ACTIFS"
echo "------------------------------------------------------------"
echo "Écoute de TOUS les topics système pendant 5 secondes..."
echo "(Pour voir ce qui est réellement publié)"
echo ""

timeout 5 mosquitto_sub -h localhost -u mosquitto -P mqtt -t "rpi/system/+/+" -v | while read line; do
    echo "$(date +%H:%M:%S) $line"
done

echo ""
echo "2. TEST DE PUBLICATION MANUELLE"
echo "------------------------------------------------------------"
echo "Test de publication sur le topic USB..."

# Publier un message de test
mosquitto_pub -h localhost -u mosquitto -P mqtt -t "rpi/system/memory/usb" -m '{"timestamp":"2025-06-21T10:00:00Z","value":25.5,"unit":"%"}' && echo "✅ Publication réussie" || echo "❌ Échec de publication"

echo ""
echo "Vérification de la réception..."
timeout 2 mosquitto_sub -h localhost -u mosquitto -P mqtt -t "rpi/system/memory/usb" -C 1 -v && echo "✅ Message reçu" || echo "❌ Pas de message"

echo ""
echo "3. VÉRIFICATION DU COLLECTEUR PYTHON"
echo "------------------------------------------------------------"
echo "Recherche de logs d'erreur liés à l'USB dans le service..."
echo ""

sudo journalctl -u maxlink-widget-servermonitoring | grep -i "usb\|error" | tail -20

echo ""
echo "4. TEST DIRECT DU COLLECTEUR"
echo "------------------------------------------------------------"
echo "Exécution directe du collecteur pour voir les erreurs..."
echo "(Arrêter avec Ctrl+C après quelques secondes)"
echo ""

# Arrêter temporairement le service
sudo systemctl stop maxlink-widget-servermonitoring

echo "Service arrêté. Lancement du collecteur en mode debug..."
echo "Attendre 35 secondes pour voir la publication USB (intervalle slow=30s)..."
echo ""

# Lancer le collecteur directement
cd /opt/maxlink/widgets/servermonitoring
timeout 40 sudo -u prod python3 servermonitoring_collector.py 2>&1 | grep -E "USB|usb|Erreur|error|memory/usb"

# Redémarrer le service
echo ""
echo "Redémarrage du service..."
sudo systemctl start maxlink-widget-servermonitoring

echo ""
echo "5. VÉRIFICATION DE L'USAGE DISQUE"
echo "------------------------------------------------------------"
echo "Usage actuel de la clé USB:"
df -h /media/prod/MAXLINKSAVE

echo ""
echo "Test avec Python et psutil:"
python3 -c "
import psutil
try:
    usage = psutil.disk_usage('/media/prod/MAXLINKSAVE')
    print(f'Pourcentage utilisé: {usage.percent}%')
    print(f'Total: {usage.total / (1024**3):.2f} GB')
    print(f'Libre: {usage.free / (1024**3):.2f} GB')
except Exception as e:
    print(f'Erreur: {e}')
"

echo ""
echo "============================================================"
echo "ANALYSE"
echo "============================================================"
echo ""
echo "Si le collecteur trouve la clé mais ne publie pas sur MQTT,"
echo "c'est probablement que la fonction publish_metric() pour l'USB"
echo "n'est pas appelée ou échoue silencieusement."
echo ""