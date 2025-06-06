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
TITLE="CloudVPS Boss MySQL Backup ${VERSION}"

if [[ ! -f "/etc/creamcloud-backup/common.sh" ]]; then
    lerror "Cannot find /etc/creamcloud-backup/common.sh"
    exit 1
fi
source /etc/creamcloud-backup/common.sh

command -v mysql >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    MYSQLD=1
fi

command -v mysqldump >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
    MYSQLD=1
fi


failed_mail() {
    for COMMAND in "mail"; do
        command_exists "${COMMAND}"
    done

    mail -s "[CLOUDVPS BOSS] MySQL backup failed on ${HOSTNAME}/$(curl -s http://ip.cloudvps.nl)." "${recipient}" <<MAIL

Dear user,

This is a message to inform you that your MySQL database backup to the CloudVPS
Object Store has not succeeded on date: $(date) (server date/time).

This is because the MySQL credentials for the administrative user are incorrect. These credentials are stored in the file /root/.my.cnf. Please check these credentials and update them if needed.

You might receive this email after you've changed your MySQL administrative user password (root, da_admin, etc). Please update the /root/.my.cnf file as well. CloudVPS Boss uses this file to access and backup the MySQL databases.

If you've corrected the credentials error and you keep receiving this message, try to remove the file '/etc/creamcloud-backup/mysql_credentials_incorrect'.

Your MySQL databases have not been backupped during this session.

This is server $(curl -s http://ip.cloudvps.nl). You are using CloudVPS Boss ${VERSION}
to backup files to the CloudVPS Object Store.

Kind regards,
CloudVPS Boss
MAIL
}

send_failed_cred_mail() {
    if [[ -f "/etc/creamcloud-backup/email.conf" ]]; then
        while read recipient; do
             failed_mail
        done < /etc/creamcloud-backup/email.conf
    else
        lerror "No email file found. Not mailing."
    fi
}


if [[ "${MYSQLD}" == 1 ]]; then
    log "mysql or mysqldump not found, not dumping mysql."
    exit
fi


if [[ ! -d "/var/backups/sql" ]]; then
    mkdir -p "/var/backups/sql"
fi

for COMMAND in "mysql" "mysqldump"; do
    command_exists "${COMMAND}"
done

if [[ ! -f "/root/.my.cnf" ]]; then
    lecho "MySQL auth config not found. Creating it in /root/.my.cnf."
    MYSQL_USER="none"
    MYSQL_PASSWORD="none"
    # DirectAdmin:
    if [[ -d "/usr/local/directadmin" ]]; then
        lecho "Using MySQL config provided by Directadmin"
        source "/usr/local/directadmin/conf/mysql.conf"
        MYSQL_USER=${user}
        MYSQL_PASSWORD=${passwd}
    fi
    # cPanel / WHM:
    if [[ -d "/usr/local/cpanel" ]]; then
        lecho "Using MySQL config provided by cPanel/WHM"
        MYSQL_USER="root"
        MYSQL_PASSWORD=""
    fi
    # Parallels Plesk:
    if [[ -d "/usr/local/psa" ]]; then
        lecho "Using MySQL config provided by Plesk"
        MYSQL_USER="admin"
        MYSQL_PASSWORD="$(cat /etc/psa/.psa.shadow)"
    fi
    # OpenPanel / OpenApp:
    if [[ -d "/var/openpanel" ]]; then
        lecho "Using MySQL config provided by OpenPanel/OpenApp"
        MYSQL_USER="$(grep ^user < /etc/mysql/debian.cnf | head -1 | awk '{print $3}')"
        MYSQL_PASSWORD="$(grep ^password < /etc/mysql/debian.cnf | head -1 | awk '{print $3}')"
    fi
    # Debian / Ubuntu:
    if [[ -f "/etc/mysql/debian.cnf" ]]; then
        lecho "Using MySQL config provided by Debian/Ubuntu"
        MYSQL_USER="$(grep ^user < /etc/mysql/debian.cnf | head -1 | awk '{print $3}')"
        MYSQL_PASSWORD="$(grep ^password < /etc/mysql/debian.cnf | head -1 | awk '{print $3}')"
    fi
    # ISPConfig 3:
    if [[ -f "/usr/local/ispconfig/server/lib/mysql_clientdb.conf" ]]; then
        lecho "Using MySQL config provided by ISPConfig 3"
        MYSQL_USER="$(grep user < /usr/local/ispconfig/server/lib/mysql_clientdb.conf | awk '{print $3'} | sed "s/[';]//g")"
        MYSQL_PASSWORD="$(grep password < /usr/local/ispconfig/server/lib/mysql_clientdb.conf | awk '{print $3'} | sed "s/[';]//g")"
    fi

    if [[ "${MYSQL_USER}" == "none" ]]; then
        lerror "Could not find MySQL username. Please add it to /root/.my.cnf to make MySQL backups work."
    fi
    if [[ "${MYSQL_PASSWORD}" == "none" ]]; then
        lerror "Could not find MySQL password. Please add it to /root/.my.cnf to make MySQL backups work."
    fi

    cat << EOF > /root/.my.cnf
[mysqldump]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
[mysql]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
[client]
user=${MYSQL_USER}
password=${MYSQL_PASSWORD}
EOF
    chmod 600 "/root/.my.cnf"
fi

if [[ -f "/root/.my.cnf" ]]; then
    mysql -e 'SHOW FULL PROCESSLIST;' >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        if [[ -f "/etc/creamcloud-backup/mysql_credentials_incorrect" ]]; then
                lerror "MySQL credentials incorrect. Please update /root/.my.cnf with the correct credentials. Emailing user."
                send_failed_cred_mail
                exit 1
        else
            touch /etc/creamcloud-backup/mysql_credentials_incorrect
            lecho "MySQL credentials incorrect. Rebuilding file and retrying."
            mv /root/.my.cnf /root/.my.cnf.$$.bak
            bash /etc/creamcloud-backup/pre-backup.d/30-mysql_backup.sh
            if [[ $? -ne 0 ]]; then
                lecho "Rebuild and retry worked."
                rm /etc/creamcloud-backup/mysql_credentials_incorrect
                exit 0
            fi
        fi
    fi
fi

DATABASES="$(mysql -e 'SHOW DATABASES;' | grep -v -e 'Database' -e 'information_schema' -e 'mysql' -e 'performance_schema' -e 'sys')"

if [[ -z "${DATABASES}" ]]; then
    lerror "No databases found. Not backing up MySQL"
    exit 1
fi

lecho "Cleaning up old database backups from /var/backups/sql/"
if [[ -d /var/backups/sql ]]; then
    rm /var/backups/sql/*.sql.gz
fi

for DB in ${DATABASES}; do
    lecho "Dumping database ${DB} to /var/backups/sql/${DB}.sql.gz"
    ionice -c2 nice -n19 mysqldump --opt --single-transaction --quick --hex-blob --force --skip-lock-tables --max_allowed_packet=128M "${DB}" | ionice -c2 nice -n19 gzip > "/var/backups/sql/${DB}.sql.gz"
    if [[ $? -ne 0 ]]; then
        lerror "Database dump ${DB} failed."
    else
        lecho "Finished dumping database ${DB}"; echo
    fi
done


