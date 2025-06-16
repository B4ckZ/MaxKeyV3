#!/bin/bash

# Script de diagnostic et configuration RTC pour Raspberry Pi 5
# Utilisant le connecteur BAT dédié

echo "================================================"
echo "   Diagnostic RTC Raspberry Pi 5 (BAT)"
echo "================================================"
echo ""

# Vérifier si le script est exécuté avec sudo
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Ce script doit être exécuté avec sudo"
    echo "   Utilisation: sudo ./rtc_pi5_diagnostic.sh"
    exit 1
fi

# Vérifier qu'on est bien sur un Pi 5
check_pi5() {
    echo "🔍 Vérification du modèle..."
    
    if grep -q "Raspberry Pi 5" /proc/cpuinfo; then
        echo "✅ Raspberry Pi 5 détecté"
        cat /proc/cpuinfo | grep "Model" | cut -d ':' -f 2 | sed 's/^ *//'
        return 0
    else
        echo "❌ Ce script est spécifique au Raspberry Pi 5"
        echo "   Modèle détecté:"
        cat /proc/cpuinfo | grep "Model" | cut -d ':' -f 2 | sed 's/^ *//'
        return 1
    fi
}

# Vérifier la présence du RTC intégré
check_rtc_device() {
    echo ""
    echo "🔍 Recherche du module RTC..."
    
    # Le Pi 5 utilise le RTC RP1 (rp1-rtc)
    if [ -e /dev/rtc0 ] || [ -e /dev/rtc ]; then
        echo "✅ Périphérique RTC détecté"
        
        # Identifier le type de RTC
        if dmesg | grep -q "rp1-rtc"; then
            echo "   Type: RP1 RTC (intégré au Pi 5)"
        fi
        
        # Vérifier quel périphérique
        if [ -e /dev/rtc0 ]; then
            echo "   Périphérique: /dev/rtc0"
            RTC_DEVICE="/dev/rtc0"
        else
            echo "   Périphérique: /dev/rtc"
            RTC_DEVICE="/dev/rtc"
        fi
        
        return 0
    else
        echo "❌ Aucun périphérique RTC trouvé"
        echo ""
        echo "Le RTC du Pi 5 devrait être détecté automatiquement."
        echo "Vérifiez que:"
        echo "1. Le module/pile est correctement inséré dans le connecteur BAT"
        echo "2. Le firmware est à jour (sudo rpi-update)"
        return 1
    fi
}

# Vérifier l'état de la batterie
check_battery_status() {
    echo ""
    echo "🔋 Vérification de la batterie RTC..."
    
    # Tenter de lire l'heure du RTC
    if hwclock -r 2>/dev/null; then
        echo "✅ Le RTC répond correctement"
        echo "   Heure actuelle du RTC: $(hwclock -r 2>/dev/null)"
        
        # Vérifier si l'heure est plausible
        RTC_YEAR=$(hwclock -r 2>/dev/null | grep -oP '\d{4}')
        if [ "$RTC_YEAR" -lt "2020" ]; then
            echo "⚠️  L'heure du RTC semble incorrecte (année: $RTC_YEAR)"
            echo "   La batterie pourrait être faible ou absente"
        fi
    else
        echo "❌ Impossible de lire l'heure du RTC"
        echo "   Vérifiez la batterie/module dans le connecteur BAT"
    fi
}

# Installer les outils nécessaires
install_tools() {
    echo ""
    echo "🔧 Vérification des outils..."
    
    if ! command -v hwclock &> /dev/null; then
        echo "📦 Installation de util-linux..."
        apt-get update
        apt-get install -y util-linux
    else
        echo "✅ hwclock déjà installé"
    fi
    
    if ! command -v timedatectl &> /dev/null; then
        echo "📦 Installation de systemd-timesyncd..."
        apt-get install -y systemd-timesyncd
    else
        echo "✅ timedatectl déjà installé"
    fi
}

# Synchroniser l'heure système vers le RTC
sync_system_to_rtc() {
    echo ""
    echo "🔄 Synchronisation de l'heure système vers le RTC..."
    
    # S'assurer que l'heure système est correcte
    echo "Heure système actuelle: $(date)"
    
    # Écrire l'heure système dans le RTC
    if hwclock -w; then
        echo "✅ Heure système écrite dans le RTC"
        
        # Vérifier
        echo "Vérification - Heure RTC: $(hwclock -r)"
    else
        echo "❌ Échec de l'écriture dans le RTC"
        return 1
    fi
}

