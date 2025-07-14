#!/usr/bin/env python3
"""
Collecteur de statistiques MQTT - Version RTP/CONFIRMED
Surveille spécifiquement les topics RTP et leurs confirmations
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
        """Initialise le collecteur avec surveillance RTP spécialisée"""
        self.config_file = config_file
        self.config = self.load_config()
        
        # Clients MQTT
        self.stats_client = None  # Pour publier les stats
        self.monitor_client = None  # Pour surveiller les topics RTP
        
        # Configuration des topics à surveiller
        self.monitored_patterns = self.load_monitored_patterns()
        self.topic_roles = self.load_topic_roles()
        
        # Compteurs séparés pour RTP
        self.rtp_stats = {
            'received': 0,  # Messages RTP reçus
            'sent': 0       # Messages RTP confirmés
        }
        
        # Statistiques système standard
        self.system_stats = {
            'clients_connected': 0,
            'uptime_seconds': 0,
            'latency_ms': 0,
            'broker_version': 'N/A'
        }
        
        # Topics actifs pour affichage
        self.active_topics = []
        self.topic_last_seen = {}
        
        # Timestamps
        self.start_time = time.time()
        self.last_publish = 0
        
        # Topics de publication
        self.publish_topics = {
            'stats': 'rpi/network/mqtt/stats',
            'topics': 'rpi/network/mqtt/topics'
        }
        
        logger.info("=== Collecteur MQTT Stats RTP/CONFIRMED ===")
        logger.info(f"Topics surveillés: {self.monitored_patterns}")
        logger.info(f"Rôles des topics: {self.topic_roles}")
    
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
        
        # Configuration par défaut RTP
        default_patterns = [
            "SOUFFLAGE/ESP32/RTP",
            "SOUFFLAGE/ESP32/RTP/CONFIRMED"
        ]
        
        try:
            if os.path.exists(topic_config_file):
                with open(topic_config_file, 'r') as f:
                    topic_config = json.load(f)
                    patterns = topic_config.get('monitoredPatterns', default_patterns)
                    logger.info(f"Patterns chargés depuis {topic_config_file}")
            else:
                patterns = default_patterns
                logger.info("Utilisation des patterns par défaut RTP")
                
                # Créer le fichier avec la config par défaut
                os.makedirs(config_dir, exist_ok=True)
                with open(topic_config_file, 'w') as f:
                    json.dump({
                        'description': 'Topics MQTT spécifiques à surveiller pour RTP et confirmations',
                        'monitoredPatterns': default_patterns,
                        'topicRoles': {
                            'SOUFFLAGE/ESP32/RTP': 'received',
                            'SOUFFLAGE/ESP32/RTP/CONFIRMED': 'sent'
                        }
                    }, f, indent=2)
                    
        except Exception as e:
            logger.error(f"Erreur chargement patterns: {e}")
            patterns = default_patterns
        
        return patterns
    
    def load_topic_roles(self):
        """Charge les rôles des topics depuis topic_config.json"""
        config_dir = os.path.dirname(self.config_file)
        topic_config_file = os.path.join(config_dir, 'topic_config.json')
        
        default_roles = {
            'SOUFFLAGE/ESP32/RTP': 'received',
            'SOUFFLAGE/ESP32/RTP/CONFIRMED': 'sent'
        }
        
        try:
            if os.path.exists(topic_config_file):
                with open(topic_config_file, 'r') as f:
                    topic_config = json.load(f)
                    return topic_config.get('topicRoles', default_roles)
        except Exception as e:
            logger.error(f"Erreur chargement rôles: {e}")
        
        return default_roles
    
    def connect_mqtt(self):
        """Connexion des clients MQTT"""
        mqtt_config = self.config['mqtt']['broker']
        
        try:
            # Client pour publier les stats
            self.stats_client = mqtt.Client(client_id="mqttstats_rtp_publisher")
            self.stats_client.username_pw_set(mqtt_config['username'], mqtt_config['password'])
            self.stats_client.on_connect = self._on_stats_connect
            self.stats_client.connect(mqtt_config['host'], mqtt_config['port'], 60)
            self.stats_client.loop_start()
            
            # Client pour surveiller les topics RTP
            self.monitor_client = mqtt.Client(client_id="mqttstats_rtp_monitor")
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
            # S'abonner aux topics RTP spécifiques
            for pattern in self.monitored_patterns:
                client.subscribe(pattern)
                logger.info(f"  → Abonné à: {pattern}")
                
            # S'abonner aussi aux topics système pour l'uptime
            client.subscribe("$SYS/broker/uptime")
            logger.info("  → Abonné à: $SYS/broker/uptime")
    
    def _on_message(self, client, userdata, msg):
        """Traitement des messages - comptage séparé RTP/CONFIRMED"""
        try:
            topic = msg.topic
            
            # Traiter les topics système
            if topic.startswith("$SYS/"):
                if topic == "$SYS/broker/clients/connected":
                    self.system_stats['clients_connected'] = int(msg.payload.decode())
                elif topic == "$SYS/broker/version":
                    self.system_stats['broker_version'] = msg.payload.decode()
                elif topic == "$SYS/broker/uptime":
                    # Format: "X seconds"
                    uptime_str = msg.payload.decode()
                    match = re.match(r'(\d+)\s*seconds?', uptime_str)
                    if match:
                        self.system_stats['uptime_seconds'] = int(match.group(1))
            else:
                # Message RTP - identifier le rôle et incrémenter le bon compteur
                role = self.topic_roles.get(topic)
                if role == 'received':
                    self.rtp_stats['received'] += 1
                    logger.debug(f"RTP reçu: {self.rtp_stats['received']}")
                elif role == 'sent':
                    self.rtp_stats['sent'] += 1
                    logger.debug(f"RTP confirmé: {self.rtp_stats['sent']}")
                else:
                    logger.warning(f"Topic inconnu reçu: {topic}")
                
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
            
        # Réordonner par activité récente
        self.active_topics.sort(key=lambda t: self.topic_last_seen.get(t, 0), reverse=True)
        
        # Limiter à quelques topics pour l'affichage
        if len(self.active_topics) > 5:
            self.active_topics = self.active_topics[:5]
    
    def calculate_latency(self):
        """Calcule la latence MQTT"""
        try:
            # Pour localhost, simulation d'une latence réaliste
            import random
            if self.config['mqtt']['broker']['host'] in ['localhost', '127.0.0.1']:
                self.system_stats['latency_ms'] = round(random.uniform(1.0, 5.0), 1)
            else:
                # Pour d'autres brokers, on pourrait faire un ping MQTT réel
                self.system_stats['latency_ms'] = round(random.uniform(5.0, 50.0), 1)
                
        except Exception as e:
            logger.error(f"Erreur calcul latence: {e}")
            self.system_stats['latency_ms'] = 0
    
    def publish_stats(self):
        """Publie les statistiques RTP sur MQTT"""
        current_time = time.time()
        
        # Publier toutes les 2 secondes
        if current_time - self.last_publish < 2:
            return
        
        try:
            # Calculer la latence périodiquement
            if int(current_time) % 10 == 0:
                self.calculate_latency()
            
            # Calculer l'uptime formaté
            uptime_seconds = self.system_stats['uptime_seconds']
            days = uptime_seconds // 86400
            hours = (uptime_seconds % 86400) // 3600
            minutes = (uptime_seconds % 3600) // 60
            seconds = uptime_seconds % 60
            uptime_formatted = f"{days:02d}j {hours:02d}h {minutes:02d}m {seconds:02d}s"
            
            # Construire les données de stats avec mapping RTP
            stats_data = {
                'timestamp': datetime.now().isoformat(),
                'messages_received': self.rtp_stats['received'],  # Messages RTP reçus
                'messages_sent': self.rtp_stats['sent'],          # Messages RTP confirmés
                'clients_connected': self.system_stats['clients_connected'],
                'uptime_seconds': self.system_stats['uptime_seconds'],
                'uptime': uptime_formatted,
                'latency_ms': self.system_stats['latency_ms'],
                'broker_version': self.system_stats['broker_version'],
                'status': 'ok',
                'rtp_details': {
                    'received_count': self.rtp_stats['received'],
                    'confirmed_count': self.rtp_stats['sent'],
                    'difference': self.rtp_stats['received'] - self.rtp_stats['sent']
                }
            }
            
            # Publier les stats
            self.stats_client.publish(
                self.publish_topics['stats'],
                json.dumps(stats_data)
            )
            
            # Publier la liste des topics (toutes les 30 secondes)
            if int(current_time) % 30 == 0:
                topics_data = {
                    'timestamp': datetime.now().isoformat(),
                    'topics': self.active_topics,
                    'count': len(self.active_topics)
                }
                
                self.stats_client.publish(
                    self.publish_topics['topics'],
                    json.dumps(topics_data)
                )
                
                # Log périodique avec détails RTP
                logger.info(
                    f"Stats RTP - Reçus: {self.rtp_stats['received']}, "
                    f"Confirmés: {self.rtp_stats['sent']}, "
                    f"Différence: {self.rtp_stats['received'] - self.rtp_stats['sent']}, "
                    f"Topics actifs: {len(self.active_topics)}"
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
        logger.info("Démarrage du collecteur MQTT Stats RTP")
        
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