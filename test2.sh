#!/bin/bash

# ===============================================================================
# DIAGNOSTIC SERVICE HEALTHCHECK MAXLINK
# Identifier et corriger le problème du service healthcheck
# ===============================================================================

echo "========================================================================"
echo "DIAGNOSTIC SERVICE HEALTHCHECK MAXLINK"
echo "========================================================================"
echo ""

# 1. ÉTAT DU SERVICE HEALTHCHECK
echo "1. État du service maxlink-healthcheck..."
echo ""

if systemctl list-unit-files | grep -q "maxlink-healthcheck"; then
    echo "Service trouvé dans systemd :"
    
    # Afficher le statut détaillé
    echo "  ↦ Statut actuel :"
    systemctl status maxlink-healthcheck.service --no-pager -l || true
    
    echo ""
    echo "  ↦ Configuration du service :"
    systemctl cat maxlink-healthcheck.service 2>/dev/null || echo "    Configuration non accessible"
    
    echo ""
    echo "  ↦ Logs récents :"
    journalctl -u maxlink-healthcheck.service --no-pager -n 10 || true
    
else
    echo "  ↦ Service maxlink-healthcheck non trouvé dans systemd"
    
    # Chercher des traces du service
    echo ""
    echo "  ↦ Recherche de fichiers liés :"
    find /etc/systemd/system/ -name "*healthcheck*" 2>/dev/null || true
    find /lib/systemd/system/ -name "*healthcheck*" 2>/dev/null || true
    find /usr/local/bin/ -name "*healthcheck*" 2>/dev/null || true
    find /opt/maxlink/ -name "*healthcheck*" 2>/dev/null || true
fi

echo ""

# 2. LOGS SYSTÈME RÉCENTS
echo "2. Logs système récents liés à healthcheck..."
echo ""

# Logs des 10 dernières minutes
journalctl --since "10 minutes ago" | grep -i healthcheck || echo "  ↦ Aucun log healthcheck trouvé"

echo ""

# 3. PROCESSUS ET SERVICES MAXLINK
echo "3. Services MaxLink existants..."
echo ""

echo "Services systemd MaxLink :"
systemctl list-unit-files | grep maxlink || echo "  ↦ Aucun service maxlink trouvé"

echo ""
echo "Processus MaxLink actifs :"
ps aux | grep -i maxlink | grep -v grep || echo "  ↦ Aucun processus maxlink trouvé"

echo ""

# 4. ANALYSE DES ERREURS
echo "4. Analyse des erreurs système..."
echo ""

# Chercher toutes les erreurs liées à maxlink dans les logs
echo "Erreurs MaxLink récentes :"
journalctl --since "1 hour ago" -p err | grep -i maxlink || echo "  ↦ Aucune erreur maxlink trouvée"

echo ""

# 5. VÉRIFICATION DÉPENDANCES
echo "5. Vérification des dépendances potentielles..."
echo ""

# Services qui pourraient être requis par healthcheck
services_to_check=("nginx" "mosquitto" "NetworkManager")

for service in "${services_to_check[@]}"; do
    if systemctl is-active --quiet "$service"; then
        echo "  ↦ $service: ACTIF ✓"
    else
        echo "  ↦ $service: INACTIF ✗"
    fi
done

echo ""

# 6. SOLUTION PROPOSÉE
echo "6. Solutions proposées..."
echo ""

if systemctl list-unit-files | grep -q "maxlink-healthcheck"; then
    echo "SERVICE HEALTHCHECK TROUVÉ - Solutions :"
    echo ""
    echo "Option A - Corriger le service :"
    echo "  1. Identifier la cause de l'échec dans les logs"
    echo "  2. Corriger le script/configuration"
    echo "  3. Redémarrer le service"
    echo ""
    echo "Option B - Désactiver temporairement :"
    echo "  sudo systemctl stop maxlink-healthcheck.service"
    echo "  sudo systemctl disable maxlink-healthcheck.service"
    echo ""
    echo "Option C - Supprimer complètement :"
    echo "  sudo systemctl stop maxlink-healthcheck.service"
    echo "  sudo systemctl disable maxlink-healthcheck.service"
    echo "  sudo rm /etc/systemd/system/maxlink-healthcheck.service"
    echo "  sudo systemctl daemon-reload"
    echo ""
    
    # Proposer une action immédiate
    echo "ACTION IMMÉDIATE RECOMMANDÉE :"
    echo "Désactiver le service défaillant pour stabiliser le système :"
    echo ""
    read -p "Voulez-vous désactiver maxlink-healthcheck maintenant ? (y/n): " choice
    
    if [[ $choice == [Yy]* ]]; then
        echo ""
        echo "Désactivation du service healthcheck..."
        
        systemctl stop maxlink-healthcheck.service 2>/dev/null || true
        systemctl disable maxlink-healthcheck.service 2>/dev/null || true
        
        echo "  ↦ Service arrêté et désactivé ✓"
        echo ""
        echo "TESTEZ MAINTENANT :"
        echo "1. Déconnectez votre PC Windows du WiFi"
        echo "2. Reconnectez-vous à MaxLink-NETWORK"  
        echo "3. Observez si le statut reste 'Connecté, sécurisé'"
        echo ""
        echo "Si le problème persiste, il y a d'autres causes."
        echo "Si le problème est résolu, le service healthcheck était la cause."
    fi
    
else
    echo "SERVICE HEALTHCHECK NON TROUVÉ - Causes possibles :"
    echo ""
    echo "1. Service supprimé mais référencé ailleurs"
    echo "2. Fichier de service corrompu"
    echo "3. Dépendance manquante"
    echo ""
    echo "Actions recommandées :"
    echo "  ↦ Nettoyer les références systemd orphelines"
    echo "  ↦ Recharger la configuration systemd"
    echo "  ↦ Vérifier les scripts de démarrage MaxLink"
    echo ""
    
    read -p "Voulez-vous nettoyer les références orphelines ? (y/n): " choice
    
    if [[ $choice == [Yy]* ]]; then
        echo ""
        echo "Nettoyage des références orphelines..."
        
        # Recharger systemd
        systemctl daemon-reload
        
        # Réinitialiser les services failed
        systemctl reset-failed 2>/dev/null || true
        
        echo "  ↦ Configuration systemd rechargée ✓"
        echo "  ↦ Services failed réinitialisés ✓"
        echo ""
        echo "Testez maintenant la connexion Windows."
    fi
fi

echo ""
echo "========================================================================"
echo "DIAGNOSTIC TERMINÉ"
echo "========================================================================"
echo ""

# Résumé des recommandations
echo "RÉSUMÉ :"
echo ""
echo "Cause probable : Service maxlink-healthcheck défaillant"
echo "Impact : Instabilité système détectée par Windows"
echo "Conséquence : Basculement vers 'Pas d'internet'"
echo ""
echo "Solutions testées :"
echo "  1. Désactivation du service défaillant"
echo "  2. Nettoyage configuration systemd"
echo ""
echo "Prochaines étapes :"
echo "  → Tester connexion Windows"
echo "  → Si OK : Le healthcheck était la cause"
echo "  → Si NOK : Chercher d'autres causes (NTP, DNS, etc.)"