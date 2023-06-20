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

set -o pipefail

VERSION="2.0.0"
TITLE="CloudVPS Boss Install ${VERSION}"

if [[ ${DEBUG} == "1" ]]; then
    set -x
fi

lecho() {
    logger -t "creamcloud-backup" -- "$1"
    echo "# $1"
}

lerror() {
    logger -t "creamcloud-backup" -- "ERROR - $1"
    echo "$1" 1>&2
}

log() {
    logger -t "creamcloud-backup" -- "$1"
}

if [[ "${EUID}" -ne 0 ]]; then
   lerror "This script must be run as root."
   exit 1
fi

lecho "${TITLE} started on $(date)."

usage() {
    echo "Usage:"
    echo "To install Cream Cloud Backup with interactive username password question:"
    echo "./$0"
    echo; echo "To install Cream Cloud Backup non-interactive:"
    echo "./$0 username@domain.tld 'passw0rd' 'tenant id'"
}

if [[ ! -z "$1" ]]; then
    if [[ "$1" == "help" ]]; then
        usage
    fi
fi

run_script() {
    # check if $1 is a file and execute it with bash.
    # log result and exit if script fails.
    if [[ -f "$1" ]]; then
        log "Starting $1"
        bash "$1" "$2" "$3" "$4"
        if [[ $? == 0 ]]; then
            logger -t "creamcloud-backup" -- "$1 completed."
        else
            lerror "$1 did not exit cleanly."
            exit 1
        fi
    else
        lerror "Cannot find $1."
    fi
}

command_exists() {
    # check if command exists and fai otherwise
    command -v "$1" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        lerror "I require $1 but it's not installed. Please install it. I've tried to install it but that failed. Aborting."
        exit 1
    fi
}

## Why all this effort to manually install stuff in three different places you wonder? Because some people refuse to build images with curl included. Why? Who knows... That explains these next 100 or so lines of extra code...

distro_version() {
    if [[ -f "/etc/debian_version" ]]; then
        NAME="Debian"
        VERSION="$(awk -F. '{print $1}' /etc/debian_version)"
    fi
    if [[ -f "/etc/lsb-release" ]]; then
        NAME="$(awk -F= '/DISTRIB_ID/ {print $2}' /etc/lsb-release)"
        VERSION="$(awk -F= '/DISTRIB_RELEASE/ {print $2}' /etc/lsb-release)"
    fi
    if [[ -f "/etc/redhat-release" ]]; then
        NAME="$(awk '{ print $1 }' /etc/redhat-release)"
        VERSION="$(grep -Eo "[0-9]\.[0-9]" /etc/redhat-release | cut -d . -f 1)"
    fi
    if [[ -f "/etc/arch-release" ]]; then
        NAME="Arch"
        VERSION="Rolling"
    fi
    if [[ "$1" == "name" ]]; then
        echo "${NAME}"
    fi
    if [[ "$1" == "version" ]]; then
        echo "${VERSION}"
    fi
}

get_hostname() {
    # Try Openstack Metadata service first
    HOSTNAME="$(curl -m 3 -s http://169.254.169.254/openstack/latest/meta_data.json | grep -o '\"uuid\": \"[^\"]*\"' | awk -F\" '{print $4}')"
    if [[ -z "${HOSTNAME}" ]]; then
        # Otherwise XLS /var/fistboot
        if [[ -f "/var/firstboot/settings" ]]; then
            HOSTNAME="$(awk -F= '/hostname/ {print $2}' /var/firstboot/settings)"
        else
            # ask the system if all else fails.
            HOSTNAME="$(uname -n)"
        fi
    fi

    echo "${HOSTNAME}"
}

