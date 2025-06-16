#!/bin/bash

# ===============================================================================
# MAXLINK - MODULE DE LOGGING (VERSION NETTOYÉE)
# Sans références SSH
# ===============================================================================

# ===============================================================================
# VARIABLES GLOBALES
# ===============================================================================

# Définir les variables si pas déjà définies (au cas où ce module est chargé avant variables.sh)
LOG_BASE="${LOG_BASE:-/var/log/maxlink}"
LOG_SYSTEM="${LOG_SYSTEM:-$LOG_BASE/system}"
LOG_INSTALL="${LOG_INSTALL:-$LOG_BASE/install}"
LOG_WIDGETS="${LOG_WIDGETS:-$LOG_BASE/widgets}"
LOG_PYTHON="${LOG_PYTHON:-$LOG_BASE/python}"

# Configuration par défaut
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-${LOG_TO_CONSOLE_DEFAULT:-true}}"
LOG_TO_FILE="${LOG_TO_FILE:-${LOG_TO_FILE_DEFAULT:-true}}"

# Variables de session
SCRIPT_NAME="${SCRIPT_NAME:-unknown}"
SCRIPT_LOG="${SCRIPT_LOG:-}"
LOG_CATEGORY="${LOG_CATEGORY:-system}"

# ===============================================================================
# CRÉATION DES RÉPERTOIRES DE LOGS
# ===============================================================================

# Créer les répertoires s'ils n'existent pas
create_log_directories() {
    local dirs=(
        "$LOG_BASE"
        "$LOG_SYSTEM"
        "$LOG_INSTALL"
        "$LOG_WIDGETS"
        "$LOG_PYTHON"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            chmod 755 "$dir"
        fi
    done
}

# Appeler automatiquement la création des répertoires
create_log_directories

# ===============================================================================
# FONCTIONS DE FORMATAGE
# ===============================================================================

# Obtenir le timestamp formaté
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Formater un message de log
format_log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(get_timestamp)
    
    # Format : [TIMESTAMP] [LEVEL] [SCRIPT] MESSAGE
    echo "[$timestamp] [$level] [$SCRIPT_NAME] $message"
}

# ===============================================================================
# FONCTIONS DE LOGGING PRINCIPALES
# ===============================================================================

# Fonction générique de logging
log() {
    local level="$1"
    local message="$2"
    local formatted_message=$(format_log_message "$level" "$message")
    
    # Afficher sur la console si activé
    if [ "$LOG_TO_CONSOLE" = true ]; then
        case "$level" in
            ERROR|CRITICAL)
                echo -e "\033[31m$formatted_message\033[0m" >&2
                ;;
            WARN|WARNING)
                echo -e "\033[33m$formatted_message\033[0m"
                ;;
            SUCCESS)
                echo -e "\033[32m$formatted_message\033[0m"
                ;;
            INFO)
                echo -e "\033[36m$formatted_message\033[0m"
                ;;
            DEBUG)
                echo -e "\033[90m$formatted_message\033[0m"
                ;;
            *)
                echo "$formatted_message"
                ;;
        esac
    fi
    
    # Écrire dans le fichier si activé et si le fichier est défini
    if [ "$LOG_TO_FILE" = true ] && [ -n "$SCRIPT_LOG" ]; then
        echo "$formatted_message" >> "$SCRIPT_LOG"
    fi
    
    # Toujours écrire les erreurs critiques dans syslog
    if [ "$level" = "CRITICAL" ] || [ "$level" = "ERROR" ]; then
        logger -t "maxlink[$SCRIPT_NAME]" -p user.err "$message"
    fi
}

# ===============================================================================
# ALIAS DE LOGGING PAR NIVEAU
# ===============================================================================

log_debug() {
    log "DEBUG" "$1"
}

log_info() {
    log "INFO" "$1"
}

log_warn() {
    log "WARN" "$1"
}

log_warning() {
    log_warn "$1"
}

log_error() {
    log "ERROR" "$1"
}

log_critical() {
    log "CRITICAL" "$1"
}

log_success() {
    log "SUCCESS" "$1"
}

# ===============================================================================
# FONCTIONS UTILITAIRES
# ===============================================================================

# Logger une séparation
log_separator() {
    local char="${1:--}"
    local width="${2:-80}"
    local separator=$(printf "%${width}s" | tr ' ' "$char")
    log "INFO" "$separator"
}

# Logger un header
log_header() {
    local title="$1"
    log_separator "="
    log "INFO" "$title"
    log_separator "="
}

# Logger une commande et son résultat
log_command() {
    local cmd="$1"
    log "CMD" "Exécution: $cmd"
    
    # Exécuter la commande et capturer la sortie
    local output
    local exit_code
    
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    
    # Logger la sortie ligne par ligne
    if [ -n "$output" ]; then
        echo "$output" | while IFS= read -r line; do
            log "OUT" "$line"
        done
    fi
    
    log "CMD" "Code de sortie: $exit_code"
    return $exit_code
}

# ===============================================================================
# INITIALISATION
# ===============================================================================

# Initialiser le logging pour un script
init_logging() {
    local script_description="$1"
    local category="${2:-system}"  # install, widgets, system, python
    
    # Déterminer le nom du script
    SCRIPT_NAME=$(basename "${BASH_SOURCE[1]:-$0}" .sh)
    LOG_CATEGORY="$category"
    
    # Déterminer le fichier de log selon la catégorie
    case "$category" in
        install)
            SCRIPT_LOG="$LOG_INSTALL/${SCRIPT_NAME}_$(date +%Y%m%d_%H%M%S).log"
            ;;
        widgets)
            SCRIPT_LOG="$LOG_WIDGETS/${SCRIPT_NAME}.log"
            ;;
        python)
            SCRIPT_LOG="$LOG_PYTHON/${SCRIPT_NAME}.log"
            ;;
        *)
            SCRIPT_LOG="$LOG_SYSTEM/${SCRIPT_NAME}.log"
            ;;
    esac
    
    # Header dans le log
    {
        echo ""
        echo "================================================================================"
        echo "DÉMARRAGE: $SCRIPT_NAME"
        [ -n "$script_description" ] && echo "Description: $script_description"
        echo "Date: $(date)"
        echo "Utilisateur: $(whoami)"
        echo "Répertoire: $(pwd)"
        echo "================================================================================"
    } >> "$SCRIPT_LOG"
    
    # Log initial
    log_info "Initialisation du logging pour $SCRIPT_NAME"
    [ -n "$script_description" ] && log_info "$script_description"
}

# ===============================================================================
# GESTION DES ERREURS
# ===============================================================================

# Définir un trap pour les erreurs
setup_error_trap() {
    trap 'log_error "Erreur détectée ligne $LINENO (code: $?)"' ERR
}

# Logger une sortie propre
log_exit() {
    local exit_code="${1:-0}"
    local message="${2:-Script terminé}"
    
    if [ $exit_code -eq 0 ]; then
        log_success "$message"
    else
        log_error "$message (code: $exit_code)"
    fi
    
    {
        echo "================================================================================"
        echo "FIN: $SCRIPT_NAME"
        echo "Date: $(date)"
        echo "Code de sortie: $exit_code"
        echo "================================================================================"
        echo ""
    } >> "$SCRIPT_LOG"
}

# ===============================================================================
# EXPORT DES FONCTIONS
# ===============================================================================

# Exporter toutes les fonctions pour les sous-shells
export -f log
export -f log_debug log_info log_warn log_warning log_error log_critical log_success
export -f log_separator log_header log_command
export -f get_timestamp format_log_message
export -f init_logging setup_error_trap log_exit