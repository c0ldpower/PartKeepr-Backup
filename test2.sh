#!/bin/bash

#########################################################################
# PartKeepr Backup Script
#
# Improvements:
# - Bash only
# - Single consistent timestamp including seconds
# - Cron-safe absolute config path
# - Required variable check
# - Required command check
# - Monthly backup directories
# - 6-month retention
# - Spinner, coloured output, logging
# - Flags: --no-data, --only-db
#########################################################################


############################
# COLOURS
############################
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"


############################
# SCRIPT PATH / CONFIG
############################
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/partkeepr-backup-test.properties"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file $CONFIG_FILE not found"
    exit 1
fi

source "$CONFIG_FILE"


############################
# CHECK REQUIRED VARIABLES
############################
for var in BACKUP_DIR DB_NAME WEB_DATA_PATH CONFIG_PATH; do
    if [[ -z "${!var}" ]]; then
        echo "Configuration variable $var is missing in $CONFIG_FILE"
        exit 1
    fi
done


############################
# CHECK REQUIRED COMMANDS
############################
for cmd in mysqldump zip find; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Required command not found: $cmd"
        exit 1
    fi
done


############################
# FLAGS
############################
BACKUP_WEB_DATA=true
ONLY_DB=false
for arg in "$@"; do
    case "$arg" in
        --no-data)
            BACKUP_WEB_DATA=false
        ;;
        --only-db)
            ONLY_DB=true
            BACKUP_WEB_DATA=false
        ;;
    esac
done


############################
# TIMESTAMPING
############################
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)  # include seconds
MONTH=$(date +%Y-%m)                     # month folder
# This single timestamp is used for all files created during this run


############################
# SAFE DIRECTORY CREATION
############################
if [[ ! -d "$BACKUP_DIR" ]]; then
    mkdir -p "$BACKUP_DIR" || { echo "Cannot create backup directory $BACKUP_DIR"; exit 1; }
fi

BACKUP_MONTH_DIR="$BACKUP_DIR/$MONTH"
if [[ ! -d "$BACKUP_MONTH_DIR" ]]; then
    mkdir -p "$BACKUP_MONTH_DIR" || { echo "Cannot create month backup dir $BACKUP_MONTH_DIR"; exit 1; }
fi

LOG_DIR="$BACKUP_DIR/logs"
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR" || { echo "Cannot create log directory $LOG_DIR"; exit 1; }
fi

LOG_FILE="$LOG_DIR/partkeepr-backup-$(date +%Y-%m-%d).log"
if [[ ! -f "$LOG_FILE" ]]; then
    touch "$LOG_FILE" || { echo "Cannot create log file $LOG_FILE"; exit 1; }
fi


############################
# LOGGING FUNCTIONS
############################
log() {
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
}

status() {
    case "$1" in
        info)  log "${BLUE}$2${NC}" ;;
        ok)    log "${GREEN}$2${NC}" ;;
        warn)  log "${YELLOW}$2${NC}" ;;
        fail)  log "${RED}$2${NC}" ;;
    esac
}


############################
# SPINNER
############################
spinner() {
    local pid=$1
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 4 ))
        printf "\r[%c] Working..." "${spin:$i:1}"
        sleep 0.2
    done
    printf "\r"
}

run_with_spinner() {
    "$@" &
    spinner $!
    wait $!
}


############################
# DATABASE BACKUP
############################
status info "Starting database backup..."

SQL_FILE="$BACKUP_MONTH_DIR/partkeepr-db-$BACKUP_TIMESTAMP.sql"
if run_with_spinner mysqldump "$DB_NAME" > "$SQL_FILE"; then
    status ok "Database dump created"
else
    status fail "Database dump failed"
    exit 1
fi

status info "Compressing database backup..."
if run_with_spinner zip -q "$SQL_FILE.zip" "$SQL_FILE"; then
    rm "$SQL_FILE"
    status ok "Database compressed"
else
    status fail "Database compression failed"
fi


############################
# ONLY DB MODE
############################
if [[ "$ONLY_DB" == true ]]; then
    status info "Only database backup requested"
    status ok "PartKeepr backup finished"
    exit 0
fi


############################
# WEB DATA BACKUP
############################
if [[ "$BACKUP_WEB_DATA" == true ]]; then
    status info "Backing up web data..."
    DATA_ARCHIVE="$BACKUP_MONTH_DIR/partkeepr-data-$BACKUP_TIMESTAMP.zip"
    if run_with_spinner zip -qr "$DATA_ARCHIVE" "$WEB_DATA_PATH"; then
        status ok "Web data backup completed"
    else
        status fail "Web data backup failed"
    fi
else
    status warn "Skipping web data backup"
fi


############################
# CONFIG BACKUP
############################
status info "Backing up config files..."
CONFIG_ARCHIVE="$BACKUP_MONTH_DIR/partkeepr-config-$BACKUP_TIMESTAMP.zip"
if run_with_spinner zip -qr "$CONFIG_ARCHIVE" "$CONFIG_PATH"; then
    status ok "Config backup completed"
else
    status fail "Config backup failed"
fi


############################
# CLEANUP OLD BACKUPS
############################
status info "Cleaning backups older than 180 days..."
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +180 -exec rm -rf {} \;
status ok "Old backups removed"


############################
# LOG RETENTION
############################
status info "Cleaning logs older than 180 days..."
find "$LOG_DIR" -type f -name "*.log" -mtime +180 -exec rm -f {} \;
status ok "Old logs removed"


############################
# FINISHED
############################
status ok "PartKeepr backup finished"
status info "Backup location: $BACKUP_MONTH_DIR"
