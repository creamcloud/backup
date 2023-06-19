#!/bin/bash

VERSION="2.0.0"
TITLE="CloudVPS Boss Completed Status Upload ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

touch "/etc/creamcloud-backup/status/${HOSTNAME}/completed"
if [[ $? -ne 0 ]]; then
    lerror "Cannot update status"
    exit 1
fi

OLD_IFS="${IFS}"
IFS=$'\n'
SWIFTTOUCH=$(swift upload ${CONTAINER_NAME} "/etc/creamcloud-backup/status/${HOSTNAME}/completed" --object-name "status/${HOSTNAME}/completed" 2>&1 | grep -v -e Warning -e pkg_resources -e oslo)
if [[ $? -ne 0 ]]; then
    lerror "Could not upload completed status"
    for line in ${SWIFTTOUCH}; do
        lerror ${line}
    done
fi
IFS="${OLD_IFS}"

lecho "${TITLE} ended on ${HOSTNAME} at $(date)."
