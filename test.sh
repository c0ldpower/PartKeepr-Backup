#!/bin/sh
# ========================
# PartKeepr Backup Script (POSIX sh, secure)
# ========================

# ------------------------
# COLOURS (ANSI codes)
# ------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"  # reset colour

# ------------------------
# STATUS FUNCTION
# ------------------------
status() {
    case "$1" in
        ok)    echo "${GREEN}✔ $2${NC}" ;;
        warn)  echo "${YELLOW}⚠ $2${NC}" ;;
        fail)  echo "${RED}✖ $2${NC}" ;;
        info)  echo "${BLUE}ℹ $2${NC}" ;;
    esac
}

# ------------------------
# LOAD CONFIG
# ------------------------
# Make sure partkeepr-backup.properties exists and uses shell-compatible syntax
if [ -f "./partkeepr-backup.properties" ]; then
    . ./partkeepr-backup.properties
else
    status fail "Configuration file partkeepr-backup.properties not found!"
    exit 1
fi

# ------------------------
# DEFAULT FLAGS
# ------------------------
BACKUP_WEB_DATA=true
ONLY_DB=false

# ------------------------
# PARSE COMMAND-LINE ARGUMENTS
# ------------------------
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
# PREPARE BACKUP DIRECTORY
# ------------------------
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# ------------------------
# DATABASE BACKUP (secure via ~/.my.cnf)
# ------------------------
status info "Starting database backup..."
if mysqldump "$DB_NAME" > "$BACKUP_DIR/partkeepr-db-$DATE.sql"; then
    status ok "Database backup completed"
else
    status fail "Database backup failed!"
    exit 1
fi

# ------------------------
# EXIT IF ONLY_DB FLAG
# ------------------------
if [ "$ONLY_DB" = true ]; then
    status info "Only database backup requested, skipping other backups."
    status ok "PartKeepr backup finished"
    exit 0
fi

# ------------------------
# WEB DATA BACKUP (optional)
# ------------------------
if [ "$BACKUP_WEB_DATA" = true ]; then
    status info "Backing up web data folder..."
    if zip -r "${BACKUP_DIR}/partkeepr-data-$DATE.zip" "$WEB_DATA_PATH"; then
        status ok "Web data backup completed"
    else
        status fail "Web data backup failed!"
    fi
else
    status warn "Skipping web data folder backup"
fi

# ------------------------
# CONFIG BACKUP
# ------------------------
status info "Backing up config files..."
if zip -r "${BACKUP_DIR}/partkeepr-config-$DATE.zip" "$CONFIG_PATH"; then
    status ok "Config backup completed"
else
    status fail "Config backup failed!"
fi

# ------------------------
# FINISHED
# ------------------------
status ok "PartKeepr backup finished"
