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
lecho "Starting Duplicity"

lecho "duplicity --verbosity 9 --log-file /var/log/duplicity.log --volsize ${VOLUME_SIZE} --tempdir=\"${TEMPDIR}\" --file-prefix=\"${HOSTNAME}.\" --name=\"${HOSTNAME}.\" --exclude-device-files --allow-source-mismatch --num-retries 100 --exclude-filelist=/etc/creamcloud-backup/exclude.conf --full-if-older-than=\"${FULL_IF_OLDER_THAN}\" ${ENCRYPTION_OPTIONS} ${CUSTOM_DUPLICITY_OPTIONS} / ${BACKUP_BACKEND}"

OLD_IFS="${IFS}"
IFS=$'\n'
DUPLICITY_OUTPUT=$(duplicity \
    --verbosity 4 \
    --log-file /var/log/duplicity.log \
    --volsize=${VOLUME_SIZE} \
    --tempdir="${TEMPDIR}" \
    --file-prefix="${HOSTNAME}." \
    --name="${HOSTNAME}." \
    --exclude-device-files \
    --allow-source-mismatch \
    --num-retries 100 \
    --exclude-filelist=/etc/creamcloud-backup/exclude.conf \
    --full-if-older-than="${FULL_IF_OLDER_THAN}" \
    ${ENCRYPTION_OPTIONS} \
    ${CUSTOM_DUPLICITY_OPTIONS} \
    / \
    ${BACKUP_BACKEND} 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e tar -e attr -e kwargs| sed -n -e '/--------------/,/--------------/ p')

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
lecho "CloudVPS Boss Cleanup ${VERSION} started on $(date). Removing all but ${FULL_TO_KEEP} full backups."
lecho "duplicity --verbosity 9 --log-file /var/log/duplicity.log --file-prefix=\"${HOSTNAME}.\" --name=\"${HOSTNAME}.\" remove-all-but-n-full \"${FULL_TO_KEEP}\" ${ENCRYPTION_OPTIONS} --force  ${BACKUP_BACKEND}"

OLD_IFS="${IFS}"
IFS=$'\n'
DUPLICITY_CLEANUP_OUTPUT=$(duplicity \
    --verbosity 4 \
    --log-file /var/log/duplicity.log \
    --file-prefix="${HOSTNAME}." \
    --name="${HOSTNAME}." \
    remove-all-but-n-full \
    "${FULL_TO_KEEP}" \
    ${ENCRYPTION_OPTIONS} \
    --force \
    ${BACKUP_BACKEND} 2>&1 | grep -v -e Warning -e pkg_resources -e oslo -e attr -e kwargs)
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