# Configurer le service RTC au démarrage
setup_rtc_service() {
    echo ""
    echo "⚙️  Configuration du service RTC..."
    
    # Créer un service systemd pour synchroniser au démarrage
    cat > /etc/systemd/system/rtc-sync.service << 'EOF'
[Unit]
Description=Synchronisation RTC au démarrage pour Pi 5
After=sysinit.target
Before=time-sync.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/sbin/hwclock -s
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
EOF

    # Activer le service
    systemctl daemon-reload
    systemctl enable rtc-sync.service
    
    echo "✅ Service RTC configuré et activé"
    
    # Configurer aussi fake-hwclock pour la redondance
    if [ -f /etc/default/fake-hwclock ]; then
        echo ""
        echo "📝 Configuration de fake-hwclock..."
        # S'assurer que fake-hwclock n'interfère pas
        systemctl disable fake-hwclock 2>/dev/null || true
        echo "✅ fake-hwclock désactivé (RTC hardware présent)"
    fi
}

# Tester la persistance
test_rtc_persistence() {
    echo ""
    echo "🧪 Test de persistance RTC..."
    echo ""
    echo "Test: Le RTC doit conserver l'heure même sans alimentation"
    echo ""
    
    # Sauvegarder l'heure actuelle
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo "1. Heure actuelle: $CURRENT_TIME"
    
    # Écrire dans le RTC
    hwclock -w
    echo "2. Heure écrite dans le RTC"
    
    echo ""
    echo "Pour tester complètement:"
    echo "- Éteignez le Pi 5 (sudo shutdown -h now)"
    echo "- Débranchez l'alimentation pendant 30 secondes"
    echo "- Rebranchez et démarrez"
    echo "- Vérifiez avec: hwclock -r"
    echo ""
    echo "Si l'heure est conservée = RTC fonctionne ✅"
    echo "Si l'heure est perdue = Vérifiez la batterie 🔋"
}

# Afficher les infos de diagnostic
show_diagnostics() {
    echo ""
    echo "================================================"
    echo "   Informations de diagnostic"
    echo "================================================"
    echo ""
    
    echo "📊 État du système:"
    timedatectl status | grep -E "Local time|RTC time|System clock synchronized"
    
    echo ""
    echo "📊 Messages kernel RTC:"
    dmesg | grep -i rtc | tail -5
    
    echo ""
    echo "📊 Périphériques RTC:"
    ls -la /dev/rtc* 2>/dev/null || echo "Aucun périphérique RTC"
}

# Fonction principale
main() {
    # Vérifier qu'on est sur un Pi 5
    if ! check_pi5; then
        exit 1
    fi
    
    # Installer les outils nécessaires
    install_tools
    
    # Vérifier la présence du RTC
    if ! check_rtc_device; then
        echo ""
        echo "💡 Conseils:"
        echo "1. Vérifiez que le module RTC est bien inséré dans le connecteur BAT"
        echo "2. Mettez à jour le firmware: sudo rpi-update"
        echo "3. Redémarrez après la mise à jour"
        exit 1
    fi
    
    # Vérifier l'état de la batterie
    check_battery_status
    
    # Synchroniser l'heure
    sync_system_to_rtc
    
    echo ""
    echo "🤔 Voulez-vous configurer le démarrage automatique? (o/n)"
    read -r response
    
    if [[ "$response" =~ ^[Oo]$ ]]; then
        setup_rtc_service
    fi
    
    # Afficher les diagnostics
    show_diagnostics
    
    # Test de persistance
    test_rtc_persistence
    
    echo ""
    echo "================================================"
    echo "   Configuration terminée!"
    echo "================================================"
    echo ""
    echo "📝 Commandes utiles:"
    echo "   hwclock -r          : Lire l'heure du RTC"
    echo "   hwclock -w          : Écrire l'heure système vers le RTC"
    echo "   hwclock -s          : Définir l'heure système depuis le RTC"
    echo "   hwclock --systohc   : Système vers RTC (identique à -w)"
    echo "   hwclock --hctosys   : RTC vers système (identique à -s)"
    echo "   timedatectl         : État complet de l'horloge"
    echo ""
    echo "💡 Notes importantes:"
    echo "- Le Pi 5 utilise le connecteur BAT pour l'alimentation RTC"
    echo "- Formats supportés: pile bouton CR2032 ou module rechargeable"
    echo "- Le RTC conservera l'heure même sans alimentation principale"
    echo ""
}

# Exécuter le script principal
main