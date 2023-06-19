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

TITLE="CloudVPS Boss Uninstall ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

read -p "Would you like to completely remove CloudVPS Boss? Your backups will NOT be removed. [y/N]? " choice

if [[ "${choice}" = "y" ]]; then
    lecho "Removing CloudVPS Boss"
    for FILE in "/etc/cron.d/creamcloud-backup"; do
        remove_file "${FILE}"
    done
    for SYMLINK in "/usr/local/bin/creamcloud-backup" "/usr/local/bin/creamcloud-backup-restore" "/usr/local/bin/creamcloud-backup-stats" "/usr/local/bin/creamcloud-backup-list-current-files" "/usr/local/bin/creamcloud-backup-update"; do
        remove_symlink "${SYMLINK}"
    done
    for PIP_INSTALLED in "python-swiftclient" "python-keystoneclient" "argparse" "babel" "debtcollector" "futures" "iso8601" "netaddr" "oslo.config" "oslo.i18n" "oslo.serialization" "oslo.utils" "pbr" "prettytable" "requests" "six" "stevedore"; do
        for PIP_VERSION in "pip" "pip2" "pip27" "pip2.7"; do
            if [[ "$(command_exists_non_verbose ${PIP_VERSION})" ]]; then
                lecho "Uninstalling ${PIP_INSTALLED} with ${PIP_VERSION}."
                echo "y\n" | ${PIP_VERSION} -q uninstall "${PIP_INSTALLED}" 2>&1 > /dev/null
            fi
        done
    done
    for FOLDER in "/usr/local/creamcloud-backup"  "/etc/creamcloud-backup/"; do
        remove_folder "${FOLDER}"
    done
    cd
    exit
fi

lecho "Choice was not 'y'. Not removing anything. Exiting."
