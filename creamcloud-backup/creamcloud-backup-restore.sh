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
TITLE="CloudVPS Boss Restore ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

lecho "${TITLE} started on ${HOSTNAME} at $(date)."

for COMMAND in "restic" "rsync" "gzip" "sed" "grep" "tar" "which" "dialog" "openssl"; do
    command_exists "${COMMAND}"
done

DIALOG_1_MESSAGE="Hello. This is the Cream Cloud Backup Restore script. \n\nIt will restore either files or a database from your Object Store Backup. The script will ask the following questions before restoring:\n\n - Hostname \n - Type (File/Database)\n - Path/Database Name \n - Restore from Snapshot ID\n\nPlease press return to continue."

DIALOG_2_MESSAGE="Please enter the hostname of the backup you want to restore. \n\nIt is pre-filled with the currently configured hostname (from backup.conf which was set during installation). If this is not equal to when the backups were made, the restore will fail. \nDo not enter the domain name or a dot at the end. For tank.example.org just enter tank"

DIALOG_3_MESSAGE="What type of restore do you want to do?"

DIALOG_4_MESSAGE="Please enter the full path to the file or folder you want to backup. \n\nIf you want to restore the folder '/home/user/test' then enter '/home/user/test/'. The next question will ask you if you want to restore the backup to its original location or to /var/restore."

DIALOG_11_MESSAGE="Do you wan to restore the folder to its original location or to /var/restore.${PID}/ ?\nIf you restore a file/folder to it's original location it will overwrite *any* files/folders that already exist both there and in the backup with files from the backup. \nIf you restore a folder to it's original location, it does not alter or remove any files that are in the folder but not in the backup.\nIf you restore a folder to /var/restore.${PID}/ you will find the original contents there and you can move it to another location yourself."

DIALOG_5_MESSAGE="Please enter the MySQL database name.\n\nIf it exists in the backups it will be restored, overwriting any databases with the same name. \nMake sure MySQL superuser credentials are set in /root/.my.cnf, otherwise the restore will fail. See documentation for more info. \nAlso make sure the database server is running."

DIALOG_6_MESSAGE="Please enter the PostgreSQL database name.\n\nIf it exists in the backups it will be restored, overwriting any databases with the same name. \nMake sure PostgreSQL system user postgres exists, otherwise the restore will fail. See documentation for more info. \nAlso make sure the database server is running."

DIALOG_7_MESSAGE="Please enter the snapshot ID. This can be found with the command creamcloud-backup-list it is a string with random characters which looks like: 69af8005 although the characters may be different."

dialog --title "${TITLE} - Introduction" --msgbox "${DIALOG_1_MESSAGE}" 20 65

dialog --title "${TITLE} - Hostname" --inputbox "${DIALOG_2_MESSAGE}" 0 0 "${HOSTNAME}" 2> "/tmp/${PID}.hostname"

HOSTNAME=$(cat /tmp/${PID}.hostname && rm /tmp/${PID}.hostname)

check_choice HOSTNAME "Hostname"

dialog --title "${TITLE} - Restore Type" --menu "${DIALOG_3_MESSAGE}" 0 0 0 "1" "File/folder restore"  "2" "MySQL Database" "3" "PostgreSQL Database" 2> "/tmp/${PID}.restore-type"

RESTORE_TYPE="$(cat /tmp/${PID}.restore-type && rm /tmp/${PID}.restore-type)"

check_choice RESTORE_TYPE "Restore type"


