#!/usr/bin/env python3
"""
Collecteur pour le widget Reboot Button
Écoute les commandes de redémarrage via MQTT et exécute le reboot système
"""

import os
import sys
import time
import json
import logging
import subprocess
from datetime import datetime

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger('rebootbutton')

try:
    import paho.mqtt.client as mqtt
except ImportError:
    logger.error("Module paho-mqtt non installé")
    sys.exit(1)

class RebootButtonCollector:
    def __init__(self, config_file=None):
        """Initialise le collecteur"""
        self.config = self.load_config(config_file)
        self.client = None
        self.running = False
        
        # Topics MQTT
        self.topics = {
            'command': 'maxlink/system/reboot',
            'status': 'maxlink/system/reboot/status'
        }
        
        logger.info("=== Collecteur Reboot Button initialisé ===")
    
    def load_config(self, config_file):
        """Charge la configuration"""
        default_config = {
            'mqtt': {
                'host': 'localhost',
                'port': 1883,
                'username': 'mosquitto',
                'password': 'mqtt'
            }
        }
        
        if config_file and os.path.exists(config_file):
            try:
                with open(config_file, 'r') as f:
                    file_config = json.load(f)
                    if 'mqtt' in file_config:
                        default_config['mqtt'].update(file_config['mqtt']['broker'])
                logger.info(f"Configuration chargée depuis {config_file}")
            except Exception as e:
                logger.error(f"Erreur lecture config: {e}")
        
        return default_config
    
    def connect_mqtt(self):
        """Connexion au broker MQTT"""
        try:
            self.client = mqtt.Client(client_id="rebootbutton_collector")
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
            # S'abonner au topic de commande
            client.subscribe(self.topics['command'])
            logger.info(f"Abonné au topic: {self.topics['command']}")
            
            # Publier le statut initial
            self.publish_status('ready')
        else:
            logger.error(f"Échec connexion MQTT: {rc}")
    
    def on_message(self, client, userdata, msg):
        """Traitement des messages MQTT"""
        try:
            topic = msg.topic
            payload = json.loads(msg.payload.decode())
            
            if topic == self.topics['command']:
                self.handle_reboot_command(payload)
                
        except Exception as e:
            logger.error(f"Erreur traitement message: {e}")
    
    def normalize_text(self, text):
        """Normalise le texte en retirant les accents et en mettant en majuscules"""
        import unicodedata
        # Normaliser en NFD (décompose les caractères accentués)
        nfd = unicodedata.normalize('NFD', text)
        # Garder seulement les caractères non-accentués
        without_accents = ''.join(char for char in nfd if unicodedata.category(char) != 'Mn')
        return without_accents.upper()
    
    def handle_reboot_command(self, payload):
        """Traite une commande de redémarrage"""
        try:
            # Vérifier les paramètres de la commande
            command = payload.get('command')
            confirmed = payload.get('confirmed', False)
            user_confirmation = payload.get('user_confirmation', '')
            
            if command != 'reboot':
                logger.warning(f"Commande non reconnue: {command}")
                return
            
            # Accepter "REDEMARRER" avec ou sans accent, en majuscules ou minuscules
            normalized_input = self.normalize_text(user_confirmation)
            expected = self.normalize_text('REDÉMARRER')  # On compare avec la version sans accent
            
            if not confirmed or normalized_input != expected:
                logger.warning("Commande de redémarrage non confirmée correctement")
                logger.warning(f"Confirmation reçue: '{user_confirmation}' (normalisée: '{normalized_input}')")
                logger.warning(f"Attendu: 'REDÉMARRER' ou variantes (normalisé: '{expected}')")
                self.publish_status('error', 'Confirmation invalide')
                return
            
            logger.info("=== COMMANDE DE REDÉMARRAGE CONFIRMÉE ===")
            logger.info(f"Timestamp: {payload.get('timestamp', 'N/A')}")
            logger.info(f"Confirmation: {user_confirmation}")
            
            # Publier le statut avant le redémarrage
            self.publish_status('rebooting', 'Redémarrage en cours...')
            
            # Attendre un peu pour que le message soit envoyé
            time.sleep(2)
            
            # Exécuter le redémarrage système
            self.execute_system_reboot()
            
        except Exception as e:
            logger.error(f"Erreur traitement commande reboot: {e}")
            self.publish_status('error', str(e))
    
    def execute_system_reboot(self):
        """Exécute le redémarrage système"""
        try:
            logger.info("Exécution du redémarrage système...")
            
            # Différentes méthodes de redémarrage selon les privilèges
            reboot_commands = [
                ['sudo', 'reboot'],           # Avec sudo
                ['systemctl', 'reboot'],       # Via systemctl
                ['sudo', 'systemctl', 'reboot'], # Sudo + systemctl
                ['reboot'],                    # Direct (si root)
                ['sudo', '/sbin/reboot']       # Chemin complet
            ]
            
            # Essayer chaque commande jusqu'à ce qu'une fonctionne
            for cmd in reboot_commands:
                try:
                    logger.info(f"Tentative de redémarrage avec: {' '.join(cmd)}")
                    result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                    
                    if result.returncode == 0:
                        logger.info("Commande de redémarrage exécutée avec succès")
                        # Le système va redémarrer, on ne verra pas la suite
                        break
                    else:
                        logger.warning(f"Échec avec {cmd[0]}: {result.stderr}")
                        
                except subprocess.TimeoutExpired:
                    logger.info("Timeout - Le redémarrage est probablement en cours")
                    break
                except Exception as e:
                    logger.debug(f"Erreur avec {cmd[0]}: {e}")
                    continue
            
            # Si on arrive ici, aucune commande n'a fonctionné
            logger.error("Impossible d'exécuter le redémarrage système")
            logger.error("Vérifiez que l'utilisateur a les privilèges nécessaires")
            logger.error("Ajoutez cette ligne dans sudoers: 'mosquitto ALL=(ALL) NOPASSWD: /sbin/reboot'")
            
            self.publish_status('error', 'Privilèges insuffisants pour redémarrer')
            
        except Exception as e:
            logger.error(f"Erreur critique lors du redémarrage: {e}")
            self.publish_status('error', f'Erreur: {str(e)}')
    
    def publish_status(self, status, message=''):
        """Publie le statut du service"""
        try:
            status_data = {
                'status': status,
                'message': message,
                'timestamp': datetime.now().isoformat()
            }
            
            if self.client:
                self.client.publish(self.topics['status'], json.dumps(status_data))
                logger.debug(f"Statut publié: {status} - {message}")
                
        except Exception as e:
            logger.error(f"Erreur publication statut: {e}")
    
    def run(self):
        """Boucle principale du collecteur"""
        logger.info("Démarrage du collecteur Reboot Button")
        
        if not self.connect_mqtt():
            logger.error("Impossible de se connecter à MQTT")
            return
        
        self.client.loop_start()
        self.running = True
        
        try:
            # Le collecteur reste en attente des commandes
            while self.running:
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("Arrêt demandé par l'utilisateur")
        except Exception as e:
            logger.error(f"Erreur dans la boucle principale: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Nettoyage avant arrêt"""
        logger.info("Arrêt du collecteur...")
        self.running = False
        
        if self.client:
            self.publish_status('stopped')
            self.client.loop_stop()
            self.client.disconnect()
            
        logger.info("Collecteur arrêté")

if __name__ == "__main__":
    # Configuration
    config_file = "/opt/maxlink/config/widgets/rebootbutton_widget.json"
    
    if len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    # Lancer le collecteur
    collector = RebootButtonCollector(config_file)
    collector.run()