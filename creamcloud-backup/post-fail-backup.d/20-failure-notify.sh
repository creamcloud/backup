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
TITLE="CloudVPS Boss Failure Notify ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

if [[ -f "/etc/creamcloud-backup/status/24h" ]]; then
    lecho "24 hour backup file found. Not sending email, removing file."
    rm "/etc/creamcloud-backup/status/24h"
    exit 0
fi

for COMMAND in "mail"; do
    command_exists "${COMMAND}"
done

getlogging() {
    if [[ -f /var/log/restic.log ]]; then
        lecho "200 most recent lines in /var/log/restic.log:"
        tail -n 200  /var/log/restic.log
    else
        if [[ -f "/var/log/messages" ]]; then
            lecho "10 most recent lines with creamcloud-backup ERROR in /var/log/messages:"
            grep "creamcloud-backup: ERROR" /var/log/messages | tail -n 10
        fi
        if [[ -f "/var/log/syslog" ]]; then
            lecho "10 most recent lines with creamcloud-backup ERROR in /var/log/syslog:"
            grep "creamcloud-backup: ERROR" /var/log/syslog | tail -n 10
        fi
    fi

}

errormail() {

    mail -s "[CLOUDVPS BOSS] ${HOSTNAME}/$(curl -s http://ip.cloudvps.nl): Critical error occurred during the backup!" "${recipient}" <<MAIL

Dear user,

This is a message to inform you that your backup to the CloudVPS
Object Store has not succeeded on date: $(date) (server date/time).

Here is some information:

===== BEGIN CLOUDVPS BOSS STATS =====
$(creamcloud-backup-stats)
===== END CLOUDVPS BOSS STATS =====

===== BEGIN CLOUDVPS BOSS ERROR LOG =====
$(getlogging)
===== END CLOUDVPS BOSS ERROR LOG =====

This is server $(curl -s http://ip.cloudvps.nl). You are using CloudVPS Boss ${VERSION}
to backup files to the CloudVPS Object Store.

Your files have not been backupped at this time. Please investigate this issue.

IMPORTANT: YOUR FILES HAVE NOT BEEN BACKED UP. PLEASE INVESTIGAE THIS ISSUE.

Kind regards,
CloudVPS Boss
MAIL
}

if [[ -f "/etc/creamcloud-backup/email.conf" ]]; then
    while read recipient; do
         errormail
    done < /etc/creamcloud-backup/email.conf
else
    lerror "No email file found. Not mailing"
fi
