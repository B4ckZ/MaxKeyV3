#!/usr/bin/env python3
"""
Collecteur de synchronisation temps MaxLink - Version simplifiée
Synchronisation automatique uniquement
"""

import json
import time
import subprocess
import logging
import os
import sys
from datetime import datetime
import paho.mqtt.client as mqtt

# Configuration du logging simplifié
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/maxlink/timesync.log')
    ]
)
logger = logging.getLogger('timesync')

class TimeSyncCollector:
    def __init__(self, config_file=None):
        self.config = self.load_config(config_file)
        self.client = None
        self.running = False
        
        # Topics MQTT simplifiés
        self.topics = {
            'time_publish': 'rpi/system/time',
            'sync_command': 'system/time/sync/command',
            'sync_result': 'system/time/sync/result'
        }
        
        logger.info("Collecteur TimSync MaxLink simplifié initialisé")
    
    def load_config(self, config_file):
        """Charge la configuration"""
        default_config = {
            'mqtt': {
                'host': 'localhost',
                'port': 1883,
                'username': 'maxlink',
                'password': 'maxlink123'
            },
            'time': {
                'publish_interval': 10,
                'max_drift_seconds': 180
            }
        }
        
        if config_file and os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    file_config = json.load(f)
                    if 'mqtt' in file_config:
                        default_config['mqtt'].update(file_config['mqtt'])
                    if 'time' in file_config:
                        default_config['time'].update(file_config['time'])
            except Exception as e:
                logger.error(f"Erreur lecture config: {e}")
        
        return default_config
    
    def connect_mqtt(self):
        """Connexion au broker MQTT"""
        try:
            self.client = mqtt.Client()
            mqtt_config = self.config['mqtt']
            self.client.username_pw_set(mqtt_config['username'], mqtt_config['password'])
            
            self.client.on_connect = self.on_connect
            self.client.on_message = self.on_message
            
            self.client.connect(mqtt_config['host'], mqtt_config['port'], 60)
            logger.info(f"Connexion MQTT: {mqtt_config['host']}:{mqtt_config['port']}")
            return True
            
        except Exception as e:
            logger.error(f"Erreur connexion MQTT: {e}")
            return False
    
    def on_connect(self, client, userdata, flags, rc):
        """Callback de connexion MQTT"""
        if rc == 0:
            logger.info("Connecté au broker MQTT")
            client.subscribe(self.topics['sync_command'])
        else:
            logger.error(f"Échec connexion MQTT: {rc}")
    
    def on_message(self, client, userdata, msg):
        """Traitement des messages MQTT"""
        try:
            topic = msg.topic
            payload = json.loads(msg.payload.decode())
            
            if topic == self.topics['sync_command']:
                self.handle_sync_command(payload)
                
        except Exception as e:
            logger.error(f"Erreur traitement message: {e}")
    
    def handle_sync_command(self, payload):
        """Exécuter une synchronisation temps"""
        try:
            if payload.get('action') != 'set_time':
                return
            
            new_timestamp = payload.get('timestamp')
            source_mac = payload.get('source_mac', 'unknown')
            
            if not new_timestamp:
                self.publish_sync_result('error', 'Timestamp manquant')
                return
            
            # Vérifier le décalage
            current_time = time.time()
            drift_seconds = abs(current_time - new_timestamp)
            
            logger.info(f"Sync demandée - Source: {source_mac}, Décalage: {drift_seconds:.1f}s")
            
            if drift_seconds < 2:
                self.publish_sync_result('skipped', 'Décalage acceptable')
                return
            
            # Effectuer la synchronisation
            if self.perform_time_sync(new_timestamp):
                logger.info(f"Synchronisation réussie - Correction: {drift_seconds:.1f}s")
                self.publish_sync_result('success', f'Synchronisé (correction: {drift_seconds:.1f}s)')
            else:
                logger.error("Échec synchronisation")
                self.publish_sync_result('error', 'Échec synchronisation système')
            
        except Exception as e:
            logger.error(f"Erreur synchronisation: {e}")
            self.publish_sync_result('error', str(e))
    
    def perform_time_sync(self, timestamp):
        """Effectue la synchronisation système"""
        try:
            new_datetime = datetime.fromtimestamp(timestamp)
            datetime_str = new_datetime.strftime('%Y-%m-%d %H:%M:%S')
            
            # Synchroniser l'heure
            subprocess.run(['sudo', 'timedatectl', 'set-ntp', 'false'], check=True, capture_output=True)
            subprocess.run(['sudo', 'timedatectl', 'set-time', datetime_str], check=True, capture_output=True)
            time.sleep(1)
            subprocess.run(['sudo', 'timedatectl', 'set-ntp', 'true'], check=True, capture_output=True)
            
            logger.info(f"Heure système: {datetime_str}")
            return True
            
        except Exception as e:
            logger.error(f"Erreur commande système: {e}")
            return False
    
    def publish_sync_result(self, status, message):
        """Publier le résultat de synchronisation"""
        try:
            result = {
                'status': status,
                'message': message,
                'timestamp': time.time()
            }
            
            self.client.publish(self.topics['sync_result'], json.dumps(result))
            
        except Exception as e:
            logger.error(f"Erreur publication résultat: {e}")
    
    def publish_periodic_time(self):
        """Publier l'heure périodiquement"""
        try:
            current_time = time.time()
            
            time_data = {
                'timestamp': current_time,
                'iso_time': datetime.fromtimestamp(current_time).isoformat(),
                'uptime_seconds': self.get_uptime_seconds(),
                'source': 'rpi_rtc'
            }
            
            self.client.publish(self.topics['time_publish'], json.dumps(time_data))
            
        except Exception as e:
            logger.error(f"Erreur publication: {e}")
    
    def get_uptime_seconds(self):
        """Récupérer l'uptime système"""
        try:
            with open('/proc/uptime', 'r') as f:
                return int(float(f.read().split()[0]))
        except:
            return 0
    
    def run(self):
        """Boucle principale"""
        logger.info("Démarrage collecteur TimSync")
        
        if not self.connect_mqtt():
            logger.error("Impossible de se connecter à MQTT")
            return
        
        self.client.loop_start()
        self.running = True
        
        try:
            publish_interval = self.config['time']['publish_interval']
            
            while self.running:
                self.publish_periodic_time()
                time.sleep(publish_interval)
                
        except KeyboardInterrupt:
            logger.info("Arrêt demandé")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Nettoyage"""
        self.running = False
        if self.client:
            self.client.loop_stop()
            self.client.disconnect()
        logger.info("Collecteur arrêté")

if __name__ == "__main__":
    config_file = "/opt/maxlink/config/widgets/timesync_widget.json"
    if len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    os.makedirs('/var/log/maxlink', exist_ok=True)
    
    collector = TimeSyncCollector(config_file)
    collector.run()