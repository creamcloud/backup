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
TITLE="CloudVPS Boss Upgrade ${VERSION}"

DL_SRV="https://github.com/creamcloud/backup/"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    echo "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

lecho "${TITLE} started on ${HOSTNAME} at $(date)."

pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

if [[ ! -d "/root/.creamcloud-backup" ]]; then
    mkdir -p "/root/.creamcloud-backup"
fi

pushd /root/.creamcloud-backup

if [[ -f "/root/.creamcloud-backup/creamcloud-backup.tar.gz" ]]; then
    lecho "Removing old update file from /root/.creamcloud-backup/creamcloud-backup.tar.gz"
    rm -rf /root/.creamcloud-backup/creamcloud-backup.tar.gz
fi

if [[ -d "/root/.creamcloud-backup/creamcloud-backup" ]]; then
    lecho "Removing old update folder from /root/.creamcloud-backup/creamcloud-backup"
    rm -rf /root/.creamcloud-backup/creamcloud-backup
fi

lecho "Downloading CloudVPS Boss from ${DL_SRV}archive/refs/heads/master.tar.gz"
get_file "/root/.creamcloud-backup/creamcloud-backup.tar.gz" "${DL_SRV}archive/refs/heads/master.tar.gz"
if [[ $? -ne 0 ]]; then
    lecho "Download of cloudvps-boss failed. Check firewall and network connectivity."
    exit 1
fi

tar -xf creamcloud-backup.tar.gz
if [[ $? -ne 0 ]]; then
    lecho "Extraction of creamcloud-backup in /root/.creamcloud-backup failed."
    exit 1
fi
mv /root/.creamcloud-backup/backup-master /root/.creamcloud-backup/creamcloud-backup
popd
pushd /root/.creamcloud-backup/creamcloud-backup
bash install.sh
