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

VERSION="3.2.0"
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
# ------------------------------------------------------------------------------

MISSING=()

for COMMAND in git restic swift composer; do
    if ! command -v "${COMMAND}" >/dev/null 2>&1; then
        MISSING+=("${COMMAND}")
    fi
done

if ! command -v php >/dev/null 2>&1; then
    MISSING+=("php (>= 8.2, cli)")
else
    if ! php -r 'exit(version_compare(PHP_VERSION, "8.2.0", ">=") ? 0 : 1);'; then
        MISSING+=("php >= 8.2 (found $(php -r 'echo PHP_VERSION;') at $(command -v php))")
    fi
    for EXTENSION in mbstring xml curl; do
        if ! php -r "exit(extension_loaded('${EXTENSION}') ? 0 : 1);"; then
            MISSING+=("php extension ${EXTENSION}")
        fi
    done
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    lerror "The following required software is missing:"
    for ITEM in "${MISSING[@]}"; do
        lerror "  - ${ITEM}"
    done
    lerror "Please install it and re-run this script."
    exit 1
fi

lecho "Using $(php -r 'echo "PHP ", PHP_VERSION;') at $(command -v php)."

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
