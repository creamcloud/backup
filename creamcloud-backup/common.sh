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

set -o pipefail

if [[ ${DEBUG} == "1" ]]; then
    set -x
fi

trap ctrl_c INT

lecho() {
    logger -t "creamcloud-backup" -- "$1"
    echo "# $1"
}

log() {
    logger -t "creamcloud-backup" -- "$1"
}

lerror() {
    logger -t "creamcloud-backup" -- "ERROR - $1"
    echo "$1" 1>&2
}

PATH=/usr/local/bin:$PATH
PID="$$"

# Do not edit. Dirty Workaround for an openstack pbr bug. If not set, everything swift will fail miserably with errors like; Exception: Versioning for this project requires either an sdist tarball, or access to an upstream git repository. Are you sure that git is installed?
# Will be fixed when new pbr version supports the wheel install used by pip.
export PBR_VERSION="0.10.0"
PBR_VERSION="0.10.0"

if [[ "${EUID}" -ne 0 ]]; then
   lerror "This script must be run as root"
   exit 1
fi

if [[ ! -f "/etc/creamcloud-backup/auth.conf" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/auth.conf."
    exit 1
fi
if [[ ! -f "/etc/creamcloud-backup/backup.conf" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/backup.conf."
    exit 1
fi
if [[ ! -f "/etc/creamcloud-backup/restic-password.conf" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/restic-password.conf."
    exit 1
fi

CONTAINER_NAME="creamcloud-backup"
BACKUP_BACKEND="swift:${CONTAINER_NAME}:/"

source /etc/creamcloud-backup/auth.conf
source /etc/creamcloud-backup/backup.conf

TMP="${TEMPDIR}"
TEMP="${TEMPDIR}"
TMPDIR="${TEMPDIR}"

if [[ -f "/etc/creamcloud-backup/custom.conf" ]]; then
    source "/etc/creamcloud-backup/custom.conf"
    logger -t "creamcloud-backup" -- "Custom Configuration Loaded"
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        lerror "I require $1 but it's not installed. Aborting."
        exit 1
    fi
}

command_exists_non_verbose() {
    command -v "$1" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
}

remove_file() {
    if [[ -f "$1" ]]; then
        lecho "Removing file $1"
        rm "$1"
        if [[ "$?" != 0 ]]; then
            lerror "Could not remove file $1"
        fi
    fi
}

remove_folder() {
    if [[ -d "$1" ]]; then
        lecho "Removing folder $1"
        rm -r "$1"
        if [[ "$?" != 0 ]]; then
            lerror "Could not remove folder $1"
        fi
    fi
}

remove_symlink() {
    if [[ -h "$1" ]]; then
        lecho "Removing symlink $1"
        rm "$1"
        if [[ "$?" != 0 ]]; then
            lerror "Could not remove symlink $1"
        fi
    fi
}

get_hostname() {
    HOSTNAME="$(curl -m 3 -s http://169.254.169.254/openstack/latest/meta_data.json | grep -o '\"hostname\": \"[^\"]*\"' | awk -F\" '{print $4}')"
    SRV_IP_ADDR="$(curl -q -A CloudVPS-Boss -m 3 -o /dev/null -s https://raymii.org/ >/dev/null 2>/dev/null)"
    if [[ -z "${HOSTNAME}" ]]; then
        if [[ -f "/var/firstboot/settings" ]]; then
            HOSTNAME="$(awk -F= '/hostname/ {print $2}' /var/firstboot/settings)"
        else
            HOSTNAME="$(uname -n)"
        fi
    fi
    echo "${HOSTNAME}"
}

ctrl_c() {
    lerror "SIGINT received. Exiting."
    exit 1
}

check_choice() {
    if [[ -z "${!1}" ]]; then
        dialog --title "${TITLE} - Error" --msgbox "${2} must be set. Aborting" 5 50
        exit 1
    fi
}

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
    if [[ "$1" == "name" ]]; then
        echo "${NAME}"
    fi
    if [[ "$1" == "version" ]]; then
        echo "${VERSION}"
    fi
}

get_file() {
    # Download a file with curl or wget
    # get_file SAVE_TO URL
    if [[ -n "$1" && -n "$2" ]]; then
        command -v curl > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            command -v wget > /dev/null 2>&1
            if [[ $? -ne 0 ]]; then
                echo "I require curl or wget but none seem to be installed."
                echo "Please install curl or wget"
                exit 1
            else
                wget --quiet --output-document "$1" "$2"
            fi
        else
            curl --location --silent --output "$1" "$2"
        fi
    else
        echo "Not all required parameters received. Usage: get_file SAVE_TO URL"
        exit 1
    fi
}

if [[ ! -d "/etc/creamcloud-backup/status/${HOSTNAME}" ]]; then
    mkdir -p "/etc/creamcloud-backup/status/${HOSTNAME}"
    if [[ $? -ne 0 ]]; then
        lerror "Cannot create status folder"
        exit 1
    fi

    OLD_IFS="${IFS}"
    IFS=$'\n'
    RESTIC_OUTPUT=$(restic init / \
        --repo ${BACKUP_BACKEND} \
        --password-file=/etc/creamcloud-backup/restic-password.conf \
        --verbose=1 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e attr -e kwargs)

    if [[ $? -ne 0 ]]; then
        for line in ${RESTIC_OUTPUT}; do
                lerror ${line}
        done
        lerror "Restic repository initialisation FAILED!. Please check server ${HOSTNAME}."
        exit 1
    fi

    for line in ${RESTIC_OUTPUT}; do
            lecho "${line}"
    done
    IFS="${OLD_IFS}"

fi

for COMMAND in "awk" "sed" "grep" "tar" "wc" "seq" "gzip" "which" "openssl" "nice" "ionice"; do
    command_exists "${COMMAND}"
done

ACTUAL_HOSTNAME="$(get_hostname)"
logger -t "creamcloud-backup" -- "Configured hostname is ${HOSTNAME}."
logger -t "creamcloud-backup" -- "Actual hostname is ${ACTUAL_HOSTNAME}."
logger -t "creamcloud-backup" -- "${TITLE} started on ${HOSTNAME} at $(date)."
