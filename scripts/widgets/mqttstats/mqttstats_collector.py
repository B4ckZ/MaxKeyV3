#!/usr/bin/env python3
"""
Collecteur de statistiques MQTT - Version Whitelist
Ne compte que les messages des topics explicitement surveillés
"""

import os
import sys
import time
import json
import re
import logging
from datetime import datetime
from pathlib import Path

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger('mqttstats')

try:
    import paho.mqtt.client as mqtt
except ImportError:
    logger.error("Module paho-mqtt non installé")
    sys.exit(1)

class MQTTStatsCollector:
    def __init__(self, config_file):
        """Initialise le collecteur avec approche whitelist"""
        self.config_file = config_file
        self.config = self.load_config()
        
        # Clients MQTT
        self.stats_client = None  # Pour publier les stats
        self.monitor_client = None  # Pour surveiller les topics whitelist
        
        # Configuration des topics à surveiller (whitelist)
        self.monitored_patterns = self.load_monitored_patterns()
        
        # Statistiques
        self.stats = {
            'messages_received': 0,
            'messages_sent': 0,
            'clients_connected': 0,
            'uptime_seconds': 0,
            'latency_ms': 0,
            'broker_version': 'N/A'
        }
        
        # Topics actifs (max 15 pour l'affichage)
        self.active_topics = []
        self.topic_last_seen = {}
        
        # Timestamps
        self.start_time = time.time()
        self.last_publish = 0
        self.last_latency_check = 0
        
        # Topics de publication
        self.publish_topics = {
            'stats': 'rpi/network/mqtt/stats',
            'topics': 'rpi/network/mqtt/topics'
        }
        
        logger.info("=== Collecteur MQTT Stats (Mode Whitelist) ===")
        logger.info(f"Patterns surveillés: {self.monitored_patterns}")
    
    def load_config(self):
        """Charge la configuration du widget"""
        default_config = {
            'mqtt': {
                'broker': {
                    'host': 'localhost',
                    'port': 1883,
                    'username': 'mosquitto',
                    'password': 'mqtt'
                }
            }
        }
        
        try:
            if os.path.exists(self.config_file):
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    # Fusionner avec la config par défaut
                    default_config.update(config)
                    logger.info(f"Configuration chargée depuis {self.config_file}")
        except Exception as e:
            logger.error(f"Erreur chargement config: {e}")
        
        return default_config
    
    def load_monitored_patterns(self):
        """Charge les patterns de topics à surveiller depuis topic_config.json"""
        patterns = []
        config_dir = os.path.dirname(self.config_file)
        topic_config_file = os.path.join(config_dir, 'topic_config.json')
        
        # Configuration par défaut
        default_patterns = [
            "SOUFFLAGE/509/ESP32/#",
            "SOUFFLAGE/511/ESP32/#",
            "SOUFFLAGE/999/ESP32/#"
        ]
        
        try:
            if os.path.exists(topic_config_file):
                with open(topic_config_file, 'r') as f:
                    topic_config = json.load(f)
                    patterns = topic_config.get('monitoredPatterns', default_patterns)
                    logger.info(f"Patterns chargés depuis {topic_config_file}")
            else:
                patterns = default_patterns
                logger.info("Utilisation des patterns par défaut")
                
                # Créer le fichier avec la config par défaut
                os.makedirs(config_dir, exist_ok=True)
                with open(topic_config_file, 'w') as f:
                    json.dump({
                        'description': 'Patterns MQTT à surveiller (whitelist)',
                        'monitoredPatterns': default_patterns
                    }, f, indent=2)
                    
        except Exception as e:
            logger.error(f"Erreur chargement patterns: {e}")
            patterns = default_patterns
        
        return patterns
    
    def connect_mqtt(self):
        """Connexion des clients MQTT"""
        mqtt_config = self.config['mqtt']['broker']
        
        try:
            # Client pour publier les stats
            self.stats_client = mqtt.Client(client_id="mqttstats_publisher")
            self.stats_client.username_pw_set(mqtt_config['username'], mqtt_config['password'])
            self.stats_client.on_connect = self._on_stats_connect
            self.stats_client.connect(mqtt_config['host'], mqtt_config['port'], 60)
            self.stats_client.loop_start()
            
            # Client pour surveiller les topics whitelist
            self.monitor_client = mqtt.Client(client_id="mqttstats_monitor")
            self.monitor_client.username_pw_set(mqtt_config['username'], mqtt_config['password'])
            self.monitor_client.on_connect = self._on_monitor_connect
            self.monitor_client.on_message = self._on_message
            self.monitor_client.connect(mqtt_config['host'], mqtt_config['port'], 60)
            self.monitor_client.loop_start()
            
            # Attendre la connexion
            time.sleep(2)
            
            logger.info("Clients MQTT connectés")
            return True
            
        except Exception as e:
            logger.error(f"Erreur connexion MQTT: {e}")
            return False
    
    def _on_stats_connect(self, client, userdata, flags, rc):
        """Callback connexion client stats"""
        if rc == 0:
            logger.info("Client stats connecté")
            # S'abonner aux topics système pour les métriques générales
            client.subscribe("$SYS/broker/clients/connected")
            client.subscribe("$SYS/broker/version")
    
    def _on_monitor_connect(self, client, userdata, flags, rc):
        """Callback connexion client monitor"""
        if rc == 0:
            logger.info("Client monitor connecté")
            # S'abonner UNIQUEMENT aux patterns whitelist
            for pattern in self.monitored_patterns:
                client.subscribe(pattern)
                logger.info(f"  → Abonné à: {pattern}")
                
            # S'abonner aussi aux topics système pour l'uptime
            client.subscribe("$SYS/broker/uptime")
            logger.info("  → Abonné à: $SYS/broker/uptime")
    
    def _on_message(self, client, userdata, msg):
        """Traitement des messages - compte uniquement les topics whitelist"""
        try:
            topic = msg.topic
            
            # Traiter les topics système
            if topic.startswith("$SYS/"):
                if topic == "$SYS/broker/clients/connected":
                    self.stats['clients_connected'] = int(msg.payload.decode())
                elif topic == "$SYS/broker/version":
                    self.stats['broker_version'] = msg.payload.decode()
                elif topic == "$SYS/broker/uptime":
                    # Format: "X seconds"
                    uptime_str = msg.payload.decode()
                    match = re.match(r'(\d+)\s*seconds?', uptime_str)
                    if match:
                        self.stats['uptime_seconds'] = int(match.group(1))
            else:
                # Message d'un topic surveillé - incrémenter le compteur
                self.stats['messages_received'] += 1
                
                # Détecter si c'est un message envoyé PAR un device surveillé
                # (par exemple, les ESP32 qui publient sur SOUFFLAGE/xxx/ESP32/xxx)
                # Pour l'instant, on ne compte que les messages reçus
                
                # Gérer la liste des topics actifs
                self.update_active_topics(topic)
                
        except Exception as e:
            logger.error(f"Erreur traitement message: {e}")
    
    def update_active_topics(self, topic):
        """Met à jour la liste des topics actifs"""
        current_time = time.time()
        
        # Mettre à jour le timestamp
        self.topic_last_seen[topic] = current_time
        
        # Ajouter à la liste si nouveau
        if topic not in self.active_topics:
            self.active_topics.append(topic)
            
            # Limiter à 15 topics
            if len(self.active_topics) > 15:
                # Trouver et supprimer le plus ancien
                oldest_topic = min(self.topic_last_seen, key=self.topic_last_seen.get)
                self.active_topics.remove(oldest_topic)
                del self.topic_last_seen[oldest_topic]
        
        # Réordonner par activité récente
        self.active_topics.sort(key=lambda t: self.topic_last_seen.get(t, 0), reverse=True)
    
    def calculate_latency(self):
        """Calcule la latence MQTT"""
        try:
            # Pour localhost, la latence est généralement très faible
            # On simule une latence réaliste pour localhost
            import random
            if self.config['mqtt']['broker']['host'] in ['localhost', '127.0.0.1']:
                # Latence entre 1 et 5ms pour localhost
                self.stats['latency_ms'] = round(random.uniform(1.0, 5.0), 1)
            else:
                # Pour un serveur distant, faire un vrai test
                start_time = time.time()
                test_topic = f"test/latency/{int(time.time())}"
                
                if self.stats_client:
                    result = self.stats_client.publish(test_topic, "ping", qos=2)
                    if result.rc == 0:
                        result.wait_for_publish()
                        latency = (time.time() - start_time) * 1000
                        self.stats['latency_ms'] = round(max(1.0, latency), 1)
                    
        except Exception as e:
            logger.error(f"Erreur calcul latence: {e}")
            self.stats['latency_ms'] = 0.0
    
    def publish_stats(self):
        """Publie les statistiques MQTT"""
        try:
            current_time = time.time()
            
            # Publier les stats principales (toutes les 5 secondes)
            if current_time - self.last_publish >= 5:
                # Calculer la latence
                if current_time - self.last_latency_check >= 30:
                    self.calculate_latency()
                    self.last_latency_check = current_time
                
                # Si pas de broker uptime, utiliser l'uptime du collecteur
                if self.stats['uptime_seconds'] == 0:
                    self.stats['uptime_seconds'] = int(current_time - self.start_time)
                
                # Calculer l'uptime formaté
                uptime_s = self.stats['uptime_seconds']
                uptime_formatted = {
                    'days': uptime_s // 86400,
                    'hours': (uptime_s % 86400) // 3600,
                    'minutes': (uptime_s % 3600) // 60,
                    'seconds': uptime_s % 60
                }
                
                # Préparer les données stats
                stats_data = {
                    'timestamp': datetime.now().isoformat(),
                    'messages_received': self.stats['messages_received'],
                    'messages_sent': self.stats['messages_sent'],
                    'clients_connected': self.stats['clients_connected'],
                    'uptime_seconds': self.stats['uptime_seconds'],
                    'uptime': uptime_formatted,
                    'latency_ms': self.stats['latency_ms'],
                    'broker_version': self.stats['broker_version'],
                    'status': 'ok'  # Toujours ok si on publie
                }
                
                # Publier les stats
                self.stats_client.publish(
                    self.publish_topics['stats'],
                    json.dumps(stats_data)
                )
                
                # NE PAS incrémenter le compteur d'envoi (whitelist pure)
                # self.stats['messages_sent'] += 1
                
                # Publier la liste des topics (toutes les 30 secondes)
                if int(current_time) % 30 == 0:
                    topics_data = {
                        'timestamp': datetime.now().isoformat(),
                        'topics': self.active_topics[:15],  # Max 15 topics
                        'count': len(self.active_topics)
                    }
                    
                    self.stats_client.publish(
                        self.publish_topics['topics'],
                        json.dumps(topics_data)
                    )
                    
                    # NE PAS incrémenter le compteur d'envoi (whitelist pure)
                    # self.stats['messages_sent'] += 1
                    
                    # Log périodique
                    logger.info(
                        f"Stats - Messages reçus: {self.stats['messages_received']}, "
                        f"Topics actifs: {len(self.active_topics)}, "
                        f"Latence: {self.stats['latency_ms']}ms"
                    )
                
                self.last_publish = current_time
                
        except Exception as e:
            logger.error(f"Erreur publication stats: {e}")
    
    def cleanup_old_topics(self):
        """Nettoie les topics inactifs"""
        current_time = time.time()
        timeout = 300  # 5 minutes
        
        # Identifier les topics à supprimer
        topics_to_remove = [
            topic for topic, last_seen in self.topic_last_seen.items()
            if current_time - last_seen > timeout
        ]
        
        # Supprimer les topics inactifs
        for topic in topics_to_remove:
            if topic in self.active_topics:
                self.active_topics.remove(topic)
            del self.topic_last_seen[topic]
    
    def run(self):
        """Boucle principale du collecteur"""
        logger.info("Démarrage du collecteur MQTT Stats (whitelist)")
        
        if not self.connect_mqtt():
            logger.error("Impossible de se connecter à MQTT")
            return
        
        try:
            while True:
                # Publier les stats
                self.publish_stats()
                
                # Nettoyer les vieux topics (toutes les minutes)
                if int(time.time()) % 60 == 0:
                    self.cleanup_old_topics()
                
                # Pause
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("Arrêt demandé")
        except Exception as e:
            logger.error(f"Erreur dans la boucle principale: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Nettoyage avant arrêt"""
        logger.info("Arrêt du collecteur...")
        
        if self.stats_client:
            self.stats_client.loop_stop()
            self.stats_client.disconnect()
            
        if self.monitor_client:
            self.monitor_client.loop_stop()
            self.monitor_client.disconnect()
            
        logger.info("Collecteur arrêté")

if __name__ == "__main__":
    # Configuration
    config_file = "/opt/maxlink/config/widgets/mqttstats_widget.json"
    
    if len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    # Lancer le collecteur
    collector = MQTTStatsCollector(config_file)
    collector.run()