install_packages_debian() {
    lecho "Installing packages required for installation."
    APT_UPDATE="$(apt-get -qq -y --force-yes update > /dev/null 2>&1)"
    if [[ "$?" -ne 0 ]]; then
        lerror "'apt-get update' failed."
        exit 1
    fi
    for PACKAGE in awk sed grep tar gzip which openssl curl wget screen vim haveged unattended-upgrades; do
        /usr/bin/apt-get -qq -y --force-yes -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" install "${PACKAGE}" >/dev/null 2>&1
    done
}

install_packages_centos() {
    lecho "Installing packages required for installation."

    yum-config-manager --add-repo https://copr.fedorainfracloud.org/coprs/copart/restic/repo/epel-7/copart-restic-epel-7.repo

    for PACKAGE in awk sed grep tar gzip which openssl curl wget screen vim haveged yum-cron restic; do
        yum -q -y --disablerepo="*" --disableexcludes=main --enablerepo="base" --enablerepo="updates" --enablerepo="copr:copr.fedorainfracloud.org:copart:restic" install "${PACKAGE}" >/dev/null 2>&1
    done
}

DISTRO_NAME=$(distro_version name)
DISTRO_VERSION=$(distro_version version)

case "${DISTRO_NAME}" in
    "Debian")
        lecho "Debian ${DISTRO_VERSION}"
        install_packages_debian
    ;;
    "Ubuntu")
        lecho "Ubuntu ${DISTRO_VERSION}"
        install_packages_debian
    ;;
    "CentOS")
        lecho "CentOS ${DISTRO_VERSION}"
        install_packages_centos
    ;;

    *)
    lerror "Distro unknown or not supported"
    exit 1
    ;;
esac

for COMMAND in "awk" "sed" "grep" "tar" "gzip" "which" "openssl" "curl" "restic"; do
    command_exists "${COMMAND}"
done

if [[ -f "/etc/csf/csf.fignore" ]]; then
    # Add ourself to the csf file ignore list
    # lfd will not scan and mark us suspicious
    if [[ ! "$(grep 'creamcloud-backup' /etc/csf/csf.fignore)" ]]; then
        lecho "Adding exceptions for lfd."
        echo "/tmp/pip-build-root/*" >> /etc/csf/csf.fignore
        echo "/tmp/creamcloud-backup/*" >> /etc/csf/csf.fignore
        echo "/usr/local/creamcloud-backup/*" >> /etc/csf/csf.fignore
        echo "/etc/creamcloud-backup/*" >> /etc/csf/csf.fignore
        service lfd restart 2>&1 > /dev/null
    fi
    if [[ ! "$(grep '89.31.101.64' /etc/csf/csf.allow)" ]]; then
        # for regular iptables
        #-A OUTPUT -d 89.31.101.64/27 ! -o lo -p tcp -m tcp --dport 443 -j ACCEPT
        # Add a rule for the CloudVPS object store to CSF
        lecho "Adding exceptions for csf."
        csf -a "tcp|out|d=443|d=89.31.101.64/27" "CloudVPS Boss Object Store for backup" 2>&1 > /dev/null
        service csf restart 2>&1 > /dev/null
        csf -r 2>&1 > /dev/null
    fi
    if [[ ! "$(grep '31.3.100.121' /etc/csf/csf.allow)" ]]; then
        # for regular iptables
        #-A OUTPUT -d 31.3.100.121/29 ! -o lo -p tcp -m tcp --dport 443 -j ACCEPT
        # Add a rule for the CloudVPS object store to CSF
        lecho "Adding exceptions for csf."
        csf -a "tcp|out|d=443|d=31.3.100.121/29" "CloudVPS Boss Object Store for backup 2" 2>&1 > /dev/null
        service csf restart 2>&1 > /dev/null
        csf -r 2>&1 > /dev/null
    fi
fi

