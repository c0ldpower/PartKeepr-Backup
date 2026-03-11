#!/bin/sh

# PartKeepr-Backup
# 
# A Linux shell script that creates a backup of a PartKeepr database and
# important web files. Backups are conveniently compressed using zip to
# date-time-stamped filenames.
#
# Configure by modifying the partkeepr-backup.property file. See README.md for
# further details and instructions.
#
# Tested with PartKeepr 1.4.0 on Raspbian 9.13 (stretch) -
# https://wiki.partkeepr.org/wiki/PartKeepr_1.4.0_installation_on_a_Raspberry_Pi
#
# - Author: Cabot Technologies - https://cabottechnologies.com
# - Licence: MIT (see the LICENSE file)


ver="0.1.3.003a"
echo "PartKeepr Backup $ver"

# ——————————————
# Command line options
# ——————————————

ONLY_DB=0
NO_DATA=0

while [ $# -gt 0 ]; do
    case "$1" in
        --only-db)
            ONLY_DB=1
            shift
            ;;
        --no-data)
            NO_DATA=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Source the script settings
. ./partkeepr-backup.properties

# ========================
# COLOURS (ANSI escape codes)
# ========================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"  # reset colour

# ========================
# STATUS FUNCTION
# ========================
status() {
    case "$1" in
        ok)    echo "${GREEN}✔ $2${NC}" ;;
        warn)  echo "${YELLOW}⚠ $2${NC}" ;;
        fail)  echo "${RED}✖ $2${NC}" ;;
        info)  echo "${BLUE}ℹ $2${NC}" ;;
    esac
}


############################
# DATABASE BACKUP
############################
status info "Starting database backup..."
backup_database() {
	local start=$(date +%s)
	local backup_file="${date_start}_partkeepr-database-backup.sql"

	status info "Starting database backup..."
	echo "Database backup:" | tee -a "$backup_path/$log_file"	
	echo "Retrieving database SQL..." | tee -a "$backup_path/$log_file"
	res="$( ( mysqldump --opt --host=$database_host --user=$database_user $database_name > "$backup_path/$backup_file" ) 2>&1 )"
	if $res
	then
		status ok "* Success" | tee -a "$backup_path/$log_file"
	else
		status fail "* ERROR: $res" | tee -a "$backup_path/$log_file"
		return 1
	fi

	echo "Compressing database backup to ZIP archive..." | tee -a "$backup_path/$log_file"
	# Zip with maximum compression. Run at low priority.
	res="$( nice -n 10 zip -j -m -q -T -9 "$backup_path/$backup_file.zip" "$backup_path/$backup_file" )"
	if $res
	then
		status ok "* Success" | tee -a "$backup_path/$log_file"
	else
		status fail "* ERROR: $res" | tee -a "$backup_path/$log_file"
		return 1
	fi

	echo "Database backup summary:" | tee -a "$backup_path/$log_file"
	backup_summary "$backup_file.zip" "$start"
}


############################
# WEB DATA BACKUP
############################
backup_app_data() {
	local start=$(date +%s)
	local backup_file="${date_start}_partkeepr-data-backup.zip"

	status info "Backing up web data folder..."
	echo "Web data backup:" | tee -a "$backup_path/$log_file"
	echo "Compressing web data to ZIP archive..." | tee -a "$backup_path/$log_file"
	# Zip with maximum compression. Run at low priority.
	res="$( nice -n 10 zip -q -r -T -9 "$backup_path/$backup_file" "$partkeepr_data_path" )"
	if $res
	then
		status ok "* Success" | tee -a "$backup_path/$log_file"
	else
		status fail "* ERROR: $res" | tee -a "$backup_path/$log_file"
		return 1
	fi

	echo "Web data backup summary:" | tee -a "$backup_path/$log_file"
	backup_summary "$backup_file" "$start"
}


############################
# CONFIG BACKUP
############################
backup_app_config() {
	local start=$(date +%s)
	local backup_file="${date_start}_partkeepr-config-backup.zip"

	status info "Backing up config files..."
	echo "Web config backup:" | tee -a "$backup_path/$log_file"
	echo "Compressing web config to ZIP archive..." | tee -a "$backup_path/$log_file"
	# Zip with maximum compression. Run at low priority.
	res="$( nice -n 10 zip -q -r -T -9 "$backup_path/$backup_file" "$partkeepr_config_path" )"
	if $res
	then
		status ok "* Success" | tee -a "$backup_path/$log_file"
	else
		status fail "* ERROR: $res" | tee -a "$backup_path/$log_file"
		return 1
	fi

	echo "Web config backup summary:" | tee -a "$backup_path/$log_file"
	backup_summary "$backup_file" "$start"
}


# Prints/logs a backup file summary
# $1 is the filename
# $2 is the start time - i.e. '$(date +%s)'
# Requires the global variable $backup_path be set.
backup_summary() {
	echo "* File name:   $1" | tee -a "$backup_path/$log_file"
	local filesize=$(ls -lsah "$backup_path/$1" | awk '{print $6}')
	echo "* File size:   $filesize" | tee -a "$backup_path/$log_file"

	local dur_sec=$(( $(date +%s) - $2 ))
	local hr=$(( dur_sec / 3600 )) # Calculate hours.
	local min=$(( (dur_sec % 3600) / 60 )) # Calculate remaining minutes.
	local sec=$(( dur_sec % 60 )) # Calculate remaining seconds.
	min=$(printf "%02d" $min) # Ensure two digits (zero padding).
	sec=$(printf "%02d" $sec) # Ensure two digits (zero padding).
	echo "* Duration:    $hr:$min:$sec\n" | tee -a "$backup_path/$log_file"
}


# First initialise backup path
date_start=$(date +'%Y%m%d-%H%M%S')
backup_path="$backup_root_path/$(date +%Y%m)"
log_file="${date_start}_partkeepr-backup.log"

echo "PartKeepr Backup $ver\n" > "$backup_path/$log_file"
echo "* Backup path: $backup_path"
echo "* Log: $log_file\n"

# Create backup path...
mkdir -p "$backup_path"

# Run backups

# always run database backup
backup_database

# data folder backup (unless requested not to)
if [ "$NO_DATA" -eq 0 ] && [ "$ONLY_DB" -eq 0 ]; then
    backup_app_data
else
    status warn "Skipping web data backup (option specified)"
fi

# only run config if NOT only-db
if [ "$ONLY_DB" -eq 0 ]; then
    backup_app_config
else
    status warn "Skipping config backup (option specified)"
fi

# ========================
# FINISHED
# ========================
#echo "PartKeepr backup finished\n"
#echo "${GREEN}PartKeepr backup finished${NC}"
status ok "PartKeepr backup finished succesfully"