if [[ "${RESTORE_TYPE}" == 1 ]]; then

    dialog --title "${TITLE} - Original Path" --inputbox "${DIALOG_4_MESSAGE}" 0 0 2> "/tmp/${PID}.original-path"

    ORIGINAL_PATH=$(cat /tmp/${PID}.original-path && rm /tmp/${PID}.original-path)

    check_choice ORIGINAL_PATH "Original path"

    dialog --title "${TITLE} - Restore Path" --menu "${DIALOG_11_MESSAGE}" 0 0 0 "1" "Original location (${ORIGINAL_PATH})"  "2" "/var/restore.${PID}/" 2> "/tmp/${PID}.restore-path-choice"

    RESTORE_PATH_CHOICE=$(cat /tmp/${PID}.restore-path-choice && rm /tmp/${PID}.restore-path-choice)

    check_choice RESTORE_PATH_CHOICE "Restore path"

    if [[ "${RESTORE_PATH_CHOICE}" == 1 ]]; then
        RESTORE_PATH="${ORIGINAL_PATH}"
    fi
    if [[ "${RESTORE_PATH_CHOICE}" == 2 ]]; then
        RESTORE_PATH="/var/restore.${PID}/"
    fi

    dialog --title "${TITLE} - Restore from Snapshot ID" --inputbox "${DIALOG_7_MESSAGE}" 0 0 2> "/tmp/${PID}.restore-snapshotid"

    RESTORE_SNAPSHOTID=$(cat /tmp/${PID}.restore-snapshotid && rm /tmp/${PID}.restore-snapshotid)

    check_choice RESTORE_SNAPSHOTID "Restore Snapshot ID"

    DIALOG_8_MESSAGE="Restoring file/folder \"$(dirname ${ORIGINAL_PATH})/$(basename ${ORIGINAL_PATH})\" from time ${RESTORE_SNAPSHOTID} for host ${HOSTNAME}.\n\nIt will be restored to ${RESTORE_PATH} .\nIf you want to cancel, press CTRL+C now. \nOtherwise, press return to continue."

    dialog --title "${TITLE} - Restore" --msgbox "${DIALOG_8_MESSAGE}" 20 70

    echo; echo; echo; echo; echo; echo;
    lecho "Restoring file/folder \"$(dirname ${ORIGINAL_PATH})/$(basename ${ORIGINAL_PATH})\" from time ${RESTORE_SNAPSHOTID} for host ${HOSTNAME}. It will be restored to ${RESTORE_PATH}. Date: $(date)."

    RELATIVE_PATH="${ORIGINAL_PATH:1}"

    lecho "restic restore ${RESTORE_SNAPSHOTID} --repo ${BACKUP_BACKEND} --password-file=/etc/creamcloud-backup/restic-password.conf --include=${RELATIVE_PATH} --target=/var/restore.${PID} --verbose=1"

    OLD_IFS="${IFS}"
    IFS=$'\n'
    RESTORE_OUTPUT=$(restic restore ${RESTORE_SNAPSHOTID} \
        --repo ${BACKUP_BACKEND} \
        --password-file=/etc/creamcloud-backup/restic-password.conf \
	      --include=${RELATIVE_PATH} \
        --target=/var/restore.${PID} \
        --verbose=1 2>&1 | grep -v -e Warning -e  pkg_resources -e oslo)
        if [[ $? -ne 0 ]]; then
            for line in ${RESTORE_OUTPUT}; do
                lerror ${line}
            done
            lerror "Restore FAILED. Please check logging, path name and network connectivity."
            exit 1
        fi
    for line in ${RESTORE_OUTPUT}; do
        lecho ${line}
    done
    IFS="${OLD_IFS}"

    if [[ "${RESTORE_PATH_CHOICE}" == 1 ]]; then
        if [[ ! -d "$(dirname ${RESTORE_PATH})" ]]; then
            mkdir -p "$(dirname ${RESTORE_PATH})"
        fi
        lecho "Moving /var/restore.${PID} to ${RESTORE_PATH}"
        if [[ -f "/var/restore.${PID}" ]]; then
            TYPEA="File"
            logger -t "creamcloud-backup" -- "FILE RESTORE TO ORIGINAL PATH"
            logger -t "creamcloud-backup" -- "rsync -azq \"/var/restore.${PID}\" \"${RESTORE_PATH}\""
            rsync -azq "/var/restore.${PID}" "${RESTORE_PATH}"
            if [[ $? -ne 0 ]]; then
                echo "File Restore unsuccessful. Please check logging, path name and network connectivity."
                exit 1
            fi
        fi
        if [[ -d "/var/restore.${PID}" ]]; then
            TYPEA="Folder"
            logger -t "creamcloud-backup" -- "DIRECTORY RESTORE TO ORIGINAL PATH"
            logger -t "creamcloud-backup" -- "rsync -azq \"/var/restore.${PID}/\" \"${RESTORE_PATH}\""
            rsync -azq "/var/restore.${PID}/" "${RESTORE_PATH}"
            if [[ $? -ne 0 ]]; then
                echo "Folder Restore unsuccessful. Please check logging, path name and network connectivity."
                exit 1
            fi
        fi
    fi
    lecho "${TYPEA} restore successfull."
fi

