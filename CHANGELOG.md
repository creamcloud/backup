# Changelog

## 3.1.0

- The `self-update` command now also updates restic (`restic self-update`).

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
