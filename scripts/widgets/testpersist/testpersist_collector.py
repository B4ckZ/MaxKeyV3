#!/usr/bin/env python3
"""
MaxLink Test Results Persistence Collector
Persiste les résultats de tests dans des fichiers JSON et confirme la sauvegarde
Version corrigée avec toutes les méthodes abstraites implémentées
"""

import os
import sys
import json
import time
import threading
from pathlib import Path
from datetime import datetime

# Ajouter le répertoire parent au path pour l'import
sys.path.insert(0, '/opt/maxlink/widgets/_core')

try:
    from collector_base import BaseCollector
except ImportError:
    print("Erreur: collector_base.py non trouvé dans /opt/maxlink/widgets/_core")
    sys.exit(1)

class TestPersistCollector(BaseCollector):
    """Collecteur pour la persistance des résultats de tests"""
    
    def __init__(self):
        super().__init__(None, 'testpersist_collector')
        
        # Configuration du stockage
        self.storage_config = self.config.get('storage', {})
        self.base_path = Path(self.storage_config.get('base_path', '/var/www/traçabilité'))
        self.file_mapping = self.storage_config.get('file_mapping', {})
        
        # Position du numéro de machine dans le code-barres
        barcode_config = self.storage_config.get('barcode_machine_position', {})
        self.machine_pos_start = barcode_config.get('start', 6)
        self.machine_pos_length = barcode_config.get('length', 3)
        
        # Verrous pour éviter les conflits d'écriture
        self.file_locks = {}
        
        # Créer le répertoire de base s'il n'existe pas
        try:
            self.base_path.mkdir(parents=True, exist_ok=True)
            self.logger.info(f"Répertoire de stockage: {self.base_path}")
        except Exception as e:
            self.logger.error(f"Erreur création répertoire {self.base_path}: {e}")
        
        # Initialiser les verrous pour chaque fichier
        for machine, filename in self.file_mapping.items():
            filepath = self.base_path / filename
            self.file_locks[str(filepath)] = threading.Lock()
            
        # S'assurer que les fichiers JSON existent
        self._ensure_json_files_exist()
    
    def _ensure_json_files_exist(self):
        """S'assure que tous les fichiers JSON existent"""
        for machine, filename in self.file_mapping.items():
            filepath = self.base_path / filename
            if not filepath.exists():
                try:
                    filepath.touch()
                    self.logger.info(f"Fichier créé: {filepath}")
                except Exception as e:
                    self.logger.error(f"Erreur création fichier {filepath}: {e}")
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        self.logger.info("Initialisation du collecteur de persistance des tests")
        self.logger.info(f"Mapping machines -> fichiers: {self.file_mapping}")
        self.logger.info(f"Position machine dans barcode: caractères {self.machine_pos_start} à {self.machine_pos_start + self.machine_pos_length}")
    
    def on_mqtt_connected(self):
        """Appelé quand la connexion MQTT est établie"""
        # S'abonner aux résultats de tests
        topic = "SOUFFLAGE/+/ESP32/result"
        self.mqtt_client.subscribe(topic)
        self.logger.info(f"Connecté au broker MQTT - Abonné au topic: {topic}")
    
    def get_update_interval(self):
        """Retourne l'intervalle de mise à jour en secondes"""
        # Widget event-driven, pas de polling
        return 1  # Retourne 1 seconde pour la boucle principale
    
    def collect_and_publish(self):
        """Collecte et publie les données - Non utilisé car event-driven"""
        # Ce widget est event-driven, les données sont traitées dans on_message
        pass
    
    def on_connect(self, client, userdata, flags, rc):
        """Callback de connexion MQTT"""
        super().on_connect(client, userdata, flags, rc)
        
        if rc == 0:
            # S'abonner aux résultats de tests
            topic = "SOUFFLAGE/+/ESP32/result"
            client.subscribe(topic)
            self.logger.info(f"Reconnexion - Abonné au topic: {topic}")
    
    def on_message(self, client, userdata, msg):
        """Traitement des messages MQTT"""
        try:
            self.logger.debug(f"Message reçu sur {msg.topic}")
            
            # Parser le topic pour extraire l'ID de la machine
            topic_parts = msg.topic.split('/')
            if len(topic_parts) < 4:
                self.logger.warning(f"Topic invalide: {msg.topic}")
                return
            
            machine_id = topic_parts[1]
            
            # Décoder le message JSON
            try:
                data = json.loads(msg.payload.decode('utf-8'))
                self.logger.debug(f"Données décodées: {data}")
            except json.JSONDecodeError as e:
                self.logger.error(f"Erreur JSON: {e}")
                return
            
            # Vérifier que toutes les données requises sont présentes
            required_fields = ['timestamp', 'team', 'barcode', 'result']
            if not all(field in data for field in required_fields):
                self.logger.error(f"Champs manquants dans les données: {data}")
                return
            
            # Extraire le numéro de machine du code-barres
            barcode = data.get('barcode', '')
            if len(barcode) >= self.machine_pos_start + self.machine_pos_length:
                barcode_machine = barcode[self.machine_pos_start:self.machine_pos_start + self.machine_pos_length]
            else:
                self.logger.error(f"Code-barres trop court: {barcode}")
                return
            
            # Vérifier la cohérence entre le topic et le code-barres
            if machine_id != barcode_machine:
                self.logger.warning(f"Incohérence machine: topic={machine_id}, barcode={barcode_machine}")
                # Utiliser le numéro du code-barres comme référence
                machine_id = barcode_machine
            
            # Déterminer le fichier de destination
            if machine_id not in self.file_mapping:
                self.logger.error(f"Machine inconnue: {machine_id}")
                return
            
            filename = self.file_mapping[machine_id]
            filepath = self.base_path / filename
            
            # Persister les données
            if self.persist_data(filepath, data):
                # Si la persistance réussit, publier la confirmation
                confirm_topic = f"SOUFFLAGE/{machine_id}/ESP32/result/confirmed"
                
                # Publier exactement les mêmes données reçues
                if self.mqtt_publish(confirm_topic, data):
                    self.logger.info(f"Résultat persisté et confirmé: {barcode} -> {filename} (machine {machine_id})")
                else:
                    self.logger.error(f"Échec de la publication de confirmation pour: {barcode}")
            else:
                self.logger.error(f"Échec de la persistance pour: {barcode}")
                
        except Exception as e:
            self.logger.error(f"Erreur dans on_message: {e}", exc_info=True)
    
    def persist_data(self, filepath, data):
        """Persiste les données dans le fichier JSON"""
        try:
            # Acquérir le verrou pour ce fichier
            lock = self.file_locks.get(str(filepath))
            if not lock:
                lock = threading.Lock()
                self.file_locks[str(filepath)] = lock
            
            with lock:
                # S'assurer que le fichier existe
                if not filepath.exists():
                    filepath.touch()
                    self.logger.info(f"Fichier créé: {filepath}")
                
                # Ouvrir le fichier en mode append
                with open(filepath, 'a', encoding='utf-8') as f:
                    # Écrire la ligne JSON
                    json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
                    f.write('\n')
                    f.flush()  # Forcer l'écriture sur disque
                    
                    # Synchronisation avec le système de fichiers
                    try:
                        os.fsync(f.fileno())
                    except OSError:
                        # Certains systèmes de fichiers ne supportent pas fsync
                        pass
            
            self.logger.debug(f"Données persistées dans {filepath}")
            return True
            
        except Exception as e:
            self.logger.error(f"Erreur lors de la persistance dans {filepath}: {e}")
            return False
    
    def mqtt_publish(self, topic, data):
        """Publie un message MQTT avec gestion d'erreur"""
        try:
            # Convertir les données en JSON
            payload = json.dumps(data, ensure_ascii=False, separators=(',', ':'))
            
            # Publier avec QoS 1 pour garantir la livraison
            result = self.mqtt_client.publish(topic, payload, qos=1)
            
            if result.rc == 0:
                self.logger.debug(f"Message publié sur {topic}")
                return True
            else:
                self.logger.error(f"Échec publication sur {topic}, code: {result.rc}")
                return False
                
        except Exception as e:
            self.logger.error(f"Erreur publication MQTT: {e}")
            return False
    
    def cleanup(self):
        """Nettoyage avant l'arrêt"""
        self.logger.info("Nettoyage du collecteur de persistance")
        # Pas de nettoyage spécifique nécessaire

if __name__ == "__main__":
    try:
        # Configurer le niveau de log si nécessaire
        import logging
        if os.environ.get('DEBUG', '').lower() == 'true':
            logging.getLogger().setLevel(logging.DEBUG)
        
        collector = TestPersistCollector()
        collector.run()  # Utiliser la méthode run() de BaseCollector
    except KeyboardInterrupt:
        logging.info("Arrêt demandé par l'utilisateur")
    except Exception as e:
        logging.error(f"Erreur fatale: {e}", exc_info=True)
        sys.exit(1)