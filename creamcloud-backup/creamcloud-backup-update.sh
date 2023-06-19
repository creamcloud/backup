#!/bin/bash
# CloudVPS Boss - Duplicity wrapper to back up to OpenStack Swift
# Copyright (C) 2017 Remy van Elst. (CloudVPS Backup to Object Store Script)
# Author: Remy van Elst, https://raymii.org
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation; either version 2 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#

VERSION="2.0.0"
DUPLICITY_VERSION="0.7.17"
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
