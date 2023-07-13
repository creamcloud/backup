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

VERSION="2.0.0"
TITLE="CloudVPS Boss File Overview ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

if [[ -n "$1" ]]; then
    TIME="$1"
    TIMEOPT="--time $1"
    TIME_MESS="Requested Time: $1"
fi

echo "========================================="
lecho "Start of CloudVPS Boss File Overview"
lecho "Hostname: ${HOSTNAME}"
lecho "$TIME_MESS"
echo "-----------------------------------------"
lecho "duplicity list-current-files --file-prefix=\"${HOSTNAME}.\" --name=\"${HOSTNAME}.\" ${ENCRYPTION_OPTIONS} ${CUSTOM_DUPLICITY_OPTIONS} --allow-source-mismatch --num-retries 100 ${TIMEOPT} ${BACKUP_BACKEND}"
duplicity list-current-files \
    --file-prefix="${HOSTNAME}." \
    --name="${HOSTNAME}." \
    ${ENCRYPTION_OPTIONS} \
    ${CUSTOM_DUPLICITY_OPTIONS} \
    --allow-source-mismatch \
    --num-retries 100 \
    ${TIMEOPT} \
    ${BACKUP_BACKEND} 2>&1 | grep -v -e Warning -e pkg_resources -e oslo
lecho "End of CloudVPS Boss File Overview"
echo "========================================="

