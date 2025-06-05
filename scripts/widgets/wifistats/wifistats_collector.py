#!/usr/bin/env python3
"""
Collecteur de statistiques WiFi pour le widget WiFi Stats
Version corrigée pour utiliser les chemins locaux
"""

import os
import sys
import time
import json
import subprocess
import re
import logging
from datetime import datetime
from pathlib import Path

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('wifistats')

try:
    import paho.mqtt.client as mqtt
except ImportError:
    logger.error("Module paho-mqtt non installé")
    sys.exit(1)

# IMPORTANT: Ajouter le chemin du core au PYTHONPATH
sys.path.insert(0, '/opt/maxlink/widgets/_core')
try:
    from collector_base import BaseCollector
except ImportError:
    logger.error("Impossible d'importer BaseCollector depuis /opt/maxlink/widgets/_core")
    sys.exit(1)

class WiFiStatsCollector(BaseCollector):
    def __init__(self, config_file):
        """Initialise le collecteur"""
        super().__init__(config_file, 'wifistats')
        
        # Intervalle de mise à jour défini directement dans le collector
        self.update_interval = 1  # 1 seconde pour voir les connexions/déconnexions rapidement
        
        # Interface WiFi (généralement wlan0)
        self.interface = "wlan0"
        
        # Cache pour stocker les temps de connexion
        self.client_first_seen = {}
        
        logger.info(f"Intervalle de mise à jour: {self.update_interval}s")
    
    def on_mqtt_connected(self):
        """Appelé quand la connexion MQTT est établie"""
        logger.info("Connecté au broker MQTT - début de la collecte des stats WiFi")
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        logger.info(f"Initialisation du collecteur WiFi Stats sur interface {self.interface}")
        
        # Vérifier que l'interface existe
        try:
            result = subprocess.run(['ip', 'link', 'show', self.interface], 
                                  capture_output=True, text=True)
            if result.returncode != 0:
                logger.warning(f"Interface {self.interface} non trouvée")
            else:
                logger.info(f"Interface {self.interface} disponible")
        except Exception as e:
            logger.error(f"Erreur vérification interface: {e}")
    
    def get_update_interval(self):
        """Retourne l'intervalle de mise à jour"""
        return self.update_interval
    
    def format_uptime(self, seconds):
        """Formate l'uptime en format lisible"""
        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        
        # Format complet avec padding : 00j 00h 00m 00s
        return f"{days:02d}j {hours:02d}h {minutes:02d}m {secs:02d}s"
    
    def get_ap_clients(self):
        """Récupère la liste simplifiée des clients connectés"""
        clients = []
        
        try:
            # Vérifier que l'interface existe et est en mode AP
            check_cmd = f"iw dev {self.interface} info"
            check_result = subprocess.run(check_cmd.split(), capture_output=True, text=True)
            
            if check_result.returncode != 0 or 'type AP' not in check_result.stdout:
                logger.debug("Interface non en mode AP ou non disponible")
                return clients
            
            # Utiliser iw pour lister les stations
            cmd = f"iw dev {self.interface} station dump"
            result = subprocess.run(cmd.split(), capture_output=True, text=True)
            
            if result.returncode == 0:
                current_client = {}
                
                for line in result.stdout.split('\n'):
                    if line.startswith('Station'):
                        # Nouveau client
                        if current_client and 'mac' in current_client:
                            clients.append(current_client)
                        
                        mac = line.split()[1]
                        current_client = {'mac': mac}
                        
                    elif 'connected time:' in line:
                        # Temps de connexion en secondes
                        match = re.search(r'connected time:\s*(\d+)', line)
                        if match:
                            connected_seconds = int(match.group(1))
                            current_client['uptime'] = self.format_uptime(connected_seconds)
                
                # Ajouter le dernier client
                if current_client and 'mac' in current_client:
                    clients.append(current_client)
            
            # Enrichir avec les noms depuis DHCP
            self._enrich_with_names(clients)
            
        except Exception as e:
            logger.error(f"Erreur récupération clients: {e}")
            self.stats['errors'] += 1
        
        return clients
    
    def _enrich_with_names(self, clients):
        """Ajoute uniquement les noms des devices"""
        try:
            # Lire le fichier de leases dnsmasq
            leases_file = "/var/lib/misc/dnsmasq.leases"
            if os.path.exists(leases_file):
                with open(leases_file, 'r') as f:
                    for line in f:
                        parts = line.strip().split()
                        if len(parts) >= 4:
                            mac = parts[1].lower()
                            name = parts[3] if parts[3] != '*' else None
                            
                            # Chercher le client correspondant
                            for client in clients:
                                if client.get('mac', '').lower() == mac:
                                    if name and name != '*':
                                        client['name'] = name
                                    break
        except Exception as e:
            logger.debug(f"Impossible de lire les leases DHCP: {e}")
        
        # Si pas de nom, utiliser un nom générique basé sur le MAC
        for client in clients:
            if 'name' not in client:
                client['name'] = self._get_device_name(client['mac'])
            # S'assurer qu'il y a toujours un uptime
            if 'uptime' not in client:
                client['uptime'] = '00j 00h 00m 00s'
    
    def _get_device_name(self, mac):
        """Génère un nom basique basé sur le MAC"""
        # Utiliser les 3 derniers octets du MAC pour créer un nom unique
        mac_suffix = mac.replace(':', '')[-6:].upper()
        return f"Device-{mac_suffix}"
    
    def get_ap_status(self):
        """Récupère l'état basique de l'AP"""
        status = {
            'ssid': None,
            'mode': 'unknown'
        }
        
        try:
            cmd = f"iw dev {self.interface} info"
            result = subprocess.run(cmd.split(), capture_output=True, text=True)
            
            if result.returncode == 0:
                for line in result.stdout.split('\n'):
                    if 'ssid' in line:
                        match = re.search(r'ssid\s+(.+)', line)
                        if match:
                            status['ssid'] = match.group(1)
                    elif 'type' in line:
                        if 'AP' in line:
                            status['mode'] = 'AP'
                        elif 'managed' in line:
                            status['mode'] = 'client'
        
        except Exception as e:
            logger.error(f"Erreur récupération status AP: {e}")
        
        return status
    
    def collect_and_publish(self):
        """Collecte et publie les données simplifiées"""
        try:
            # Récupérer les clients
            clients = self.get_ap_clients()
            
            # Format simplifié : juste nom, MAC et uptime
            simplified_clients = []
            for client in clients:
                simplified_clients.append({
                    'name': client.get('name', 'Unknown'),
                    'mac': client.get('mac', ''),
                    'uptime': client.get('uptime', '00j 00h 00m 00s')
                })
            
            # Publier la liste des clients
            self.publish_data("rpi/network/wifi/clients", {
                "clients": simplified_clients,
                "count": len(simplified_clients)
            })
            
            # Récupérer et publier le status minimal
            status = self.get_ap_status()
            status['clients_count'] = len(clients)
            
            self.publish_data("rpi/network/wifi/status", status)
            
            logger.debug(f"Données publiées - {len(clients)} clients")
            
        except Exception as e:
            logger.error(f"Erreur collecte/publication: {e}")
            self.stats['errors'] += 1

if __name__ == "__main__":
    # Configuration
    config_file = os.environ.get('CONFIG_FILE')
    
    if not config_file and len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    if not config_file:
        config_file = "/opt/maxlink/config/widgets/wifistats_widget.json"
    
    # Log du démarrage
    logger.info("="*60)
    logger.info("Démarrage du collecteur WiFi Stats")
    logger.info(f"Config recherchée dans: {config_file}")
    logger.info(f"Répertoire de travail: {os.getcwd()}")
    logger.info("="*60)
    
    # Lancer le collecteur
    collector = WiFiStatsCollector(config_file)
    collector.run()