if [[ -d "/etc/creamcloud-backup" ]]; then
    # check if we already exist, if so, back us up
    lecho "Backing up /etc/creamcloud-backup to /var/backups/creamcloud-backup.$$"
    if [[ ! -d "/var/backups/creamcloud-backup.$$" ]]; then
        mkdir -p "/var/backups/creamcloud-backup.$$"
        if [[ "$?" -ne 0 ]]; then
            lerror "Cannot create folder /var/backups/creamcloud-backup.$$"
        fi
    fi

    cp -r "/etc/creamcloud-backup" "/var/backups/creamcloud-backup.$$"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot backup /etc/creamcloud-backup to /var/backups/creamcloud-backup.$$."
        exit 1
    fi

    if [[ -f "/etc/cron.d/creamcloud-backup" ]]; then
        cp -r "/etc/cron.d/creamcloud-backup" "/var/backups/creamcloud-backup.$$/creamcloud-backup.cron.bak"
        if [[ "$?" -ne 0 ]]; then
            lerror "Cannot backup /etc/cron.d/creamcloud-backup to /var/backups/creamcloud-backup.$$/creamcloud-backup.cron.bak."
            exit 1
        fi
    fi
fi

for FOLDER in "/etc/creamcloud-backup/pre-backup.d" "/etc/creamcloud-backup/post-backup.d" "/etc/creamcloud-backup/post-fail-backup.d"; do
    # create a few required folders
    if [[ ! -d "${FOLDER}" ]]; then
        mkdir -p "${FOLDER}"
        if [[ $? -ne 0 ]]; then
        lerror "Cannot create ${FOLDER}"
            exit 1
        fi
    fi
done

log "Extracting to /etc/creamcloud-backup/"
# we copy all the things manually because
# some users do a chattr +i on stuff they don't want
# overwritten. A cp -r fails and leaves inconsistent state,
# a manual copy only fails the chattr'd things.
for COPY_FILE in "README.md" "LICENSE.md" "CHANGELOG.md"; do
    cp "${COPY_FILE}" "/etc/creamcloud-backup/${COPY_FILE}"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot copy ${COPY_FILE} to /etc/creamcloud-backup/${COPY_FILE}."
    fi
done

for COPY_FILE in "creamcloud-backup.cron" "backup.conf" "creamcloud-backup-list-current-files.sh" "creamcloud-backup-verify.sh" "creamcloud-backup-cleanup.sh" "creamcloud-backup-restore.sh" "creamcloud-backup.sh" "creamcloud-backup-stats.sh" "creamcloud-backup-manual-full.sh" "creamcloud-backup-update.sh" "common.sh" "exclude.conf" "uninstall.sh"; do
    cp "creamcloud-backup/${COPY_FILE}" "/etc/creamcloud-backup/${COPY_FILE}"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot copy creamcloud-backup/${COPY_FILE} to /etc/creamcloud-backup/${COPY_FILE}."
    fi
done

for COPY_FILE in "10-upload-starting-status.sh" "20_lockfile_check.sh" "30-mysql_backup.sh"; do
    cp "creamcloud-backup/pre-backup.d/${COPY_FILE}" "/etc/creamcloud-backup/pre-backup.d/${COPY_FILE}"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot copy creamcloud-backup/${COPY_FILE} to /etc/creamcloud-backup/pre-backup.d/${COPY_FILE}."
    fi
done

for COPY_FILE in "10-upload-completed-status.sh"; do
    cp "creamcloud-backup/post-backup.d/${COPY_FILE}" "/etc/creamcloud-backup/post-backup.d/${COPY_FILE}"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot copy creamcloud-backup/${COPY_FILE} to /etc/creamcloud-backup/post-backup.d/${COPY_FILE}."
    fi
done

for COPY_FILE in "10-upload-fail-status.sh" "20-failure-notify.sh"; do
    cp "creamcloud-backup/post-fail-backup.d/${COPY_FILE}" "/etc/creamcloud-backup/post-fail-backup.d/${COPY_FILE}"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot copy creamcloud-backup/${COPY_FILE} to /etc/creamcloud-backup/post-fail-backup.d/${COPY_FILE}."
    fi
done

