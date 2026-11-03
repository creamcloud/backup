# Changelog

## 3.3.1
- Fixed initializing the repository on a new server with restic < 0.17 (e.g. 0.14 of Debian 12): it reports a missing repository with exit code 1 and "unable to open config file: ... Object Not Found" instead of exit code 10.
- Improvement: Changed the GZIP compression level for faster compression.

## 3.3.0
- Moved the tool's working data out of Debian's `/var/backups` into a single configurable `DATA_DIR` (default `/var/creamcloud/backup`): staged MySQL dumps in `sql/`, restore output in `restore/` and the restic cache in `cache/`.
- restic is now run with an explicit `--cache-dir`, so the cache no longer depends on `/root/.cache/restic`.
- The restore output and the restic cache are excluded from the backup.
- The repository is only initialized when restic reports it does not exist (exit code 10). Any other error when opening the repository is now logged as is, instead of triggering a failing `restic init`.

## 3.2.1 
- Added path to use local PHP to cronjob.

## 3.2.0
- Install only checks for installed packages and no longer installs them by itself. 

## 3.1.0

- The `self-update` command now also updates restic (`restic self-update`).
- The `backup:cleanup` command now also repairs the indexes. 

## 3.0.1

- Consider the backup also successful when Restic exits with status 3 (some source files could not be read, e.g. because they vanished mid-scan) rather than only status 0, since restic still saves a snapshot in that case.
- Added log prefix to several used commands

## 3.0.0

Complete rewrite of Cream Cloud Backup from a collection of bash scripts into a PHP, Symfony Console based application, installed as a single `creamcloud-backup` command with per-action subcommands.

- Replaced the separate `creamcloud-backup-*.sh` scripts with one `creamcloud-backup` command and its subcommands.
- Added an interactive `install` command that asks for this server's hostname and OpenStack Object Store credentials, generates (or accepts) the restic repository password, symlinks the `creamcloud-backup` binary, and installs the cron job and added `--reinstall` to reconfigure a server.
- Added `backup:delete`, to delete a specific snapshot (or every snapshot with `--all`) and immediately reclaim its storage.
- Replaced the `pre-backup.d/` / `post-backup.d/` / `post-fail-backup.d/` hook scripts with Symfony event subscribers, and failure notifications now go through Symfony Mailer.
- Split configuration into a committed `etc/backup.conf` (shared defaults) and a per-server `/etc/creamcloud-backup/backup.conf` (credentials and overrides).
- Moved the tool's working directories from `/var/backups/sql` and `/var/backups/restore` to `/var/backups/creamcloud-backup/sql` and `/var/backups/creamcloud-backup/restore`, so the staged MySQL dumps and restore output no longer sit alongside the OS package-state backups (`dpkg.*`, `alternatives.tar.*`, `apt.extended_states.*`) that Debian writes into `/var/backups`.
