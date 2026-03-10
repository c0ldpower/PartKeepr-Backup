#!/bin/bash

# ========================
# COLOURS
# ========================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

status() {
    case "$1" in
        ok)   echo "${GREEN}✔ $2${NC}" ;;
        warn) echo "${YELLOW}⚠ $2${NC}" ;;
        fail) echo "${RED}✖ $2${NC}" ;;
        info) echo "${BLUE}ℹ $2${NC}" ;;
    esac
}

# ========================
# SPINNER
# ========================
spinner() {
    pid=$1
    spin='-\|/'
    i=0
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r${BLUE}[%c] Working...${NC}" "${spin:$i:1}"
        sleep 0.2
    done
    printf "\r"
}

run_with_spinner() {
    "$@" &
    spinner $!
    wait $!
    return $?
}

# ========================
# LOAD CONFIG
# ========================
if [ -f "./partkeepr-backup-test.properties" ]; then
    . ./partkeepr-backup-test.properties
else
    status fail "Configuration file partkeepr-backup.properties not found!"
    exit 1
fi

# ========================
# FLAGS
# ========================
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

# ========================
# BACKUP PATHS
# ========================
DATE=$(date +%Y%m%d_%H%M%S)
MONTH=$(date +%Y-%m)

BACKUP_MONTH_DIR="$BACKUP_DIR/$MONTH"
mkdir -p "$BACKUP_MONTH_DIR"

# ========================
# DATABASE BACKUP
# ========================
status info "Creating database dump..."

SQL_FILE="$BACKUP_MONTH_DIR/partkeepr-db-$DATE.sql"

if run_with_spinner mysqldump "$DB_NAME" > "$SQL_FILE"
then
    status ok "Database dump created"
else
    status fail "Database dump failed"
    exit 1
fi

status info "Compressing database backup..."

if run_with_spinner zip -q "$SQL_FILE.zip" "$SQL_FILE"
then
    rm "$SQL_FILE"
    status ok "Database compressed"
else
    status fail "Database compression failed"
fi

# ========================
# ONLY DB MODE
# ========================
if [ "$ONLY_DB" = true ]; then
    status info "Only database backup requested"
    status ok "PartKeepr backup finished"
    exit 0
fi

# ========================
# DATA BACKUP
# ========================
if [ "$BACKUP_WEB_DATA" = true ]; then
    status info "Backing up web data folder..."

    if run_with_spinner zip -qr \
        "$BACKUP_MONTH_DIR/partkeepr-data-$DATE.zip" \
        "$WEB_DATA_PATH"
    then
        status ok "Web data backup completed"
    else
        status fail "Web data backup failed"
    fi
else
    status warn "Skipping web data backup"
fi

# ========================
# CONFIG BACKUP
# ========================
status info "Backing up config folder..."

if run_with_spinner zip -qr \
    "$BACKUP_MONTH_DIR/partkeepr-config-$DATE.zip" \
    "$CONFIG_PATH"
then
    status ok "Config backup completed"
else
    status fail "Config backup failed"
fi

# ========================
# FINISHED
# ========================
status ok "PartKeepr backup finished"
status info "Backup location: $BACKUP_MONTH_DIR"
