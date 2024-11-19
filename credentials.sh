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

VERSION="2.0.0"
TITLE="CloudVPS Boss Credentials Config ${VERSION}"

if [[ ${DEBUG} == "1" ]]; then
    set -x
fi

usage() {
    echo "# ./${0} [username] [password] [project_id] [region] [user_domain_name] [project_domain_name]"
    echo "# Interactive: ./$0"
    echo "# Noninteractive: ./$0 'user@example.org' 'P@ssw0rd' 'aeae1234...'"
    exit 1
}

lecho() {
    logger -t "creamcloud-backup" -- "$1"
    echo "# $1"
}

lerror() {
    logger -t "creamcloud-backup" -- "ERROR - $1"
    echo "$1" 1>&2
}

if [[ "${EUID}" -ne 0 ]]; then
   lerror "This script must be run as root"
   exit 1
fi

if [[ ! -d "/etc/creamcloud-backup" ]]; then
    mkdir -p "/etc/creamcloud-backup"
    if [[ $? -ne 0 ]]; then
        lerror "Cannot create /etc/creamcloud-backup"
        exit 1
    fi
fi

if [[ -f "/etc/creamcloud-backup/auth.conf" ]]; then
    lecho "/etc/creamcloud-backup/auth.conf already exists. Not overwriting it"
    exit
fi

if [[ "${1}" == "help" ]]; then
    usage
elif [[ -z ${2} || -z ${1} || -z ${3} ]]; then
    echo; echo; echo; echo; echo;
    read -e -p "Openstack Username (user@example.org): " USERNAME
    read -e -s -p "Openstack Password (not shown): " PASSWORD
    echo
    read -e -p "Openstack Project ID: " PROJECT_ID
    read -e -p "OpenStack User Domain Name: " -i "transip" OS_USER_DOMAIN_NAME
    read -e -p "OpenStack Project Domain Name: " -i "transip" OS_PROJECT_DOMAIN_NAME
    read -e -p "Openstack Region: " -i "NL" OS_REGION
else
    USERNAME="${1}"
    PASSWORD="${2}"
    PROJECT_ID="${3}"
    OS_REGION="${4}"
    OS_USER_DOMAIN_NAME="${5}"
    OS_PROJECT_DOMAIN_NAME="${6}"
fi

if [[ -z "${USERNAME}" || -z "${PASSWORD}" || -z "${PROJECT_ID}" || -z "${OS_REGION}" || -z "${OS_USER_DOMAIN_NAME}" || -z "${OS_PROJECT_DOMAIN_NAME}" ]]; then
    echo
    lerror "Need username, password, project id, region and domain names."
    exit 1
fi

OS_BASE_AUTH_URL="https://auth.teamblue.cloud/v3"
OS_AUTH_URL="${OS_BASE_AUTH_URL}/auth/tokens"
OS_TENANTS_URL="${OS_BASE_AUTH_URL}/auth/projects"

command -v curl > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    command -v wget > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        lerror "I require curl or wget but none seem to be installed."
        lerror "Please install curl or wget"
        exit 1
    else
        PROJECT_NAME=$(wget -q --header="Content-Type: application/json" --header "Accept: application/json" -O - --post-data='{"auth": {"identity": {"methods": ["password"],"region": "'${OS_REGION}'","password": {"user": {"name": "'${USERNAME}'","domain": { "name": "'${OS_USER_DOMAIN_NAME}'" },"password": "'${PASSWORD}'"}}},"scope": {"project": {"id": "'${PROJECT_ID}'"}}}}' "${OS_AUTH_URL}" | jq -r '.token.project.name' )
    fi
else
    PROJECT_NAME=$(curl -s "${OS_AUTH_URL}" -X POST -H "Content-Type: application/json" -H "Accept: application/json"  -d '{"auth": {"identity": {"methods": ["password"],"region": "'${OS_REGION}'","password": {"user": {"name": "'${USERNAME}'","domain": { "name": "'${OS_USER_DOMAIN_NAME}'" },"password": "'${PASSWORD}'"}}},"scope": {"project": {"id": "'${PROJECT_ID}'"}}}}' | jq -r '.token.project.name' )
fi

if [[ -z "${PROJECT_ID}" ]]; then
    lerror "Project ID could not be found. Check username, password or network connectivity."
    exit 1
fi

if [[ -z "${PROJECT_NAME}" ]]; then
    lecho "Authentication failed!. Trying again."
    sleep 5
    command -v curl > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        command -v wget > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            lerror "I require curl or wget but none seem to be installed."
            lerror "Please install curl or wget"
            exit 1
        else
            PROJECT_NAME=$(wget -q --header="Content-Type: application/json" --header "Accept: application/json" -O - --post-data='{"auth": {"identity": {"methods": ["password"],"region": "'${OS_REGION}'","password": {"user": {"name": "'${USERNAME}'","domain": { "name": "'${OS_USER_DOMAIN_NAME}'" },"password": "'${PASSWORD}'"}}},"scope": {"project": {"id": "'${PROJECT_ID}'"}}}}' "${OS_AUTH_URL}" | jq -r '.token.project.name')
        fi
    else
        PROJECT_NAME=$(curl -s "${OS_AUTH_URL}" -X POST -H "Content-Type: application/json" -H "Accept: application/json"  -d '{"auth": {"identity": {"methods": ["password"],"region": "'${OS_REGION}'","password": {"user": {"name": "'${USERNAME}'","domain": { "name": "'${OS_USER_DOMAIN_NAME}'" },"password": "'${PASSWORD}'"}}},"scope": {"project": {"id": "'${PROJECT_ID}'"}}}}' | jq -r '.token.project.name' )
    fi
    if [[ -z "${PROJECT_NAME}" ]]; then
        lerror "Authentication failed after two tries! Check username, password or network connectivity."
        exit 1
    fi
fi

if [[ ! -f "/etc/creamcloud-backup/auth.conf" ]]; then
    touch "/etc/creamcloud-backup/auth.conf"
    chmod 600 "/etc/creamcloud-backup/auth.conf"
    cat << EOF > /etc/creamcloud-backup/auth.conf
export OS_USERNAME="${USERNAME}"
export OS_PASSWORD="${PASSWORD}"
export OS_PROJECT_NAME="${PROJECT_NAME}"
export OS_USER_DOMAIN_NAME="${OS_USER_DOMAIN_NAME}"
export OS_PROJECT_DOMAIN_NAME="${OS_PROJECT_DOMAIN_NAME}"
export OS_REGION_NAME=${OS_REGION}
export OS_AUTH_URL="${OS_BASE_AUTH_URL}"
export OS_IDENTITY_API_VERSION=3
EOF
    lecho "Written auth config to /etc/creamcloud-backup/auth.conf."
else
    lecho "/etc/creamcloud-backup/auth.conf already exists. Not overwriting it"
fi

lecho "Username: ${USERNAME}"
lecho "Auth URL: ${OS_BASE_AUTH_URL}"
lecho "Checking Swift Container for Backups: https://public.objectstore.eu/v1/${PROJECT_ID}/creamcloud-backup/"

curl -s -o /dev/null -X PUT -T "/etc/hosts" --user "${USERNAME}:${PASSWORD}" "https://public.objectstore.eu/v1/${PROJECT_ID}/creamcloud-backup/"
if [[ $? == 60 ]]; then
    # CentOS 5...
    lecho "Curl error Peer certificate cannot be authenticated with known CA certificates."
    lecho "This is probably CentOS 5. CentOS 5 is deprecated. Exiting"
    exit 1
fi
