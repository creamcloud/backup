# Changelog

## 3.0.0

Complete rewrite of Cream Cloud Backup from a collection of bash scripts into a PHP, Symfony Console based application, installed as a single `creamcloud-backup` command with per-action subcommands.

- Replaced the separate `creamcloud-backup-*.sh` scripts with one `creamcloud-backup` command and its subcommands.
- Added an interactive `install` command that asks for this server's hostname and OpenStack Object Store credentials, generates (or accepts) the restic repository password, symlinks the `creamcloud-backup` binary, and installs the cron job and added `--reinstall` to reconfigure a server.
- Added `backup:delete`, to delete a specific snapshot (or every snapshot with `--all`) and immediately reclaim its storage.
- Replaced the `pre-backup.d/` / `post-backup.d/` / `post-fail-backup.d/` hook scripts with Symfony event subscribers, and failure notifications now go through Symfony Mailer.
- Split configuration into a committed `etc/backup.conf` (shared defaults) and a per-server `/etc/creamcloud-backup/backup.conf` (credentials and overrides).
