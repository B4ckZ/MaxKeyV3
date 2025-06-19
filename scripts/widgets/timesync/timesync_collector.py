#!/usr/bin/env python3
"""
Collecteur de synchronisation temps MaxLink - Version simplifiée
Sans NTP, utilisation du RTC comme source primaire
Avec redémarrage automatique des services après synchronisation
"""

import json
import time
import subprocess
import logging
import os
import sys
from datetime import datetime
import paho.mqtt.client as mqtt

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger('timesync')

class TimeSyncCollector:
    def __init__(self, config_file=None):
        self.config = self.load_config(config_file)
        self.client = None
        self.running = False
        
        # Topics MQTT
        self.topics = {
            'time_publish': 'rpi/system/time',
            'sync_command': 'system/time/sync/command',
            'sync_result': 'system/time/sync/result'
        }
        
        # Services à redémarrer après synchronisation
        self.services_to_restart = [
            'maxlink-widget-servermonitoring',
            'maxlink-widget-mqttstats'
        ]
        
        logger.info("Collecteur TimSync simplifié initialisé (sans NTP)")
    
    def load_config(self, config_file):
        """Charge la configuration"""
        default_config = {
            'mqtt': {
                'host': 'localhost',
                'port': 1883,
                'username': 'mosquitto',
                'password': 'mqtt'
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
                        default_config['mqtt'].update(file_config['mqtt']['broker'])
                    if 'time' in file_config:
                        default_config['time'].update(file_config['time'])
                logger.info(f"Configuration chargée depuis {config_file}")
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
            logger.info("Abonné aux commandes de synchronisation")
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
    
    def restart_affected_services(self):
        """Redémarre les services affectés par le changement d'heure"""
        logger.info("Redémarrage des services affectés par le changement d'heure...")
        
        for service in self.services_to_restart:
            try:
                # Vérifier si le service existe et est actif
                check_result = subprocess.run(
                    ['systemctl', 'is-active', service],
                    capture_output=True,
                    text=True
                )
                
                if check_result.returncode == 0:  # Service actif
                    logger.info(f"  → Redémarrage de {service}...")
                    
                    # Redémarrer le service
                    restart_result = subprocess.run(
                        ['systemctl', 'restart', service],
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    
                    # Attendre un peu pour laisser le service démarrer
                    time.sleep(1)
                    
                    # Vérifier le statut après redémarrage
                    status_result = subprocess.run(
                        ['systemctl', 'is-active', service],
                        capture_output=True,
                        text=True
                    )
                    
                    if status_result.returncode == 0:
                        logger.info(f"  ✓ {service} redémarré avec succès")
                    else:
                        logger.warning(f"  ✗ {service} n'est pas actif après redémarrage")
                else:
                    logger.debug(f"  - {service} n'est pas actif, pas de redémarrage nécessaire")
                    
            except subprocess.CalledProcessError as e:
                logger.error(f"  ✗ Erreur lors du redémarrage de {service}: {e}")
            except Exception as e:
                logger.error(f"  ✗ Erreur inattendue pour {service}: {e}")
        
        logger.info("Processus de redémarrage terminé")
    
    def handle_sync_command(self, payload):
        """Exécuter une synchronisation temps"""
        try:
            if payload.get('action') != 'set_time':
                logger.warning(f"Action inconnue: {payload.get('action')}")
                return
            
            new_timestamp = payload.get('timestamp')
            source_mac = payload.get('source_mac', 'unknown')
            source = payload.get('source', 'unknown')
            
            if not new_timestamp:
                logger.error("Timestamp manquant dans commande sync")
                self.publish_sync_result('error', 'Timestamp manquant')
                return
            
            # Vérifier le décalage
            current_time = time.time()
            drift_seconds = abs(current_time - new_timestamp)
            direction = "avant" if new_timestamp > current_time else "arrière"
            
            logger.info(f"Sync demandée - Source: {source_mac} ({source})")
            logger.info(f"Décalage: {drift_seconds:.1f}s en {direction}")
            
            # Toujours synchroniser si le décalage est significatif
            if drift_seconds < 2:
                logger.info("Décalage négligeable - pas de synchronisation")
                self.publish_sync_result('skipped', f'Décalage négligeable ({drift_seconds:.1f}s)')
                return
            
            # Effectuer la synchronisation
            if self.perform_time_sync(new_timestamp):
                message = f'Synchronisé ({drift_seconds:.1f}s en {direction})'
                logger.info(f"Synchronisation réussie - {message}")
                self.publish_sync_result('success', message)
                
                # Redémarrer les services affectés
                self.restart_affected_services()
                
                # Forcer une republication immédiate de l'heure
                time.sleep(0.5)  # Petite pause pour laisser le système se stabiliser
                self.publish_periodic_time()
            else:
                logger.error("Échec synchronisation")
                self.publish_sync_result('error', 'Échec synchronisation système')
            
        except Exception as e:
            logger.error(f"Erreur synchronisation: {e}")
            self.publish_sync_result('error', str(e))
    
    def perform_time_sync(self, timestamp):
        """Effectue la synchronisation système - Version simple sans NTP"""
        try:
            new_datetime = datetime.fromtimestamp(timestamp)
            datetime_str = new_datetime.strftime('%Y-%m-%d %H:%M:%S')
            
            logger.info(f"Changement de l'heure système vers: {datetime_str}")
            
            # Simple changement d'heure avec date
            result = subprocess.run(
                ['date', '-s', datetime_str], 
                check=True, 
                capture_output=True, 
                text=True
            )
            
            if result.returncode != 0:
                logger.error(f"Erreur commande date: {result.stderr}")
                return False
            
            # Mettre à jour le RTC si présent
            rtc_updated = False
            if os.path.exists('/dev/rtc') or os.path.exists('/dev/rtc0') or os.path.exists('/dev/rtc1'):
                logger.info("Mise à jour du module RTC...")
                try:
                    # Essayer rtc1 d'abord (DS3231)
                    if os.path.exists('/dev/rtc1'):
                        subprocess.run(
                            ['hwclock', '--systohc', '--rtc=/dev/rtc1'], 
                            check=True,
                            capture_output=True
                        )
                        rtc_updated = True
                        logger.info("RTC1 (DS3231) mis à jour")
                    else:
                        # Sinon utiliser le RTC par défaut
                        subprocess.run(
                            ['hwclock', '--systohc'], 
                            check=True,
                            capture_output=True
                        )
                        rtc_updated = True
                        logger.info("RTC mis à jour")
                except subprocess.CalledProcessError as e:
                    logger.warning(f"Impossible de mettre à jour le RTC: {e}")
            
            logger.info(f"Heure système synchronisée avec succès")
            if rtc_updated:
                logger.info("Module RTC synchronisé")
            
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Erreur commande système: {e}")
            return False
        except Exception as e:
            logger.error(f"Erreur synchronisation: {e}")
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
            logger.debug(f"Résultat de sync publié: {status} - {message}")
            
        except Exception as e:
            logger.error(f"Erreur publication résultat: {e}")
    
    def publish_periodic_time(self):
        """Publier l'heure périodiquement"""
        try:
            current_time = time.time()
            
            # Information sur la source de temps
            time_source = "rtc"  # Par défaut on utilise le RTC
            if os.path.exists('/dev/rtc1'):
                time_source = "rtc_ds3231"
            elif os.path.exists('/dev/rtc0'):
                time_source = "rtc_system"
            
            time_data = {
                'timestamp': current_time,
                'iso_time': datetime.fromtimestamp(current_time).isoformat(),
                'uptime_seconds': self.get_uptime_seconds(),
                'source': time_source,
                'timezone': time.tzname[0]
            }
            
            self.client.publish(self.topics['time_publish'], json.dumps(time_data))
            
        except Exception as e:
            logger.error(f"Erreur publication périodique: {e}")
    
    def get_uptime_seconds(self):
        """Récupérer l'uptime système"""
        try:
            with open('/proc/uptime', 'r') as f:
                return int(float(f.read().split()[0]))
        except:
            return 0
    
    def run(self):
        """Boucle principale"""
        logger.info("=== Démarrage collecteur TimSync simplifié ===")
        logger.info("Mode: Sans NTP, RTC comme source primaire")
        
        if not self.connect_mqtt():
            logger.error("Impossible de se connecter à MQTT")
            return
        
        self.client.loop_start()
        self.running = True
        
        try:
            publish_interval = self.config['time']['publish_interval']
            logger.info(f"Publication de l'heure toutes les {publish_interval}s")
            
            # Publier une première fois immédiatement
            self.publish_periodic_time()
            
            while self.running:
                time.sleep(publish_interval)
                self.publish_periodic_time()
                
        except KeyboardInterrupt:
            logger.info("Arrêt demandé par l'utilisateur")
        except Exception as e:
            logger.error(f"Erreur dans la boucle principale: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Nettoyage"""
        logger.info("Arrêt du collecteur...")
        self.running = False
        if self.client:
            self.client.loop_stop()
            self.client.disconnect()
        logger.info("Collecteur TimSync arrêté proprement")

if __name__ == "__main__":
    config_file = "/opt/maxlink/config/widgets/timesync_widget.json"
    if len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    collector = TimeSyncCollector(config_file)
    collector.run()