#!/bin/sh
# ========================
# PartKeepr Backup Script (POSIX /bin/sh, secure, logging, safe permissions)
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
# LOGGING FUNCTION (POSIX SAFE)
# ------------------------
		  
		   

log() {
    printf "%s\n" "$*" | tee -a "$LOG_FILE"
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
# POSIX SPINNER
# ------------------------
spinner() {
    pid=$1
    spin='-\|/'
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        c=$(printf "%s" "$spin" | cut -c $((i + 1)))
        printf "\r${BLUE}[%s] Working...${NC}" "$c"
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
if [ -f "./partkeepr-backup-test.properties" ]; then
    . ./partkeepr-backup-test.properties
else
    echo "Configuration file partkeepr-backup.properties not found!"
    exit 1
fi

# ------------------------
# ENSURE BACKUP DIR EXISTS AND IS WRITABLE
# ------------------------
mkdir -p "$BACKUP_DIR" || { echo "Cannot create backup directory $BACKUP_DIR"; exit 1; }
chmod 700 "$BACKUP_DIR"

# ------------------------
# LOG FILE SETUP
# ------------------------
LOG_DIR="$BACKUP_DIR/logs"
mkdir -p "$LOG_DIR" || { echo "Cannot create log directory $LOG_DIR"; exit 1; }
chmod 700 "$LOG_DIR"

LOG_FILE="$LOG_DIR/partkeepr-backup-$(date +%Y-%m-%d).log"
touch "$LOG_FILE" || { echo "Cannot create log file $LOG_FILE"; exit 1; }

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
# CONSISTENT TIMESTAMP
# ------------------------
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M)  # no seconds
MONTH=$(date +%Y-%m)
BACKUP_MONTH_DIR="$BACKUP_DIR/$MONTH"
mkdir -p "$BACKUP_MONTH_DIR" || { status fail "Cannot create month backup dir"; exit 1; }

# ------------------------
# DATABASE BACKUP
# ------------------------
status info "Creating database dump..."
SQL_FILE="$BACKUP_MONTH_DIR/partkeepr-db-$BACKUP_TIMESTAMP.sql"

if run_with_spinner sh -c "mysqldump $DB_NAME > '$SQL_FILE'"; then
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

# ------------------------
# ONLY DB MODE
# ------------------------
if [ "$ONLY_DB" = true ]; then
    status info "Only database backup requested"
    status ok "PartKeepr backup finished"
    exit 0
fi

# ------------------------
# WEB DATA BACKUP
# ------------------------
if [ "$BACKUP_WEB_DATA" = true ]; then
    status info "Backing up web data folder..."
    if run_with_spinner zip -qr "$BACKUP_MONTH_DIR/partkeepr-data-$BACKUP_TIMESTAMP.zip" "$WEB_DATA_PATH"; then
        status ok "Web data backup completed"
    else
        status fail "Web data backup failed"
    fi
else
    status warn "Skipping web data backup"
fi

# ------------------------
# CONFIG BACKUP
# ------------------------
status info "Backing up config folder..."
if run_with_spinner zip -qr "$BACKUP_MONTH_DIR/partkeepr-config-$BACKUP_TIMESTAMP.zip" "$CONFIG_PATH"; then
    status ok "Config backup completed"
else
    status fail "Config backup failed"
fi

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
