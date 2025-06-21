#!/bin/bash

# Script de diagnostic pour la clé USB MAXLINKSAVE
# Version simplifiée en bash

echo "============================================================"
echo " DIAGNOSTIC USB MAXLINKSAVE"
echo " $(date)"
echo "============================================================"

echo ""
echo "1. TEST LSBLK - Recherche des périphériques"
echo "------------------------------------------------------------"
echo "Recherche du label MAXLINKSAVE..."
echo ""

# Afficher tous les périphériques
lsblk -o NAME,LABEL,SIZE,TYPE,MOUNTPOINT,FSTYPE

echo ""
echo "Recherche spécifique de MAXLINKSAVE:"
if lsblk -o LABEL,MOUNTPOINT | grep -i "MAXLINKSAVE"; then
    echo "✅ Clé USB MAXLINKSAVE trouvée!"
    
    # Obtenir le point de montage
    MOUNT_POINT=$(lsblk -o LABEL,MOUNTPOINT | grep -i "MAXLINKSAVE" | awk '{print $2}')
    
    if [ -n "$MOUNT_POINT" ] && [ "$MOUNT_POINT" != "" ]; then
        echo "✅ Point de montage: $MOUNT_POINT"
        
        # Vérifier l'espace disque
        echo ""
        echo "Espace disque:"
        df -h "$MOUNT_POINT" 2>/dev/null || echo "❌ Impossible d'accéder aux statistiques"
        
        # Vérifier les permissions
        echo ""
        echo "Permissions:"
        ls -la "$MOUNT_POINT" 2>/dev/null | head -5 || echo "❌ Impossible de lister le contenu"
        
        # Test d'accès avec l'utilisateur prod
        echo ""
        echo "Test d'accès avec l'utilisateur prod:"
        sudo -u prod ls "$MOUNT_POINT" 2>/dev/null && echo "✅ L'utilisateur prod peut accéder au répertoire" || echo "❌ L'utilisateur prod ne peut pas accéder au répertoire"
        
    else
        echo "⚠️  La clé est détectée mais PAS MONTÉE"
        echo ""
        echo "Pour la monter manuellement:"
        echo "1. Créer un point de montage: sudo mkdir -p /mnt/maxlinksave"
        echo "2. Monter la clé: sudo mount LABEL=MAXLINKSAVE /mnt/maxlinksave"
    fi
else
    echo "❌ Aucune clé USB avec le label MAXLINKSAVE trouvée"
fi

echo ""
echo "============================================================"
echo "2. TEST BLKID - Vérification des labels"
echo "------------------------------------------------------------"
echo "Liste de tous les périphériques avec leurs labels:"
echo ""
sudo blkid | grep -v loop

echo ""
echo "============================================================"
echo "3. TEST JSON LSBLK - Format utilisé par le collecteur"
echo "------------------------------------------------------------"
echo "Sortie JSON de lsblk:"
echo ""
lsblk -J -o NAME,LABEL,MOUNTPOINT,TYPE | python3 -m json.tool 2>/dev/null || lsblk -J -o NAME,LABEL,MOUNTPOINT,TYPE

echo ""
echo "============================================================"
echo "4. VÉRIFICATION DU SERVICE"
echo "------------------------------------------------------------"
echo "Status du service servermonitoring:"
echo ""
sudo systemctl status maxlink-widget-servermonitoring --no-pager | head -20

echo ""
echo "Derniers logs du service:"
echo ""
sudo journalctl -u maxlink-widget-servermonitoring -n 20 --no-pager

echo ""
echo "============================================================"
echo "5. TEST MQTT - Vérification des messages USB"
echo "------------------------------------------------------------"
echo "Écoute du topic MQTT pendant 5 secondes..."
echo "(Si rien n'apparaît, c'est que le collecteur ne publie pas)"
echo ""
timeout 5 mosquitto_sub -h localhost -u mosquitto -P mqtt -t "rpi/system/memory/usb" -v 2>/dev/null || echo "Pas de message reçu sur le topic USB"

echo ""
echo "============================================================"
echo "RÉSUMÉ ET SOLUTIONS"
echo "============================================================"
echo ""
echo "📌 Pour que la détection fonctionne, il faut:"
echo "1. Une clé USB avec le label exact 'MAXLINKSAVE'"
echo "2. La clé doit être montée quelque part"
echo "3. L'utilisateur 'prod' doit pouvoir y accéder"
echo ""
echo "💡 Pour créer le bon label sur une clé USB:"
echo "   - FAT32: sudo mkfs.vfat -n MAXLINKSAVE /dev/sdX1"
echo "   - NTFS:  sudo ntfslabel /dev/sdX1 MAXLINKSAVE"
echo "   - EXT4:  sudo e2label /dev/sdX1 MAXLINKSAVE"
echo ""
echo "💡 Pour monter automatiquement au démarrage:"
echo "   Ajouter dans /etc/fstab:"
echo "   LABEL=MAXLINKSAVE /mnt/maxlinksave auto defaults,nofail,user,rw 0 0"
echo ""

# Installation de psutil si nécessaire
echo "============================================================"
echo "6. VÉRIFICATION DE PSUTIL"
echo "------------------------------------------------------------"
if ! python3 -c "import psutil" 2>/dev/null; then
    echo "❌ psutil n'est pas installé"
    echo ""
    echo "Pour l'installer:"
    echo "sudo apt update"
    echo "sudo apt install python3-psutil"
    echo "ou"
    echo "sudo pip3 install psutil"
else
    echo "✅ psutil est installé"
fi

echo ""
echo "Fin du diagnostic."