#!/usr/bin/env python3
"""
Collecteur de métriques système pour le widget Server Monitoring
Version avec support USB MAXLINKSAVE
"""

import os
import sys
import time
import json
import logging
from datetime import datetime
from pathlib import Path
import subprocess

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('servermonitoring')

# Import des modules requis
try:
    import psutil
except ImportError:
    logger.error("Module psutil non installé")
    sys.exit(1)

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

class SystemMetricsCollector(BaseCollector):
    def __init__(self, config_file):
        """Initialise le collecteur avec la configuration du widget"""
        super().__init__(config_file, 'servermonitoring')
        
        # Intervalles de mise à jour
        self.intervals = {
            'fast': 1,    # CPU usage, Fréquences, RAM/SWAP
            'normal': 5,  # Températures
            'slow': 30    # Disk et USB
        }
        
        self.last_update = {
            'fast': 0,
            'normal': 0,
            'slow': 0
        }
        
        # Cache pour le point de montage USB
        self.usb_mount_point = None
        self.last_usb_check = 0
    
    def on_mqtt_connected(self):
        """Appelé quand la connexion MQTT est établie"""
        logger.info("Connecté au broker MQTT - début de la collecte des métriques système")
    
    def initialize(self):
        """Initialise les variables spécifiques au widget"""
        logger.info("Initialisation du collecteur de métriques système")
        logger.info(f"Intervalles: Fast={self.intervals['fast']}s, Normal={self.intervals['normal']}s, Slow={self.intervals['slow']}s")
        
        # IMPORTANT: Premier appel pour initialiser les compteurs internes de psutil
        # Cela permet d'avoir des valeurs correctes dès le deuxième appel
        psutil.cpu_percent(interval=None, percpu=True)
        logger.info("Compteurs CPU initialisés")
    
    def get_update_interval(self):
        """Retourne l'intervalle de mise à jour minimum"""
        return 0.1  # Pour vérifier rapidement les différents intervalles
    
    def collect_and_publish(self):
        """Collecte et publie les données selon les intervalles définis"""
        current_time = time.time()
        
        # Groupe FAST (CPU, Fréquences, RAM/SWAP, Uptime)
        if current_time - self.last_update['fast'] >= self.intervals['fast']:
            self.collect_cpu_metrics()
            self.collect_frequency_metrics()
            self.collect_memory_metrics()
            self.collect_uptime_metrics()
            self.last_update['fast'] = current_time
        
        # Groupe NORMAL (Températures)
        if current_time - self.last_update['normal'] >= self.intervals['normal']:
            self.collect_temperature_metrics()
            self.last_update['normal'] = current_time
        
        # Groupe SLOW (Disque et USB)
        if current_time - self.last_update['slow'] >= self.intervals['slow']:
            self.collect_disk_metrics()
            self.collect_usb_metrics()
            self.last_update['slow'] = current_time
    
    def find_usb_mount_point(self):
        """Trouve le point de montage de la clé USB MAXLINKSAVE"""
        try:
            # Utiliser lsblk pour obtenir les informations sur les périphériques
            result = subprocess.run(['lsblk', '-J', '-o', 'NAME,LABEL,MOUNTPOINT,TYPE'], 
                                  capture_output=True, text=True, check=True)
            
            lsblk_data = json.loads(result.stdout)
            
            # Parcourir les périphériques
            for device in lsblk_data.get('blockdevices', []):
                # Vérifier le périphérique principal et ses partitions
                devices_to_check = [device]
                if 'children' in device:
                    devices_to_check.extend(device['children'])
                
                for dev in devices_to_check:
                    # Vérifier si c'est une partition avec le label MAXLINKSAVE
                    if (dev.get('type') == 'part' and 
                        dev.get('label') == 'MAXLINKSAVE' and 
                        dev.get('mountpoint')):
                        logger.info(f"Clé USB MAXLINKSAVE trouvée : {dev['mountpoint']}")
                        return dev['mountpoint']
            
            logger.debug("Clé USB MAXLINKSAVE non trouvée")
            return None
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Erreur lors de l'exécution de lsblk : {e}")
            return None
        except json.JSONDecodeError as e:
            logger.error(f"Erreur lors du parsing JSON de lsblk : {e}")
            return None
        except Exception as e:
            logger.error(f"Erreur lors de la recherche de la clé USB : {e}")
            return None
    
    def collect_usb_metrics(self):
        """Collecte les métriques de la clé USB MAXLINKSAVE"""
        try:
            current_time = time.time()
            
            # Rechercher le point de montage toutes les 60 secondes
            # ou si on n'a pas encore de point de montage
            if (self.usb_mount_point is None or 
                current_time - self.last_usb_check >= 60):
                self.usb_mount_point = self.find_usb_mount_point()
                self.last_usb_check = current_time
            
            if self.usb_mount_point:
                # Vérifier que le point de montage existe toujours
                if os.path.exists(self.usb_mount_point):
                    try:
                        disk_usage = psutil.disk_usage(self.usb_mount_point)
                        self.publish_metric(
                            "rpi/system/memory/usb", 
                            round(disk_usage.percent, 1), 
                            "%"
                        )
                        logger.debug(f"USB usage: {disk_usage.percent:.1f}%")
                    except PermissionError:
                        logger.warning(f"Pas de permission pour accéder à {self.usb_mount_point}")
                        self.publish_metric("rpi/system/memory/usb", -1, "N/A")
                        self.usb_mount_point = None
                else:
                    # Le point de montage n'existe plus
                    logger.info("Le point de montage USB n'existe plus")
                    self.usb_mount_point = None
                    self.publish_metric("rpi/system/memory/usb", -1, "N/A")
            else:
                # Pas de clé USB trouvée
                self.publish_metric("rpi/system/memory/usb", -1, "N/A")
                
        except Exception as e:
            logger.error(f"Erreur collecte USB: {e}")
            self.stats['errors'] += 1
            self.publish_metric("rpi/system/memory/usb", -1, "N/A")
    
    def collect_cpu_metrics(self):
        """Collecte les métriques CPU sans blocage - comme htop"""
        try:
            # Utiliser psutil sans interval (non-bloquant)
            # Cela calcule le pourcentage depuis le dernier appel
            cpu_percents = psutil.cpu_percent(interval=None, percpu=True)
            
            # Publier les métriques pour chaque core
            for i, percent in enumerate(cpu_percents, 1):
                self.publish_metric(
                    f"rpi/system/cpu/core{i}", 
                    round(percent, 1), 
                    "%"
                )
                
            # Log occasionnel pour debug
            if self.stats['messages_sent'] % 60 == 0:  # Toutes les 60 mesures
                logger.debug(f"CPU usage: {[round(p, 1) for p in cpu_percents]}")
                
        except Exception as e:
            logger.error(f"Erreur collecte CPU: {e}")
            self.stats['errors'] += 1
    
    def collect_temperature_metrics(self):
        """Collecte les températures"""
        try:
            # Température CPU (Raspberry Pi)
            temp_file = "/sys/class/thermal/thermal_zone0/temp"
            if os.path.exists(temp_file):
                with open(temp_file, 'r') as f:
                    temp_c = float(f.read().strip()) / 1000.0
                    
                self.publish_metric(
                    "rpi/system/temperature/cpu", 
                    round(temp_c, 1), 
                    "°C"
                )
                
                # GPU = CPU sur Raspberry Pi
                self.publish_metric(
                    "rpi/system/temperature/gpu", 
                    round(temp_c, 1), 
                    "°C"
                )
        except Exception as e:
            logger.error(f"Erreur collecte température: {e}")
            self.stats['errors'] += 1
    
    def collect_frequency_metrics(self):
        """Collecte les fréquences"""
        try:
            # Fréquence CPU
            cpu_freq = psutil.cpu_freq()
            if cpu_freq:
                freq_ghz = round(cpu_freq.current / 1000, 2)
                self.publish_metric(
                    "rpi/system/frequency/cpu", 
                    freq_ghz, 
                    "GHz"
                )
            
            # Fréquence GPU (spécifique Raspberry Pi)
            gpu_freq_file = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
            if os.path.exists(gpu_freq_file):
                with open(gpu_freq_file, 'r') as f:
                    freq_khz = float(f.read().strip())
                    freq_mhz = round(freq_khz / 1000, 0)
                    self.publish_metric(
                        "rpi/system/frequency/gpu", 
                        freq_mhz, 
                        "MHz"
                    )
        except Exception as e:
            logger.error(f"Erreur collecte fréquences: {e}")
            self.stats['errors'] += 1
    
    def collect_memory_metrics(self):
        """Collecte les métriques mémoire - RAM et SWAP uniquement"""
        try:
            # RAM
            ram = psutil.virtual_memory()
            self.publish_metric(
                "rpi/system/memory/ram", 
                round(ram.percent, 1), 
                "%"
            )
            
            # SWAP
            swap = psutil.swap_memory()
            self.publish_metric(
                "rpi/system/memory/swap", 
                round(swap.percent, 1), 
                "%"
            )
            
        except Exception as e:
            logger.error(f"Erreur collecte mémoire: {e}")
            self.stats['errors'] += 1
    
    def collect_disk_metrics(self):
        """Collecte les métriques disque"""
        try:
            disk = psutil.disk_usage('/')
            self.publish_metric(
                "rpi/system/memory/disk", 
                round(disk.percent, 1), 
                "%"
            )
        except Exception as e:
            logger.error(f"Erreur collecte disque: {e}")
            self.stats['errors'] += 1
    
    def collect_uptime_metrics(self):
        """Collecte l'uptime"""
        try:
            with open('/proc/uptime', 'r') as f:
                uptime_seconds = int(float(f.readline().split()[0]))
                self.publish_metric(
                    "rpi/system/uptime", 
                    uptime_seconds, 
                    "seconds"
                )
        except Exception as e:
            logger.error(f"Erreur collecte uptime: {e}")
            self.stats['errors'] += 1

if __name__ == "__main__":
    # Configuration depuis l'environnement ou paramètres
    config_file = os.environ.get('CONFIG_FILE')
    
    if not config_file and len(sys.argv) > 1:
        config_file = sys.argv[1]
    
    # Si pas de config spécifiée, utiliser le chemin local par défaut
    if not config_file:
        config_file = "/opt/maxlink/config/widgets/servermonitoring_widget.json"
    
    # Log du démarrage
    logger.info("="*60)
    logger.info("Démarrage du collecteur Server Monitoring")
    logger.info(f"Config recherchée dans: {config_file}")
    logger.info(f"Répertoire de travail: {os.getcwd()}")
    logger.info("="*60)
    
    # Lancer le collecteur
    collector = SystemMetricsCollector(config_file)
    collector.run()