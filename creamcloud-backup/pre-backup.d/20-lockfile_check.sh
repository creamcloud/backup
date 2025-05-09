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
TITLE="CloudVPS Boss Lockfile Check ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

DUPLICITY_LOCKFILE="$(find /root/.cache/duplicity -iname '*.lock' 2>&1 | head -n 1)"

greater_than_24hour_mail() {
    for COMMAND in "mail"; do
        command_exists "${COMMAND}"
    done

    mail -s "[CLOUDVPS BOSS] ${HOSTNAME}/$(curl -s http://ip.cloudvps.nl): Other backup job still running, more than 24 hours." "${recipient}" <<MAIL

Dear user,

This is a message to inform you that your backup to the CloudVPS
Object Store has not succeeded on date: $(date) (server date/time).

This is because the backup lockfile still exists.

The backupscript has noticed that the last initiated job was still running after 24 hours. This is unusual behaviour and could lead to hanging backup processes.

Should this process hang for 24 hours as well, you will receive this message again, then CloudVPS Boss needs investigation to see what is causing the issues. Please contact support@cloudvps.com and forward this email.

Your files have not been backupped during this session.

This is server $(curl -s http://ip.cloudvps.nl). You are using CloudVPS Boss ${VERSION}
to backup files to the CloudVPS Object Store.

Kind regards,
CloudVPS Boss
MAIL
}

send_greater_than_24hour_mail() {
    if [[ -f "/etc/creamcloud-backup/email.conf" ]]; then
        while read recipient; do
             greater_than_24hour_mail
        done < /etc/creamcloud-backup/email.conf
    else
        lerror "No email file found. Not mailing"
    fi
}

less_than_24hour_mail() {
    for COMMAND in "mail"; do
        command_exists "${COMMAND}"
    done

    mail -s "[CLOUDVPS BOSS] ${HOSTNAME}/$(curl -s http://ip.cloudvps.nl): Other backupjob still running, less than 24 hours." "${recipient}" <<MAIL

Dear user,

This is a message to inform you that your backup to the CloudVPS
Object Store has not succeeded on date: $(date) (server date/time).

This is because the backup lockfile still exists.

The script has investigated this problem and has stated that the current running backup process has not passed the 24 hour run limit yet.

Therefore this backup job will not continue to make sure that the current process can succeed without errors.

Currently, there is no intervention needed from your side, CloudVPS Boss has already chosen the appropriate solution at this point.

Your files have not been backupped during this session.

This is server $(curl -s http://ip.cloudvps.nl). You are using CloudVPS Boss ${VERSION}
to backup files to the CloudVPS Object Store.

Kind regards,
CloudVPS Boss
MAIL
}

send_less_than_24hour_mail() {
    if [[ -f "/etc/creamcloud-backup/email.conf" ]]; then
        while read recipient; do
             less_than_24hour_mail
        done < /etc/creamcloud-backup/email.conf
    else
        lerror "No email file found. Not mailing"
    fi
}

if [[ ! -z "${DUPLICITY_LOCKFILE}" ]]; then
    if [[ -f "${DUPLICITY_LOCKFILE}" ]]; then
        lecho "Duplicity Lockfile found"
        FILETIME="$(stat -c %Y ${DUPLICITY_LOCKFILE})"
        CURRTIME="$(date +%s)"
        TIMEDIFF="$(( (CURRTIME - FILETIME) / 84600))"
        if [[ ${TIMEDIFF} != 0 ]]; then
            lecho "Lockfile is older thay 24 hours."
            pgrep duplicity
            if [[ $? -ne 0 ]]; then
                lecho "Cannot find running duplicity process. Removing lockfile"
                rm "${DUPLICITY_LOCKFILE}"
                if [[ $? -ne 0 ]]; then
                    lerror "Cannot remove lockfile"
                fi
            else
                echo "Duplicity is still running, longer than 24 hours."
                send_greater_than_24hour_mail
            fi
        else
            lecho "Lockfile exists but is not older than 24 hours."
            pgrep duplicity
            if [[ $? -ne 0 ]]; then
                lecho "Cannot find running duplicity process. Removing lockfile"
                rm "${DUPLICITY_LOCKFILE}"
                if [[ $? -ne 0 ]]; then
                    lerror "Cannot remove lockfile"
                fi
            else
                echo "Duplicity is still running. Seems OK."
                touch /etc/creamcloud-backup/status/24h
                send_less_than_24hour_mail
            fi
        fi
    else
        lecho "Lockfile variable set but not a file. Lockfile var contents: ${DUPLICITY_LOCKFILE}."
    fi
else
    log "Lockfile not found."
fi