if [[ "${RESTORE_TYPE}" == 2 ]]; then

    for COMMAND in "mysql"; do
        command_exists "${COMMAND}"
    done

    dialog --title "${TITLE} - MySQL Database Name" --inputbox "${DIALOG_5_MESSAGE}" 0 0 2> "/tmp/${PID}.mysql-db-name"

    MYSQL_DB_NAME="$(cat /tmp/${PID}.mysql-db-name && rm /tmp/${PID}.mysql-db-name)"

    check_choice MYSQL_DB_NAME "MySQL Database Name"

    dialog --title "${TITLE} - Restore from Date" --inputbox "${DIALOG_7_MESSAGE}" 0 0 2> "/tmp/${PID}.restore-snapshotid"

    RESTORE_SNAPSHOTID="$(cat /tmp/${PID}.restore-snapshotid && rm /tmp/${PID}.restore-snapshotid)"

    check_choice RESTORE_SNAPSHOTID "Restore date/time"

    DIALOG_9_MESSAGE="Restoring MySQL database ${MYSQL_DB_NAME} from time ${RESTORE_SNAPSHOTID} for host ${HOSTNAME}. \nIt will be restored to /var/restore.${PID} and then placed back in the MySQL server. \nIf you want to cancel, press CTRL+C now. \nOtherwise, press return to continue."

    dialog --title "${TITLE} - Restore" --msgbox "${DIALOG_9_MESSAGE}" 10 70

    echo; echo; echo; echo; echo; echo;
    lecho "Restoring MySQL database ${MYSQL_DB_NAME} from time ${RESTORE_SNAPSHOTID} for host ${HOSTNAME}. It will be restored to /var/restore.${PID} and then placed back in the MySQL server. Date: $(date)."

    lecho "duplicity --file-prefix=\"${HOSTNAME}.\" --name=\"${HOSTNAME}.\" ${ENCRYPTION_OPTIONS} ${CUSTOM_DUPLICITY_OPTIONS} --allow-source-mismatch --num-retries 100 --tempdir=\"${TEMPDIR}\" -t ${RESTORE_SNAPSHOTID} --file-to-restore var/backups/sql/${MYSQL_DB_NAME}.sql.gz ${BACKUP_BACKEND} \"/var/restore.${PID}.gz\""

    OLD_IFS="${IFS}"
    IFS=$'\n'
    RESTORE_OUTPUT=$(duplicity \
        --file-prefix="${HOSTNAME}." \
        --name="${HOSTNAME}." \
        --allow-source-mismatch \
        --num-retries 100 \
        ${ENCRYPTION_OPTIONS} \
        ${CUSTOM_DUPLICITY_OPTIONS} \
        --tempdir "${TEMPDIR}" \
        -t ${RESTORE_DATETIME} \
        --file-to-restore var/backups/sql/${MYSQL_DB_NAME}.sql.gz \
        ${BACKUP_BACKEND} "/var/restore.${PID}.gz" 2>&1 | grep -v -e Warning -e  pkg_resources -e oslo)
        if [[ $? -ne 0 ]]; then
            for line in ${RESTORE_OUTPUT}; do
                lerror ${line}
            done
            lerror "Restore FAILED. Please check logging, path name and network connectivity."
            exit 1
        fi
    for line in ${RESTORE_OUTPUT}; do
        lecho ${line}
    done
    IFS="${OLD_IFS}"

    gzip -f -d "/var/restore.${PID}.gz"
    if [[ "$?" != 0 ]]; then
        echo "Gunzip unsuccessful. Please check logging, path name and network connectivity."
        exit 1
    fi

    DATABASE_EXISTS=$(mysql -e 'show databases;' | grep "${MYSQL_DB_NAME}")

    if [[ -z "${DATABASE_EXISTS}" ]]; then
        lecho "MySQL Database does not exist. Creating db ${MYSQL_DB_NAME}."
        CREATE_NON_EXIST_DB=$(mysql -e "create database ${MYSQL_DB_NAME};")
        if [[ "$?" != 0 ]]; then
            echo "Database Import unsuccessful. Please check logging, path name and network connectivity."
            exit 1
        fi
    fi

    mysql "${MYSQL_DB_NAME}" < "/var/restore.${PID}"
    if [[ "$?" != 0 ]]; then
        echo "Database Import unsuccessful. Please check logging, path name and network connectivity."
        exit 1
    fi
    lecho "MySQL restore successfull."

fi

