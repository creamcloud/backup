#!/bin/bash
#
#        ▄▄███████▄▄
#     ▄███████████████▄
#   ▄███▐███▀▀▄▄▄▄▀▀████▄
#  ████▐██ ███▀▀▀███▄▀███▌   ▄█████▄ ██▄▄███▌ ▄█████▄  ▄██████▄ ██▌▄████▄▄████▄
# ▐███▌██ ██       ██▌████  ▐███   ▀ ▀███▀▀▀ ███▀  ███ ▀▀   ███  ███▀▀████▀▀███▌
# ▐███▌██ ▀█     █ ▐██▐███  ▐██▌     ▐██▌    █████████ ▄███████▌ ███   ███  ▐██▌
# ▐████▄▀█▄ ▀▀  ▄█ ███▐███  ▐██▌     ▐██▌    ███      ▐███   ██▌ ███   ███  ▐██▌
#  █████▌▀▀████▀▀ ███▐███▌   ▀█████▀ ▐██▌    ▀███████▀ █████████ ███   ██▌   ██▌
#   ▀██████▄▄▄▄█████▐███▀
#     ▀███████████████▀
#        ▀▀███████▀▀
#
# ------------------------------------------------------------------------------
# Cream Cloud Backup - Restic wrapper to back up to OpenStack Object Store
#
# Copyright (C):          Cream Commerce B.V., https://www.cream.nl/
# Based on the work of:   Remy van Elst, https://raymii.org/

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/creamcloud-backup"
BIN_LINK="/usr/local/bin/creamcloud-backup"
CRON_FILE="/etc/cron.d/creamcloud-backup"

lecho() {
    logger -t "creamcloud-backup" -- "$1"
    echo "# $1"
}

if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root." 1>&2
    exit 1
fi

read -r -p "Remove Cream Cloud Backup from this server? Your restic repository, ${CONFIG_DIR} (which holds the restic password) and ${PROJECT_DIR} will NOT be removed. [y/N] " choice

if [[ "${choice}" != "y" && "${choice}" != "Y" ]]; then
    echo "Not removing anything."
    exit 0
fi

if [[ -f "${CRON_FILE}" ]]; then
    lecho "Removing ${CRON_FILE}."
    rm -f "${CRON_FILE}"
fi

if [[ -L "${BIN_LINK}" ]]; then
    lecho "Removing ${BIN_LINK}."
    rm -f "${BIN_LINK}"
fi

lecho "Cream Cloud Backup has been removed."
lecho "The application directory (${PROJECT_DIR}), ${CONFIG_DIR} and your restic"
lecho "repository have NOT been removed. Remove them manually if you no longer need them."
