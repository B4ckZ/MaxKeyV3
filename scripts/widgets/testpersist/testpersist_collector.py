#!/usr/bin/env python3
"""
MaxLink Test Results Persistence Collector
Persiste les résultats de tests CSV avec traçabilité hebdomadaire
Version 3.0 - Architecture 1: Extension Simple
"""

import os
import sys
import threading
import datetime
import glob
import shutil
from pathlib import Path

# Ajouter le répertoire parent au path pour l'import
sys.path.insert(0, '/opt/maxlink/widgets/_core')

try:
    from collector_base import BaseCollector
except ImportError:
    print("Erreur: collector_base.py non trouvé dans /opt/maxlink/widgets/_core")
    sys.exit(1)

class TestPersistCollector(BaseCollector):
    """Collecteur pour la persistance des résultats de tests CSV avec traçabilité hebdomadaire"""
    
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
        
        # Configuration de la traçabilité hebdomadaire
        self.weekly_config = self.storage_config.get('weekly_tracking', {})
        self.archives_enabled = self.weekly_config.get('enabled', True)
        self.archives_subdir = self.weekly_config.get('archives_folder', 'Archives')
        
        # Répertoire d'archives
        self.archives_path = self.base_path / self.archives_subdir
        
        # Variables de suivi de semaine
        self.current_year, self.current_week = self._get_current_week_info()
        self.last_known_week = None
        
        # Verrous pour éviter les conflits d'écriture
        self.file_locks = {}
        self.archive_lock = threading.Lock()
        
        # Créer les répertoires nécessaires
        self._ensure_directories_exist()
        
        # Initialiser le système de traçabilité hebdomadaire
        self._initialize_weekly_tracking()
        
        # Initialiser les verrous pour chaque fichier unique
        self._initialize_file_locks()
    
    def _get_current_week_info(self):
        """Retourne l'année et le numéro de semaine courant (ISO 8601)"""
        now = datetime.datetime.now()
        year, week, weekday = now.isocalendar()
        return year, week
    
    def _ensure_directories_exist(self):
        """S'assure que tous les répertoires nécessaires existent"""
        try:
            # Répertoire principal
            self.base_path.mkdir(parents=True, exist_ok=True)
            self.logger.info(f"Répertoire de stockage: {self.base_path}")
            
            # Répertoire d'archives
            if self.archives_enabled:
                self.archives_path.mkdir(parents=True, exist_ok=True)
                self.logger.info(f"Répertoire d'archives: {self.archives_path}")
                
        except Exception as e:
            self.logger.error(f"Erreur création répertoires: {e}")
    
    def _initialize_weekly_tracking(self):
        """Initialise le système de traçabilité hebdomadaire"""
        try:
            self.logger.info(f"Initialisation traçabilité hebdomadaire - Semaine {self.current_week}/{self.current_year}")
            
            # Archiver les fichiers de semaines précédentes s'ils existent
            if self.archives_enabled:
                self._archive_previous_weeks()
            
            # S'assurer que les fichiers de la semaine courante existent
            self._ensure_current_week_files_exist()
            
            # Mémoriser la semaine courante
            self.last_known_week = (self.current_year, self.current_week)
            
        except Exception as e:
            self.logger.error(f"Erreur initialisation traçabilité hebdomadaire: {e}")
    
    def _get_current_week_filename(self, machine_id):
        """Génère le nom de fichier pour la semaine courante"""
        if machine_id in ['998', '999']:
            machine_suffix = 'RPDT'
        else:
            machine_suffix = machine_id
        
        return f"S{self.current_week:02d}_{self.current_year}_{machine_suffix}.csv"
    
    def _get_week_filename(self, year, week, machine_id):
        """Génère le nom de fichier pour une semaine donnée"""
        if machine_id in ['998', '999']:
            machine_suffix = 'RPDT'
        else:
            machine_suffix = machine_id
        
        return f"S{week:02d}_{year}_{machine_suffix}.csv"
    
    def _find_previous_week_files(self):
        """Trouve tous les fichiers de semaines précédentes dans le répertoire principal"""
        previous_files = []
        
        # Pattern pour les fichiers de semaine: S##_####_*.csv
        pattern = str(self.base_path / "S*_*_*.csv")
        
        for filepath in glob.glob(pattern):
            file_path = Path(filepath)
            filename = file_path.name
            
            try:
                # Parser le nom de fichier: S##_####_machine.csv
                parts = filename.replace('.csv', '').split('_')
                if len(parts) >= 3 and parts[0].startswith('S'):
                    week_str = parts[0][1:]  # Retirer le 'S'
                    year_str = parts[1]
                    
                    file_week = int(week_str)
                    file_year = int(year_str)
                    
                    # Vérifier si c'est une semaine précédente
                    if (file_year, file_week) != (self.current_year, self.current_week):
                        previous_files.append((file_path, file_year, file_week))
                        
            except (ValueError, IndexError) as e:
                self.logger.warning(f"Impossible de parser le nom de fichier: {filename} - {e}")
        
        return previous_files
    
    def _archive_previous_weeks(self):
        """Archive automatiquement les fichiers de semaines précédentes"""
        with self.archive_lock:
            previous_files = self._find_previous_week_files()
            
            if not previous_files:
                self.logger.info("Aucun fichier de semaine précédente à archiver")
                return
            
            archived_count = 0
            
            for file_path, file_year, file_week in previous_files:
                try:
                    # Créer le répertoire d'archive pour l'année
                    year_archive_dir = self.archives_path / str(file_year)
                    year_archive_dir.mkdir(parents=True, exist_ok=True)
                    
                    # Destination du fichier archivé
                    archive_dest = year_archive_dir / file_path.name
                    
                    # Déplacer le fichier vers les archives
                    shutil.move(str(file_path), str(archive_dest))
                    
                    self.logger.info(f"Fichier archivé: {file_path.name} → Archives/{file_year}/")
                    archived_count += 1
                    
                except Exception as e:
                    self.logger.error(f"Erreur archivage {file_path.name}: {e}")
            
            if archived_count > 0:
                self.logger.info(f"Archivage terminé: {archived_count} fichier(s) déplacé(s)")
    
    def _ensure_current_week_files_exist(self):
        """S'assure que tous les fichiers de la semaine courante existent"""
        # Obtenir toutes les machines uniques de la configuration
        machines = set(self.file_mapping.keys())
        
        for machine_id in machines:
            filename = self._get_current_week_filename(machine_id)
            filepath = self.base_path / filename
            
            if not filepath.exists():
                try:
                    filepath.touch()
                    self.logger.info(f"Fichier de semaine créé: {filename}")
                except Exception as e:
                    self.logger.error(f"Erreur création fichier {filename}: {e}")
    
    def _initialize_file_locks(self):
        """Initialise les verrous pour chaque fichier de machine"""
        machines = set(self.file_mapping.keys())
        
        for machine_id in machines:
            filename = self._get_current_week_filename(machine_id)
            filepath = self.base_path / filename
            self.file_locks[str(filepath)] = threading.Lock()
    
    def _check_week_change(self):
        """Vérifie si la semaine a changé et effectue l'archivage si nécessaire"""
        current_year, current_week = self._get_current_week_info()
        
        if (current_year, current_week) != (self.current_year, self.current_week):
            self.logger.info(f"Changement de semaine détecté: S{self.current_week}/{self.current_year} → S{current_week}/{current_year}")
            
            # Archiver les fichiers de la semaine précédente
            if self.archives_enabled:
                self._archive_previous_weeks()
            
            # Mettre à jour les variables de semaine courante
            self.current_year = current_year
            self.current_week = current_week
            
            # Créer les nouveaux fichiers de semaine
            self._ensure_current_week_files_exist()
            
            # Réinitialiser les verrous pour les nouveaux fichiers
            self._initialize_file_locks()
            
            self.logger.info(f"Transition vers semaine S{self.current_week}/{self.current_year} terminée")
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        self.logger.info("Collecteur de persistance CSV avec traçabilité hebdomadaire initialisé")
        self.logger.info(f"Machines surveillées: {list(self.file_mapping.keys())}")
        self.logger.info(f"Semaine courante: S{self.current_week:02d}_{self.current_year}")
        self.logger.info(f"Archives activées: {self.archives_enabled}")
        
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
            
            try:
                self.on_mqtt_connected()
            except Exception as e:
                self.logger.error(f"Erreur dans on_mqtt_connected: {e}")
        else:
            self.logger.error(f"Échec connexion MQTT, code: {rc}")
            self.connected = False
    
    def on_message(self, client, userdata, msg):
        """Traitement des messages MQTT avec vérification de changement de semaine"""
        try:
            # Vérifier si la semaine a changé avant de traiter le message
            self._check_week_change()
            
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
            
            # Déterminer le fichier de destination (semaine courante)
            filename = self._get_current_week_filename(machine_id)
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
        """Persiste la ligne CSV dans le fichier de la semaine courante"""
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
    
    def get_archive_info(self):
        """Retourne des informations sur les archives disponibles"""
        if not self.archives_enabled or not self.archives_path.exists():
            return {}
        
        archives_info = {}
        
        try:
            # Parcourir les répertoires d'années
            for year_dir in self.archives_path.iterdir():
                if year_dir.is_dir() and year_dir.name.isdigit():
                    year = year_dir.name
                    archives_info[year] = []
                    
                    # Chercher les fichiers de semaine dans l'année
                    pattern = f"S*_{year}_*.csv"
                    
                    for archive_file in year_dir.glob(pattern):
                        filename = archive_file.name
                        try:
                            # Parser: S##_####_machine.csv
                            parts = filename.replace('.csv', '').split('_')
                            if len(parts) >= 3 and parts[0].startswith('S'):
                                week_str = parts[0][1:]
                                week_num = int(week_str)
                                
                                if week_num not in archives_info[year]:
                                    archives_info[year].append(week_num)
                        
                        except (ValueError, IndexError):
                            continue
                    
                    # Trier les semaines
                    archives_info[year].sort(reverse=True)
        
        except Exception as e:
            self.logger.error(f"Erreur lecture archives: {e}")
        
        return archives_info

def main():
    """Point d'entrée principal"""
    collector = TestPersistCollector()
    collector.run()

if __name__ == "__main__":
    main()