<?php

namespace App\Service;

/**
 * Locates MySQL administrator credentials and writes them to /root/.my.cnf
 * so that "mysql" / "mysqldump" can run unattended, replacing the
 * panel-detection logic from pre-backup.d/30-mysql_backup.sh.
 */
final class MysqlCredentials
{
    private const MY_CNF = '/root/.my.cnf';

    public function __construct(
        private readonly ActivityLogger $logger,
    ) {
    }

    /**
     * Ensures /root/.my.cnf exists, creating it from panel-specific
     * credentials if possible. Returns false if no credentials could be
     * found and none already existed.
     */
    public function ensureCredentials(): bool
    {
        if (is_file(self::MY_CNF)) {
            return true;
        }

        $this->logger->info('MySQL auth config not found. Creating it in '.self::MY_CNF.'.');

        [$user, $password] = $this->discoverCredentials();

        if (null === $user) {
            $this->logger->error('Could not find MySQL credentials. Please add them to '.self::MY_CNF.' to make MySQL backups work.');

            return false;
        }

        $contents = sprintf(
            "[mysqldump]\nuser=%s\npassword=%s\n[mysql]\nuser=%s\npassword=%s\n[client]\nuser=%s\npassword=%s\n",
            $user, $password, $user, $password, $user, $password,
        );

        file_put_contents(self::MY_CNF, $contents);
        chmod(self::MY_CNF, 0600);

        $this->logger->info('Written MySQL credentials to '.self::MY_CNF.'.');

        return true;
    }

    /**
     * @return array{0: ?string, 1: ?string}
     */
    private function discoverCredentials(): array
    {
        // DirectAdmin
        if (is_file('/usr/local/directadmin/conf/mysql.conf')) {
            $this->logger->info('Using MySQL config provided by DirectAdmin.');
            $config = parse_ini_file('/usr/local/directadmin/conf/mysql.conf') ?: [];

            return [$config['user'] ?? null, $config['passwd'] ?? null];
        }

        // cPanel / WHM ships a passwordless root user via the unix socket.
        if (is_dir('/usr/local/cpanel')) {
            $this->logger->info('Using MySQL config provided by cPanel/WHM.');

            return ['root', ''];
        }

        // Plesk
        if (is_file('/etc/psa/.psa.shadow')) {
            $this->logger->info('Using MySQL config provided by Plesk.');

            return ['admin', trim((string) file_get_contents('/etc/psa/.psa.shadow'))];
        }

        // Debian / Ubuntu maintain a "debian-sys-maint" superuser.
        if (is_file('/etc/mysql/debian.cnf')) {
            $this->logger->info('Using MySQL config provided by Debian/Ubuntu.');

            return $this->parseKeyValueFile('/etc/mysql/debian.cnf', 'user', 'password');
        }

        // ISPConfig 3
        if (is_file('/usr/local/ispconfig/server/lib/mysql_clientdb.conf')) {
            $this->logger->info('Using MySQL config provided by ISPConfig 3.');

            return $this->parseKeyValueFile('/usr/local/ispconfig/server/lib/mysql_clientdb.conf', 'clientdb_user', 'clientdb_password');
        }

        return [null, null];
    }

    /**
     * Extracts "key = value" (optionally PHP variable / quoted) style
     * assignments from a configuration file.
     *
     * @return array{0: ?string, 1: ?string}
     */
    private function parseKeyValueFile(string $path, string $userKey, string $passwordKey): array
    {
        $user = null;
        $password = null;

        foreach (file($path, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
            if (null === $user && preg_match('/'.preg_quote($userKey, '/')."\s*=\s*['\"]?([^'\";]+)/", $line, $matches)) {
                $user = trim($matches[1]);
            }
            if (null === $password && preg_match('/'.preg_quote($passwordKey, '/')."\s*=\s*['\"]?([^'\";]*)/", $line, $matches)) {
                $password = trim($matches[1]);
            }
        }

        return [$user, $password];
    }
}
