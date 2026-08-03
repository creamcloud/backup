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

VERSION="3.0.0"
TITLE="Cream Cloud Backup Install ${VERSION}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/creamcloud-backup"

if [[ "${DEBUG:-}" == "1" ]]; then
    set -x
fi

lecho() {
    logger -t "creamcloud-backup" -- "$1"
    echo "# $1"
}

lerror() {
    logger -t "creamcloud-backup" -- "ERROR - $1"
    echo "$1" 1>&2
}

if [[ "${EUID}" -ne 0 ]]; then
    lerror "This script must be run as root."
    exit 1
fi

usage() {
    cat <<USAGE
Usage:
  Interactive install (asks for OpenStack Object Store credentials, hostname
  and restic repository password):
    ./install.sh

  Unattended install:
    ./install.sh --username=USERNAME --password=PASSWORD --project-id=PROJECT_ID \\
        --region=REGION --user-domain-name=USER_DOMAIN_NAME \\
        --project-domain-name=PROJECT_DOMAIN_NAME \\
        --hostname=HOSTNAME --restic-password=RESTIC_PASSWORD

  Any other option accepted by "creamcloud-backup install" (e.g. --reinstall)
  can be passed here too; see "creamcloud-backup install --help".
USAGE
}

if [[ "${1:-}" == "help" ]]; then
    usage
    exit 0
fi

lecho "${TITLE} started on $(date)."

# ------------------------------------------------------------------------------
# Required system packages
# ------------------------------------------------------------------------------

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

install_packages_debian() {
    lecho "Installing required packages."
    apt-get -qq -y update
    apt-get -qq -y install git unzip curl ca-certificates restic python3-swiftclient \
        php-cli php-mbstring php-xml php-curl >/dev/null
}

install_packages_rhel() {
    lecho "Installing required packages."
    PKG_MGR="yum"
    command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf"
    "${PKG_MGR}" -q -y install git unzip curl ca-certificates restic python3-swiftclient \
        php-cli php-mbstring php-xml php-curl >/dev/null
}

DISTRO_NAME="$(distro_version name)"
DISTRO_VERSION="$(distro_version version)"

case "${DISTRO_NAME}" in
    Debian|Ubuntu)
        lecho "${DISTRO_NAME} ${DISTRO_VERSION}"
        install_packages_debian
        ;;
    CentOS|Fedora|Rocky|AlmaLinux|RedHatEnterpriseServer)
        lecho "${DISTRO_NAME} ${DISTRO_VERSION}"
        install_packages_rhel
        ;;
    *)
        lerror "Distro unknown or not supported."
        lerror "Please install git, unzip, curl, restic, python3-swiftclient and PHP >= 8.2"
        lerror "(with the cli, mbstring, xml and curl extensions) manually and re-run this script."
        ;;
esac

for COMMAND in git curl restic; do
    if ! command -v "${COMMAND}" >/dev/null 2>&1; then
        lerror "I require ${COMMAND} but it is not installed. Please install it and re-run this script."
        exit 1
    fi
done

if ! command -v php >/dev/null 2>&1 || ! php -r 'exit(version_compare(PHP_VERSION, "8.2.0", ">=") ? 0 : 1);'; then
    lerror "PHP >= 8.2 (cli) is required, but was not found."
    lerror "See https://www.php.net/manual/en/install.php for installation instructions."
    exit 1
fi

if ! command -v composer >/dev/null 2>&1; then
    lecho "Installing Composer to /usr/local/bin/composer."
    EXPECTED_SIGNATURE="$(curl -s https://composer.github.io/installer.sig)"
    curl -s -o /tmp/composer-setup.php https://getcomposer.org/installer
    ACTUAL_SIGNATURE="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"
    if [[ "${EXPECTED_SIGNATURE}" != "${ACTUAL_SIGNATURE}" ]]; then
        lerror "Composer installer signature mismatch, aborting."
        rm -f /tmp/composer-setup.php
        exit 1
    fi
    php /tmp/composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
    rm -f /tmp/composer-setup.php
fi

# ------------------------------------------------------------------------------
# Application dependencies
# ------------------------------------------------------------------------------

lecho "Installing PHP dependencies in ${PROJECT_DIR}."
composer install --no-interaction --no-dev --optimize-autoloader --working-dir="${PROJECT_DIR}"
if [[ $? -ne 0 ]]; then
    lerror "composer install failed."
    exit 1
fi

# ------------------------------------------------------------------------------
# Server configuration, restic repository, "creamcloud-backup" command and
# cron job. Everything past this point requires the PHP dependencies just
# installed above, so it is handled by the application's own installer.
# ------------------------------------------------------------------------------

chmod +x "${PROJECT_DIR}/bin/creamcloud-backup"
"${PROJECT_DIR}/bin/creamcloud-backup" install "$@"
