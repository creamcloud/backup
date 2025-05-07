# Cream Cloud Backup

## Introduction<a id="intro"></a>

Cream Cloud Backup is a lightweight, open-source backup wrapper for Restic. It securely backs up files, folders, and databases to any Restic supported backend

## Table of Contents

<ol>
<li><a href="#intro">Introduction</a></li>
<li><a href="#install">Installation</a></li>
<li><a href="#update">Updating</a></li>
<li><a href="#config">Configuration</a></li>
<li><a href="#backup">Backup</a></li>
<li><a href="#restore">Restore</a></li>
<li><a href="#uninstall">Uninstall</a></li>
<li><a href="#license">License</a></li>
<li><a href="#authors">Authors</a></li>
</ol>

## Installation <a id="install"></a>

#### Installation

You need to run the installer as the `root` user. All the Cream Cloud Backup tools will check if they are executed as root and will fail otherwise.

Download the .tar.gz file containing the latest version of the application:

    wget -O creamcloud-backup.tar.gz https://github.com/creamcloud/backup/archive/refs/heads/master.tar.gz

Extract it:

    tar -xf creamcloud-backup.tar.gz

Go in the folder and start the installer:

    cd backup-master
    bash install.sh

If you want to start the installation unattended, give the username, password and object store credentials as options:

    cd backup-master
    bash install.sh [username] [password] [project_id] [region] [user_domain_name] [project_domain_name]

The installer will ask you for your Openstack Object Store Username, Password and Tenant ID. Your password will not be shown when you type it, you will also not see stars or some other masking.

## Updating <a id="update"></a>

To update Cream Cloud Backup manually, run:

    creamcloud-update

This command backs up your existing configuration—such as authentication, backup settings, and exclude rules—before replacing the script with the latest version. Your configurations will be restored automatically after the update.

Additionally, a cron job is installed to perform this update automatically on the first day of each month.

## Configuration <a id="config"></a>

The install script creates a default configuration for the backup process, with these settings in it:

- Keep 7 daily backups
- Keep 2 weekly backups

The settings can be found in `/etc/creamcloud-backup/backup.conf`:

    # Server hostname. Will be replaced during install. Must be unique among backuped servers.
    HOSTNAME="server.creamcloud.io"
    # Create a full backup if the last is older than X days.
    KEEP_DAILY="7"
    # Keep at max X full backups.
    KEEP_WEEKLY="2"
    # Only change this if your tmp folder is to small. See README
    TEMPDIR="/tmp"

If you want more or less retention, change the variables. For one week of retention, create a full backup if the other full is older than 7 days and keep at max 1 full backup. If you want a month of retention, create a full backup if the other full is older than 7 days and keep at max 4 full backups.

The auth.conf file has the credentials needed for Swift and Openstack authentication:

    export OS_USERNAME="USERNAME"
    export OS_PASSWORD="PASSWORD"
    export OS_PROJECT_NAME="PROJECT NAME"
    export OS_USER_DOMAIN_NAME="transip"
    export OS_PROJECT_DOMAIN_NAME="transip"
    export OS_REGION_NAME=NL
    export OS_AUTH_URL="https://auth.teamblue.cloud/v3"
    export OS_IDENTITY_API_VERSION=3

#### Custom Configuration <a id="customconfig"></a>

If you want to use a custom backend or extra Duplicity options you can configure those in the following file:

    /etc/creamcloud-backup/custom.conf

This file is not there by default, you should create it.

The following options are supported:

    BACKUP_BACKEND=''

If you want to use a container other than the default 'creamcloud-backup' you can change CONTAINER_NAME as shown in the example below.

    BACKUP_BACKEND='swift:CONTAINER_NAME:/'

You can also specify a custom backend here, this will be used instead of our Object Store. You can also specify custom options which will be added to every Duplicity command. For example, to use an FTP server:

    BACKUP_BACKEND='ftp://backup@example.com:Passw0rd@example.com'

## Backup <a id="backup"></a>

To run a backup manually, simply execute:

    creamcloud-backup

By default, Cream Cloud Backup also installs a cron job at /etc/cron.d/creamcloud-backup, which schedules a daily backup at a random time between 00:00 and 06:59. You can edit this file to change the backup frequency. For example, to run a backup every hour, update the cron entry to:

    1 * * * * root /usr/local/bin/creamcloud-backup

If you want to run a backup manually, use the command `creamcloud-backup`.

## Restore <a id="restore"></a>

To recover a file or a database, use the `creamcloud-backup-restore` command. It is installed together with the script during installation. It is a dialog based script which makes it easy to restore a file, folder or database.

The script consists of te following steps:

- Hostname