# See if we are upgrading and if so
# place back the important config files
for CONF_FILE in "auth.conf" "email.conf" "backup.conf" "custom.conf" "exclude.conf" "encryption.conf"; do
    if [[ -f "/var/backups/creamcloud-backup.$$/creamcloud-backup/${CONF_FILE}" ]]; then
        lecho "Update detected. Placing back file ${CONF_FILE}."
        cp -r "/var/backups/creamcloud-backup.$$/creamcloud-backup/${CONF_FILE}" "/etc/creamcloud-backup/${CONF_FILE}"
    fi
done

# complicated loop to run the installer and the credentials script
# with the correct parameters.
for SCRIPT in "credentials.sh"; do
    if [[ "${SCRIPT}" == "credentials.sh" ]]; then
        if [[ ! -z "$1" ]]; then
            if [[ ! -z "$2" ]]; then
                if [[ ! -z "$3" ]]; then
                    run_script "${SCRIPT}" "$1" "$2" "$3"
                else
                   run_script "${SCRIPT}"
                fi
            else
                run_script "${SCRIPT}"
            fi
        else
           run_script "${SCRIPT}"
        fi
    else
        run_script "${SCRIPT}"
    fi
done

# hostname is used by Duplicity...
HOSTNAME="$(get_hostname)"
# get and set the hostname in the config. Fails if config is chattr +i.
sed -i "s/replace_me/${HOSTNAME}/g" /etc/creamcloud-backup/backup.conf

if [[ ! -d "/etc/cron.d" ]]; then
    mkdir -p "/etc/cron.d"
fi

if [[ ! -f "/etc/cron.d/creamcloud-backup" ]]; then
    mv "/etc/creamcloud-backup/creamcloud-backup.cron" "/etc/cron.d/creamcloud-backup"
    if [[ "$?" -ne 0 ]]; then
        lerror "Cannot place cronjob in /etc/cron.d."
    fi
    # use awk to get a number between 0 and 6 for the hour
    RANDH="$(awk 'BEGIN{srand();print int(rand()*(0-6))+6 }')"
    RANDM="$(awk 'BEGIN{srand();print int(rand()*(0-59))+59 }')"
    # and 0 to 59 for the minutes. Then place it in the cronjob.
    sed -i -e "s/RANDH/${RANDH}/g" -e "s/RANDM/${RANDM}/g" /etc/cron.d/creamcloud-backup
    # and show the user
    lecho "Randomized cronjob time, will run on ${RANDH}:${RANDM}."
fi

if [[ ! -d "/usr/local/bin" ]]; then
    mkdir -p "/usr/local/bin"
fi

for COMMAND in "creamcloud-backup.sh" "creamcloud-backup-restore.sh" "creamcloud-backup-stats.sh" "creamcloud-backup-update.sh" "creamcloud-backup-list-current-files.sh" "creamcloud-backup-manual-full.sh"; do
    log "Creating symlink for /etc/creamcloud-backup/${COMMAND} in /usr/local/bin/${COMMAND%.sh}."
    chmod +x "/etc/creamcloud-backup/${COMMAND}"
    ln -fs "/etc/creamcloud-backup/${COMMAND}" "/usr/local/bin/${COMMAND%.sh}"
done

for FILE in "pre-backup.d/30-mysql_backup.sh" "post-backup.d/10-upload-completed-status.sh" "pre-backup.d/10-upload-starting-status.sh" "pre-backup.d/20_lockfile_check.sh" "post-fail-backup.d/10-upload-fail-status.sh" "post-fail-backup.d/20-failure-notify.sh"; do
    # make sure all files are executable
    chmod +x "/etc/creamcloud-backup/${FILE}"
done

echo
lecho "If you want to receive email notifications of issues, please install"
lecho "a mailserver and add email addresses, one per line, to the following"
lecho "file: /etc/creamcloud-backup/email.conf"
echo
lecho "CloudVPS Boss installation completed."
echo