if [[ "${RESTORE_TYPE}" == 3 ]]; then
    for COMMAND in "psql"; do
        command_exists "${COMMAND}"
    done

    dialog --title "${TITLE} - Postgresql Database Name" --inputbox "${DIALOG_6_MESSAGE}" 0 0 2> "/tmp/${PID}.psql-db-name"

    PSQL_DB_NAME=$(cat /tmp/${PID}.psql-db-name && rm /tmp/${PID}.psql-db-name)

    check_choice PSQL_DB_NAME "PSQL Database Name"

    dialog --title "${TITLE} - Restore from Date" --inputbox "${DIALOG_7_MESSAGE}" 0 0 2> "/tmp/${PID}.restore-datetime"

    RESTORE_DATETIME=$(cat /tmp/${PID}.restore-datetime && rm /tmp/${PID}.restore-datetime)

    check_choice RESTORE_DATETIME "Restore date/time"

    DIALOG_10_MESSAGE="Restoring PostgreSQL database ${PSQL_DB_NAME} from time ${RESTORE_DATETIME} for host ${HOSTNAME}. \nIt will be restored to /var/restore.${PID} and then placed back in the PostgreSQL server. \nIf you want to cancel, press CTRL+C now. \nOtherwise, press return to continue."

    dialog --title "${TITLE} - Restore" --msgbox "${DIALOG_10_MESSAGE}" 10 70

    echo; echo; echo; echo; echo; echo;
    lecho "Restoring PostgreSQL database ${PSQL_DB_NAME} from time ${RESTORE_DATETIME} for host ${HOSTNAME}. It will be restored to /var/restore.${PID} and then placed back in the PostgreSQL server. Date: $(date)."

    lecho "duplicity --file-prefix=\"${HOSTNAME}.\" --name=\"${HOSTNAME}.\" ${ENCRYPTION_OPTIONS} ${CUSTOM_DUPLICITY_OPTIONS} --allow-source-mismatch --num-retries 5 --tempdir=\"${TEMPDIR}\" -t ${RESTORE_DATETIME} --file-to-restore var/backups/sql/${PSQL_DB_NAME}.psql.gz ${BACKUP_BACKEND} \"/var/restore.${PID}.gz\""

    OLD_IFS="${IFS}"
    IFS=$'\n'
    RESTORE_OUTPUT=$(duplicity \
        --file-prefix="${HOSTNAME}." \
        --name="${HOSTNAME}." \
        ${ENCRYPTION_OPTIONS} \
        ${CUSTOM_DUPLICITY_OPTIONS} \
        --allow-source-mismatch \
        --num-retries 5 \
        --tempdir "${TEMPDIR}" \
        -t ${RESTORE_DATETIME} \
        --file-to-restore var/backups/sql/${PSQL_DB_NAME}.psql.gz \
        ${BACKUP_BACKEND} "/var/restore.${PID}.gz" 2>&1 | grep -v -e Warning -e  pkg_resources -e oslo)
        if [[ $? -ne 0 ]]; then
            for line in ${RESTORE_OUTPUT}; do
                lerror ${line}
            done
            lerror "Restore FAILED. Please check logging, path name and network connectivity."
            exit 1
        fi
    for line in ${RESTORE_OUTPUT}; do
        lecho ${line}
    done
    IFS="${OLD_IFS}"

    gzip -f -d "/var/restore.${PID}.gz"
    if [[ $? -ne 0 ]]; then
        echo "Gunzip unsuccessful. Please check logging, path name and network connectivity."
        exit 1
    fi

    chmod 777 /var/restore.${PID}
    if [[ -z "$(su postgres -c "psql -l | awk '{print $1}' | grep \"${PSQL_DB_NAME}\"")" ]]; then
        lecho "Database not found, creating empty DB"
        su postgres -c "createdb ${PSQL_DB_NAME}"
    fi
    OLD_IFS="${IFS}"
    IFS=$'\n'
    PG_RESTORE_OUTPUT=$(su postgres -c "psql \"${PSQL_DB_NAME}\" < \"/var/restore.${PID}\"")
    if [[ $? -ne 0 ]]; then
        for line in ${PG_RESTORE_OUTPUT}; do
                lerror ${line}
            done
            lerror "Database Import FAILED. Please check logging, path name and network connectivity."
            exit 1
        fi
    for line in ${PG_RESTORE_OUTPUT}; do
        lecho ${line}
    done
    IFS="${OLD_IFS}"
    lecho "PostgresSQL restore successfull."

fi

lecho "${TITLE} ended on ${HOSTNAME} at $(date)."