This is pre-filled with the current configured hostname (from backup.conf which was set during installation). If this is not equal to when the backups were made, the restore will fail. To restore from another machine, enter that hostname here.

- Type

Choose File/folder, MySQL database or PostgreSQL database.

- File/Folder/DB Name

Either the full path to the file or folder you want to restore, or the name of the database you want to restore.

If you want to restore the folder '/home/user/test' then enter '/home/user/test/'. If you select file, there will follow another question asking if you want to restore the file to its original location or to /var/backups/restore. If you restore the file to its original location it will overwrite *any* files/folders that already exist both there and in the backup with files from the backup. If you restore a folder, it does not alter or remove any files that are in the folder but not in the backup.

If the database exists in the backups it will be restored, overwriting any databases with the same name. Make sure MySQL superuser credentials are set in /root/.my.cnf, otherwise the restore will fail. Make sure PostgreSQL system user `postgres` exists, otherwise the restore will fail. Also make sure the database server is running.

- Restore Location

If you want to restore a file/folder this question will ask you if you want to restore it to its original location or restore it to /var/backups/restore/. If you restore the file to its original location it will overwrite *any* files/folders that already exist both there and in the backup with files from the backup. If you restore a folder, it does not alter or remove any files that are in the folder but not in the backup. If you restore to /var/backups/restore you can move the files/folders to another location yourself.

If you want to restore a database to another database you need to do that manually, by restoring the database dump (from /var/backups/sql) and them importing that to a new database with the respective tools.

- Restore date/time

Provide the snapshot ID from when you want to restore a backup.

You can use the `creamcloud-backup-stats` command to see which backup sets, dates and times are available. See below for more info on `creamcloud-backup-stats`.

- Confirmation

Provides an overview of what we are going to do and the last option to cancel it. Press Enter to start the restore. It will take a while, there is no progress output.

<a id="full"></a>

#### Where are my files/databases restored?

The file / folder is restored on the original location. All exisiting files already available on the filesystem and also in the backup will be overwritten with files/folders from the backup. If you restore a folder, if it exists on the filesytem, the entire folder will be overwritten.

For MySQL and Postgres databases, if the database already exists, all data will be overwritten with data from the backup. If the database does not exist, it will be created.

<a id="oth"></a>

#### Recover from another host

To recover data from another host (for example, after a reinstall or crash) you can follow the steps above. However, you must make sure the hostname given in to the restore script is the same as the hostname of the other machine. If you are going to restore a database you must make sure that a database server is available, running and accessible to the restore script.

<a id="inf"></a>

### Information and Statistics

Cream Cloud Backup provides a simple statistics and information program, `creamcloud-backup-stats`. It shows you parts of the configuration and the status of your backup and available snapshots. You can run it manually from the command line:

    creamcloud-backup-stats

Example output:

    =========================================
    # Start of Cream Cloud Backup Status 2.0.0
    # Hostname: creamcloud.io
    # External IP: 4.4.8.8
    # Username:
    # Storage used: 13G
    # Full backups to keep:
    # Create full backup if last full backup is older than:
    -----------------------------------------
    # Restic snapshots:
    # ID        Time                 Host                Tags        Paths
    # --------------------------------------------------------------------
    # bac71131  2025-05-01 06:59:06  creamcloud.io                   /
    # e322a6ae  2025-05-02 06:59:04  creamcloud.io                   /
    # f542be4e  2025-05-03 06:59:06  creamcloud.io                   /
    # a31ec4f7  2025-05-04 06:59:05  creamcloud.io                   /
    # bb8507f8  2025-05-05 06:59:04  creamcloud.io                   /
    # 58dfaa84  2025-05-06 06:59:04  creamcloud.io                   /
    # f390c894  2025-05-07 06:59:04  creamcloud.io                   /
    # --------------------------------------------------------------------
    # 7 snapshots
    # End of Cream Cloud Backup Status
    =========================================

## Uninstall <a id="uninstall"></a>

You can use the uninstall script to remove all of Cream Cloud Backup. It does not remove your backups itself, it only removes Cream Cloud Backup application from you server. Run it like so:

    /etc/creamcloud-backup/uninstall.sh

## License

    Cream Cloud Backup - Restic wrapper to back up to OpenStack Object Store

    Copyright (C):          Cream Commerce B.V., https://www.cream.nl/
    Based on the work of:   Remy van Elst, https://raymii.org/

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation; either version 2 of the License, or (at your
    option) any later version.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

Also see LICENSE.md for full text of GPLv2.

## Authors

- Copyright: Cream Commerce B.V., https://www.cream.nl/
- Author: Danny Verkade
- Based on the work of: Remy van Elst, https://raymii.org/

