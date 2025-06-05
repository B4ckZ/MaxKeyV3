#!/usr/bin/env python3
"""
Collecteur passif pour le widget Uptime
Ce widget utilise les données publiées par servermonitoring
"""

import sys
import time
import logging

# Configuration du logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('uptime')

# Ce widget n'a pas de collecteur actif
# Il lit les données du topic rpi/system/uptime publié par servermonitoring

if __name__ == "__main__":
    logger.info("Widget Uptime est passif - pas de collecteur actif")
    logger.info("Les données d'uptime sont publiées par le widget servermonitoring")
    logger.info("Topic MQTT : rpi/system/uptime")
    # Le service va s'arrêter immédiatement
    sys.exit(0)