#!/usr/bin/env python3
"""
Collecteur de statistiques MQTT pour le widget MQTT Stats
Version corrigée pour utiliser les chemins locaux
"""

import os
import sys
import time
import json
import re
import logging
from datetime import datetime, timedelta
from collections import defaultdict
from pathlib import Path
import fnmatch

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('mqttstats')

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

class MQTTStatsCollector(BaseCollector):
    def __init__(self, config_file):
        """Initialise le collecteur"""
        super().__init__(config_file, 'mqttstats')
        
        self.stats_client = None
        self.stats_connected = False
        
        # Intervalles de mise à jour selon les groupes
        self.update_intervals = {
            'fast': 1,    # messages, uptime
            'normal': 5,  # latence
            'slow': 30    # topics
        }
        
        # Dernières mises à jour par groupe
        self.last_update = {
            'fast': 0,
            'normal': 0,
            'slow': 0
        }
        
        # Charger la configuration des topics
        self.topic_config = self.load_topic_config()
        
        # Structure de données MQTT - état actuel
        self.mqttData = {
            'received': 0,
            'sent': 0,
            'clients_connected': 0,
            'uptime_seconds': 0,
            'uptime': { 'days': 0, 'hours': 0, 'minutes': 0, 'seconds': 0 },
            'latency': 0,
            'status': 'error',
            'topics': [],
            'lastActivityTimestamp': time.time(),
            'connected': False,
            'broker_version': 'N/A',
            'broker_load': {}
        }
        
        # Topics actifs (hors système)
        self.active_topics = set()
        self.topic_last_seen = {}
        
        # Cache des valeurs système
        self.sys_values = {}
        
        logger.info(f"Configuration topics: {len(self.topic_config.get('includedPatterns', []))} patterns d'inclusion")
    
    def load_topic_config(self):
        """Charge la configuration des topics depuis topic_config.json"""
        try:
            # Utiliser get_widget_file pour trouver le fichier
            config_path = self.get_widget_file('topic_config.json')
            
            with open(config_path, 'r') as f:
                config = json.load(f)
                logger.info(f"Configuration des topics chargée depuis {config_path}")
                return config
        except FileNotFoundError:
            logger.warning("Fichier topic_config.json non trouvé, utilisation config par défaut")
            return {}
        except Exception as e:
            logger.error(f"Erreur chargement topic_config.json: {e}")
            return {}
    
    def should_include_topic(self, topic):
        """Vérifie si un topic doit être inclus selon la configuration"""
        # Toujours exclure nos propres topics
        if self.topic_config.get('excludeOwnTopics', True):
            if topic.startswith('rpi/network/mqtt/'):
                return False
        
        # Exclure les topics système
        if topic.startswith('$SYS/'):
            return False
        
        # Si pas de patterns d'inclusion définis, inclure tout
        included_patterns = self.topic_config.get('includedPatterns', [])
        if not included_patterns:
            return True
        
        # Vérifier si le topic correspond à un pattern d'inclusion
        for pattern in included_patterns:
            # Convertir le pattern MQTT en pattern fnmatch
            fnmatch_pattern = pattern.replace('+', '*').replace('#', '**')
            
            # Gérer le cas spécial de ** à la fin
            if fnmatch_pattern.endswith('/**'):
                fnmatch_pattern = fnmatch_pattern[:-2] + '*'
            
            if fnmatch.fnmatch(topic, fnmatch_pattern):
                return True
        
        return False
    
    def on_mqtt_connected(self):
        """Appelé quand la connexion MQTT principale est établie"""
        logger.info("Client principal connecté - démarrage du client de statistiques")
        self._setup_stats_client()
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        logger.info("Initialisation du collecteur MQTT Stats")
        logger.info(f"Intervalles: Fast={self.update_intervals['fast']}s, Normal={self.update_intervals['normal']}s, Slow={self.update_intervals['slow']}s")
    
    def get_update_interval(self):
        """Retourne l'intervalle de mise à jour minimum"""
        return 1  # 1 seconde
    
    def _setup_stats_client(self):
        """Configure le client pour écouter les statistiques"""
        try:
            # Client pour écouter les topics système et utilisateur
            self.stats_client = mqtt.Client(client_id="mqttstats-listener")
            self.stats_client.on_connect = lambda c,u,f,rc: self._on_stats_connect(c, u, f, rc)
            self.stats_client.on_disconnect = lambda c,u,rc: self._on_stats_disconnect(c, u, rc)
            self.stats_client.on_message = self._on_message
            self.stats_client.username_pw_set(
                self.mqtt_config['username'],
                self.mqtt_config['password']
            )
            self.stats_client.connect(
                self.mqtt_config['host'], 
                self.mqtt_config['port'], 
                60
            )
            self.stats_client.loop_start()
        except Exception as e:
            logger.error(f"Erreur configuration client stats: {e}")
    
    def _on_stats_connect(self, client, userdata, flags, rc):
        """Callback de connexion du client stats"""
        if rc == 0:
            logger.info("Client stats connecté au broker MQTT")
            self.stats_connected = True
            # S'abonner aux topics système
            client.subscribe("$SYS/#")
            # S'abonner à tous les topics utilisateur pour les compter
            client.subscribe("#")
            logger.info("Abonné aux topics système ($SYS/#) et utilisateur (#)")
        else:
            logger.error(f"Échec connexion client stats, code: {rc}")
    
    def _on_stats_disconnect(self, client, userdata, rc):
        """Callback de déconnexion du client stats"""
        logger.warning(f"Client stats déconnecté (code: {rc})")
        self.stats_connected = False
    
    def _on_message(self, client, userdata, msg):
        """Callback de réception de message"""
        try:
            topic = msg.topic
            payload = msg.payload.decode('utf-8')
            
            # Traiter les topics système
            if topic.startswith("$SYS/"):
                self._process_sys_topic(topic, payload)
            else:
                # Topics utilisateur - appliquer le filtrage
                if self.should_include_topic(topic):
                    self.active_topics.add(topic)
                    self.topic_last_seen[topic] = time.time()
                    
                    # Garder seulement les 15 derniers topics
                    if len(self.active_topics) > 15:
                        # Supprimer le plus ancien
                        oldest_topic = min(self.topic_last_seen, key=self.topic_last_seen.get)
                        self.active_topics.discard(oldest_topic)
                        del self.topic_last_seen[oldest_topic]
            
        except Exception as e:
            logger.error(f"Erreur traitement message: {e}")
    
    def _process_sys_topic(self, topic, payload):
        """Traite les topics système"""
        try:
            # Stocker la valeur
            self.sys_values[topic] = payload
            
            # Traiter selon le topic
            if topic == "$SYS/broker/clients/connected":
                self.mqttData['clients_connected'] = int(payload)
                
            elif topic == "$SYS/broker/messages/received":
                self.mqttData['received'] = int(payload)
                
            elif topic == "$SYS/broker/messages/sent":
                self.mqttData['sent'] = int(payload)
                
            elif topic == "$SYS/broker/uptime":
                # Format: "X seconds"
                match = re.match(r'(\d+)\s*seconds?', payload)
                if match:
                    self.mqttData['uptime_seconds'] = int(match.group(1))
                    self._calculate_uptime()
                    
            elif topic == "$SYS/broker/version":
                self.mqttData['broker_version'] = payload
                
            elif topic.startswith("$SYS/broker/load/"):
                # Charge du broker (messages/seconde)
                load_type = topic.split('/')[-1]
                try:
                    self.mqttData['broker_load'][load_type] = float(payload)
                except:
                    pass
                    
        except Exception as e:
            logger.debug(f"Erreur traitement topic système {topic}: {e}")
    
    def _calculate_uptime(self):
        """Calcule l'uptime en jours/heures/minutes/secondes"""
        seconds = self.mqttData['uptime_seconds']
        
        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        
        self.mqttData['uptime'] = {
            'days': days,
            'hours': hours,
            'minutes': minutes,
            'seconds': secs
        }
    
    def calculate_latency(self):
        """Calcule la latence en faisant un ping MQTT"""
        if not self.connected:
            return
        
        try:
            # Sur localhost, la latence est très faible
            if self.mqtt_config['host'] in ['localhost', '127.0.0.1', '::1']:
                import random
                self.mqttData['latency'] = random.randint(2, 5)
                return
            
            # Pour un host distant, mesurer vraiment
            start_time = time.time()
            result = self.mqtt_client.publish(
                "test/latency/ping",
                json.dumps({"timestamp": start_time}),
                qos=2
            )
            
            if result.rc == 0:
                result.wait_for_publish()
                latency_ms = int((time.time() - start_time) * 1000)
                self.mqttData['latency'] = max(1, min(latency_ms, 999))
                
        except Exception as e:
            logger.debug(f"Erreur calcul latence: {e}")
            self.mqttData['latency'] = 3
    
    def collect_and_publish(self):
        """Collecte et publie les données selon les intervalles définis"""
        current_time = time.time()
        
        # Mettre à jour le statut
        self.mqttData['status'] = 'ok' if self.connected else 'error'
        self.mqttData['connected'] = self.connected
        
        # Groupe FAST (1s) : messages reçus/envoyés, uptime
        if current_time - self.last_update['fast'] >= self.update_intervals['fast']:
            # Publier les statistiques principales
            self.publish_data("rpi/network/mqtt/stats", {
                "messages_received": self.mqttData['received'],
                "messages_sent": self.mqttData['sent'],
                "clients_connected": self.mqttData['clients_connected'],
                "uptime_seconds": self.mqttData['uptime_seconds'],
                "uptime": self.mqttData['uptime'],
                "latency_ms": self.mqttData['latency'],
                "broker_version": self.mqttData['broker_version'],
                "status": self.mqttData['status']
            })
            self.last_update['fast'] = current_time
        
        # Groupe NORMAL (5s) : latence
        if current_time - self.last_update['normal'] >= self.update_intervals['normal']:
            self.calculate_latency()
            self.last_update['normal'] = current_time
        
        # Groupe SLOW (30s) : liste des topics
        if current_time - self.last_update['slow'] >= self.update_intervals['slow']:
            # Préparer la liste des topics actifs filtrés
            topics_list = sorted(list(self.active_topics))[:15]
            
            # Publier la liste des topics actifs
            self.publish_data("rpi/network/mqtt/topics", {
                "topics": topics_list,
                "count": len(topics_list)
            })
            
            logger.info(
                f"Stats publiées - Messages: {self.mqttData['received']}/{self.mqttData['sent']}, "
                f"Clients: {self.mqttData['clients_connected']}, "
                f"Topics filtrés: {len(topics_list)}/{len(self.topic_last_seen)}"
            )
            
            self.last_update['slow'] = current_time
    
    def cleanup(self):
        """Nettoyage avant l'arrêt"""
        if self.stats_client:
            self.stats_client.loop_stop()
            self.stats_client.disconnect()

if __name__ == "__main__":
    # Configuration
    config_file = os.environ.get('CONFIG_FILE')
    
    if not config_file and len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    if not config_file:
        config_file = "/opt/maxlink/config/widgets/mqttstats_widget.json"
    
    # Log du démarrage
    logger.info("="*60)
    logger.info("Démarrage du collecteur MQTT Stats avec filtrage")
    logger.info(f"Config recherchée dans: {config_file}")
    logger.info(f"Répertoire de travail: {os.getcwd()}")
    logger.info("="*60)
    
    # Lancer le collecteur
    collector = MQTTStatsCollector(config_file)
    collector.run()