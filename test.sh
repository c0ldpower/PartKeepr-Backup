#!/bin/bash
# ========================
# PartKeepr Backup - Bash version
# ========================

# ------------------------
# COLOURS
# ------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

# ------------------------
# LOGGING
# ------------------------
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || { echo "Cannot create directory $dir"; exit 1; }
    fi
}

log() {
    printf "%b\n" "$*" | tee -a "$LOG_FILE"
}

status() {
    case "$1" in
        ok)   log "${GREEN}✔ $2${NC}" ;;
        warn) log "${YELLOW}⚠ $2${NC}" ;;
        fail) log "${RED}✖ $2${NC}" ;;
        info) log "${BLUE}ℹ $2${NC}" ;;
    esac
}

# ------------------------
# SPINNER
# ------------------------
spinner() {
    local pid=$1
    local spin='-\|/'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
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

# ------------------------
# LOAD CONFIG
# ------------------------
if [[ ! -f "./partkeepr-backup-test.properties" ]]; then
    echo "Configuration file partkeepr-backup-test.properties not found!"
    exit 1
fi
source ./partkeepr-backup-test.properties

# ------------------------
# FLAGS
# ------------------------
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
        *)
            status warn "Unknown argument: $arg"
            ;;
    esac
done

# ------------------------
# TIMESTAMP & MONTH
# ------------------------
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M)
MONTH=$(date +%Y-%m)

# ------------------------
# ENSURE DIRECTORIES
# ------------------------
ensure_dir "$BACKUP_DIR"
BACKUP_MONTH_DIR="$BACKUP_DIR/$MONTH"
ensure_dir "$BACKUP_MONTH_DIR"
LOG_DIR="$BACKUP_DIR/logs"
ensure_dir "$LOG_DIR"

LOG_FILE="$LOG_DIR/partkeepr-backup-$(date +%Y-%m-%d).log"

# ------------------------
# DATABASE BACKUP
# ------------------------
status info "Creating database dump..."
SQL_FILE="$BACKUP_MONTH_DIR/partkeepr-db-$BACKUP_TIMESTAMP.sql"
run_with_spinner mysqldump "$DB_NAME" > "$SQL_FILE" && status ok "Database dump created" || { status fail "Database dump failed"; exit 1; }

status info "Compressing database backup..."
run_with_spinner zip -q "$SQL_FILE.zip" "$SQL_FILE" && rm "$SQL_FILE" && status ok "Database compressed" || status fail "Database compression failed"

# ------------------------
# ONLY DB MODE
# ------------------------
if [[ "$ONLY_DB" == true ]]; then
    status info "Only database backup requested"
    status ok "PartKeepr backup finished"
    exit 0
fi

# ------------------------
# WEB DATA BACKUP
# ------------------------
if [[ "$BACKUP_WEB_DATA" == true ]]; then
    status info "Backing up web data folder..."
    run_with_spinner zip -qr "$BACKUP_MONTH_DIR/partkeepr-data-$BACKUP_TIMESTAMP.zip" "$WEB_DATA_PATH" && status ok "Web data backup completed" || status fail "Web data backup failed"
else
    status warn "Skipping web data backup"
fi

# ------------------------
# CONFIG BACKUP
# ------------------------
status info "Backing up config folder..."
run_with_spinner zip -qr "$BACKUP_MONTH_DIR/partkeepr-config-$BACKUP_TIMESTAMP.zip" "$CONFIG_PATH" && status ok "Config backup completed" || status fail "Config backup failed"

# ------------------------
# CLEANUP OLD BACKUPS (6 months / 180 days)
# ------------------------
status info "Cleaning backups older than 180 days..."
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +180 -exec rm -rf {} \;
status ok "Old backups cleaned"

# ------------------------
# ROTATE LOGS (6 months / 180 days)
# ------------------------
status info "Cleaning logs older than 180 days..."
find "$LOG_DIR" -type f -name "*.log" -mtime +180 -exec rm -f {} \;
status ok "Old logs cleaned"

# ------------------------
# FINISHED
# ------------------------
status ok "PartKeepr backup finished"
status info "Backup location: $BACKUP_MONTH_DIR"
