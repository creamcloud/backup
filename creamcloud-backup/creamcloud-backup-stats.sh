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
TITLE="CloudVPS Boss Stats ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

USED="$(swift stat --lh ${HOSTNAME} 2>&1 | awk '/Bytes/ { print $2}' | grep -v -e Warning -e pkg_resources -e oslo)"

echo "========================================="
lecho "Start of CloudVPS Boss Status ${VERSION}"
lecho "Hostname: ${HOSTNAME}"
lecho "External IP: $(curl -s http://ip.cloudvps.nl)"
lecho "Username: ${SWIFT_USERNAME}"
lecho "Storage used: ${USED}"
lecho "Full backups to keep: ${FULL_TO_KEEP}"
lecho "Create full backup if last full backup is older than: ${FULL_IF_OLDER_THAN}"
echo "-----------------------------------------"
lecho "Restic snapshots:"
OLD_IFS="${IFS}"
IFS=$'\n'
RESTIC_OUTPUT=$(restic snapshots \
    --repo ${BACKUP_BACKEND} \
    --password-file=/etc/creamcloud-backup/restic-password.conf \
    --no-cache \
    --verbose=1 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e tar -e attr -e kwargs)
for line in ${RESTIC_OUTPUT}; do
        lecho "${line}"
done
IFS="${OLD_IFS}"
lecho "End of CloudVPS Boss Status"
echo "========================================="

