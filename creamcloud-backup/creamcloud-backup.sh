#!/bin/bash
# CloudVPS Boss - Duplicity wrapper to back up to OpenStack Swift
# Copyright (C) 2018 Remy van Elst. (CloudVPS Backup to Object Store Script)
# Author: Remy van Elst, https://raymii.org

VERSION="2.0.0"
TITLE="CloudVPS Boss Backup ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

lecho "${TITLE} started on ${HOSTNAME} at $(date)."
echo
lecho "Running pre-backup scripts from /etc/creamcloud-backup/pre-backup.d/"
for SCRIPT in /etc/creamcloud-backup/pre-backup.d/*; do
    if [[ ! -d "${SCRIPT}" ]]; then
        if [[ -x "${SCRIPT}" ]]; then
            log "${SCRIPT}"
            ionice -c2 nice -n19 "${SCRIPT}"
            if [[ $? -ne 0 ]]; then
                lerror "Pre backup script ${SCRIPT} failed."
            fi
        fi
    fi
done

echo
lecho "Create full backup if last full backup is older than: ${FULL_IF_OLDER_THAN} and keep at max ${FULL_TO_KEEP} full backups."
lecho "Starting Restic"

lecho "restic backup /data --repo ${BACKUP_BACKEND} --exclude-file=/etc/creamcloud-backup/exclude.conf --password-file=/etc/creamcloud-backup/restic-password.conf --verbose=1"

OLD_IFS="${IFS}"
IFS=$'\n'
DUPLICITY_OUTPUT=$(restic backup /data \
    --repo ${BACKUP_BACKEND} \
    --exclude-file=/etc/creamcloud-backup/exclude.conf \
    --password-file=/etc/creamcloud-backup/restic-password.conf \
    --verbose=1 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e attr -e kwargs)

if [[ $? -ne 0 ]]; then
    for line in ${DUPLICITY_OUTPUT}; do
            lerror ${line}
    done
    lerror "CloudVPS Boss Backup to Object Store FAILED!. Please check server ${HOSTNAME}."
    lerror "Running post-fail-backup scripts from /etc/creamcloud-backup/post-fail-backup.d/"
    for SCRIPT in /etc/creamcloud-backup/post-fail-backup.d/*; do
        if [[ ! -d "${SCRIPT}" ]]; then
            if [[ -x "${SCRIPT}" ]]; then
                "${SCRIPT}" || lerror "Post fail backup script ${SCRIPT} failed."
            fi
        fi
    done
    exit 1
fi

for line in ${DUPLICITY_OUTPUT}; do
        lecho "${line}"
done
IFS="${OLD_IFS}"

echo
lecho "CloudVPS Boss Cleanup ${VERSION} started on $(date). Removing all and keep ${KEEP_DAILY} daily backups and ${KEEP_WEEKLY} weekly backups."
lecho "restic forget --repo ${BACKUP_BACKEND} --exclude-file=/etc/creamcloud-backup/exclude.conf --password-file=/etc/creamcloud-backup/restic-password.conf --keep-daily ${KEEP_DAILY} --keep-weekly ${KEEP_WEEKLY} --verbose=1"

OLD_IFS="${IFS}"
IFS=$'\n'
DUPLICITY_OUTPUT=$(restic forget \
    --repo ${BACKUP_BACKEND} \
    --exclude-file=/etc/creamcloud-backup/exclude.conf \
    --password-file=/etc/creamcloud-backup/restic-password.conf \
    --keep-daily ${KEEP_DAILY} \
    --keep-weekly ${KEEP_WEEKLY} \
    --verbose=1 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e attr -e kwargs)

if [[ $? -ne 0 ]]; then
    for line in ${DUPLICITY_CLEANUP_OUTPUT}; do
            lerror ${line}
    done
    lerror "CloudVPS Boss Cleanup FAILED!. Please check server ${HOSTNAME}."
fi

for line in ${DUPLICITY_CLEANUP_OUTPUT}; do
        lecho "cleanup: ${line}"
done
IFS="${OLD_IFS}"

echo
lecho "Running post-backup scripts from /etc/creamcloud-backup/post-backup.d/"
for SCRIPT in /etc/creamcloud-backup/post-backup.d/*; do
    if [[ ! -d "${SCRIPT}" ]]; then
        if [[ -x "${SCRIPT}" ]]; then
            "${SCRIPT}" || lerror "Post backup script ${SCRIPT} failed."
        fi
    fi
done

echo
lecho "CloudVPS Boss ${VERSION} ended on $(date)."
