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
TITLE="CloudVPS Boss Start Status Upload ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

touch "/etc/creamcloud-backup/status/${HOSTNAME}/started"
if [[ $? -ne 0 ]]; then
    lerror "Cannot update status"
    exit 1
fi

OLD_IFS="${IFS}"
IFS=$'\n'
SWIFTTOUCH=$(swift upload ${CONTAINER_NAME} "/etc/creamcloud-backup/status/${HOSTNAME}/started" --object-name "status/${HOSTNAME}/started" 2>&1 | grep -v -e Warning -e pkg_resources -e oslo)
if [[ $? -ne 0 ]]; then
    lerror "Could not upload status"
    for line in ${SWIFTTOUCH}; do
        lerror ${line}
    done
fi
IFS="${OLD_IFS}"


lecho "Logging version of CloudVPS Boss to Object Store: ${VERSION}"

touch "/etc/creamcloud-backup/status/${HOSTNAME}/version-${VERSION}"
if [[ $? -ne 0 ]]; then
    lerror "Cannot update version"
fi

OLD_IFS="${IFS}"
IFS=$'\n'
SWIFTTOUCH=$(swift upload ${CONTAINER_NAME} "/etc/creamcloud-backup/status/${HOSTNAME}/version-${VERSION}" --object-name "status/${HOSTNAME}/version-${VERSION}" 2>&1 | grep -v -e UserWarning -e pkg_resources -e oslo)
if [[ $? -ne 0 ]]; then
    lerror "Could not upload version"
    for line in ${SWIFTTOUCH}; do
        lerror ${line}
    done
fi
IFS="${OLD_IFS}"
