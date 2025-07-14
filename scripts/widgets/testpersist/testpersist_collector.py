#!/usr/bin/env python3
"""
MaxLink Test Results Persistence Collector
Persiste les résultats de tests CSV et publie une confirmation
"""

import os
import sys
import threading
from pathlib import Path

# Ajouter le répertoire parent au path pour l'import
sys.path.insert(0, '/opt/maxlink/widgets/_core')

try:
    from collector_base import BaseCollector
except ImportError:
    print("Erreur: collector_base.py non trouvé dans /opt/maxlink/widgets/_core")
    sys.exit(1)

class TestPersistCollector(BaseCollector):
    """Collecteur pour la persistance des résultats de tests CSV"""
    
    def __init__(self):
        super().__init__(None, 'testpersist_collector')
        
        # Configuration du stockage
        self.storage_config = self.config.get('storage', {})
        self.base_path = Path(self.storage_config.get('base_path', '/home/prod/Documents/traçabilité'))
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
        
        # Initialiser les verrous pour chaque fichier unique
        unique_files = set(self.file_mapping.values())
        for filename in unique_files:
            filepath = self.base_path / filename
            self.file_locks[str(filepath)] = threading.Lock()
            
        # S'assurer que les fichiers CSV existent
        self._ensure_csv_files_exist()
    
    def _ensure_csv_files_exist(self):
        """S'assure que tous les fichiers CSV existent"""
        unique_files = set(self.file_mapping.values())
        for filename in unique_files:
            filepath = self.base_path / filename
            if not filepath.exists():
                try:
                    filepath.touch()
                    self.logger.info(f"Fichier CSV créé: {filepath}")
                except Exception as e:
                    self.logger.error(f"Erreur création fichier {filepath}: {e}")
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        self.logger.info("Collecteur de persistance CSV initialisé")
        self.logger.info(f"Machines surveillées: {list(self.file_mapping.keys())}")
        
        # Configuration explicite du callback MQTT
        self.mqtt_client.on_message = self.on_message
    
    def on_mqtt_connected(self):
        """Appelé quand la connexion MQTT est établie"""
        topic = "SOUFFLAGE/ESP32/RTP"
        result = self.mqtt_client.subscribe(topic)
        self.logger.info(f"Abonné au topic: {topic}")
    
    def get_update_interval(self):
        """Retourne l'intervalle de mise à jour en secondes"""
        return 1  # Widget event-driven
    
    def collect_and_publish(self):
        """Collecte et publie les données - Non utilisé car event-driven"""
        pass
    
    def on_connect(self, client, userdata, flags, rc):
        """Callback de connexion MQTT"""
        if rc == 0:
            self.logger.info("Connecté au broker MQTT")
            self.connected = True
            
            topic = "SOUFFLAGE/ESP32/RTP"
            result = client.subscribe(topic)
            
            # Configuration du callback
            client.on_message = self.on_message
            
            try:
                self.on_mqtt_connected()
            except Exception as e:
                self.logger.error(f"Erreur dans on_mqtt_connected: {e}")
        else:
            self.logger.error(f"Échec connexion MQTT, code: {rc}")
            self.connected = False
    
    def on_message(self, client, userdata, msg):
        """Traitement des messages MQTT"""
        try:
            # Décoder le message CSV
            csv_line = msg.payload.decode('utf-8').strip()
            
            # Parser la ligne CSV: date,heure,équipe,codebarre,résultat
            csv_fields = csv_line.split(',')
            
            if len(csv_fields) != 5:
                self.logger.error(f"Format CSV invalide - {len(csv_fields)} champs au lieu de 5")
                return
            
            date, heure, equipe, codebarre, resultat = csv_fields
            
            # Vérifier la longueur du code-barres
            if len(codebarre) < self.machine_pos_start + self.machine_pos_length:
                self.logger.error(f"Code-barres trop court: {codebarre}")
                return
            
            # Extraire le numéro de machine
            machine_id = codebarre[self.machine_pos_start:self.machine_pos_start + self.machine_pos_length]
            
            # Vérifier que la machine est connue
            if machine_id not in self.file_mapping:
                self.logger.warning(f"Machine non configurée: {machine_id}")
                return
            
            # Déterminer le fichier de destination
            filename = self.file_mapping[machine_id]
            filepath = self.base_path / filename
            
            # Persister les données CSV
            if self.persist_csv_data(filepath, csv_line):
                # Publication de la confirmation après persistance réussie
                confirm_topic = "SOUFFLAGE/ESP32/RTP/CONFIRMED"
                if self.mqtt_publish(confirm_topic, csv_line):
                    self.logger.info(f"Résultat persisté et confirmé: {machine_id} -> {filename}")
                else:
                    self.logger.error(f"Échec publication confirmation")
            else:
                self.logger.error(f"Échec persistance pour machine {machine_id}")
                
        except Exception as e:
            self.logger.error(f"Erreur traitement message: {e}", exc_info=True)
    
    def persist_csv_data(self, filepath, csv_line):
        """Persiste la ligne CSV dans le fichier"""
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
                
                # Écriture en mode append
                with open(filepath, 'a', encoding='utf-8', newline='') as f:
                    f.write(csv_line + '\n')
                    f.flush()
                    
                return True
                
        except Exception as e:
            self.logger.error(f"Erreur écriture fichier {filepath}: {e}")
            return False
    
    def mqtt_publish(self, topic, message):
        """Publie un message CSV sur MQTT"""
        if not self.connected:
            return False
        
        try:
            result = self.mqtt_client.publish(topic, message, qos=1)
            return result.rc == 0
        except Exception as e:
            self.logger.error(f"Erreur publication MQTT: {e}")
            return False

def main():
    """Point d'entrée principal"""
    collector = TestPersistCollector()
    collector.run()

if __name__ == "__main__":
    main()