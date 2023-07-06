#!/bin/bash
# CloudVPS Boss - Duplicity wrapper to back up to OpenStack Swift
# Copyright (C) 2018 Remy van Elst. (CloudVPS Backup to Object Store Script)
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
TITLE="CloudVPS Boss Backup Verify ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

lecho "${TITLE} started on ${HOSTNAME} at $(date)."

lecho "restic check --repo ${BACKUP_BACKEND} --password-file=/etc/creamcloud-backup/restic-password.conf --verbose=1"

OLD_IFS="${IFS}"
IFS=$'\n'
RESTIC_OUTPUT=$(restic check \
    --repo ${BACKUP_BACKEND} \
    --password-file=/etc/creamcloud-backup/restic-password.conf \
    --verbose=1 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e tar -e attr -e kwargs)

if [[ $? -ne 0 ]]; then
    for line in ${RESTIC_OUTPUT}; do
            lerror ${line}
    done
    lerror "CloudVPS Boss Verify FAILED!. Please check server ${HOSTNAME}."
fi

for line in ${RESTIC_OUTPUT}; do
        lecho "${line}"
done
IFS="${OLD_IFS}"

echo
lecho "CloudVPS Boss Verify ${VERSION} ended on $(date)."
