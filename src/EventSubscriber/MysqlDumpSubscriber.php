<?php

namespace App\EventSubscriber;

use App\Event\PreBackupEvent;
use App\Service\ActivityLogger;
use App\Service\MysqlCredentials;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Process\ExecutableFinder;
use Symfony\Component\Process\Process;

/**
 * Dumps every (non-system) MySQL database to gzip files before the
 * backup runs, replacing pre-backup.d/30-mysql_backup.sh. The dumps are
 * picked up by "restic backup" because they live under $sqlBackupDir
 * (DATA_DIR/sql, /var/creamcloud/backup/sql by default), which is not
 * excluded.
 */
final class MysqlDumpSubscriber implements EventSubscriberInterface
{
    private const SYSTEM_DATABASES = ['information_schema', 'mysql', 'performance_schema', 'sys'];

    private readonly Filesystem $filesystem;
    private readonly ExecutableFinder $executableFinder;

    public function __construct(
        private readonly MysqlCredentials $credentials,
        private readonly ActivityLogger $logger,
        private readonly string $sqlBackupDir,
    ) {
        $this->filesystem = new Filesystem();
        $this->executableFinder = new ExecutableFinder();
    }

    public static function getSubscribedEvents(): array
    {
        return [
            PreBackupEvent::class => ['onPreBackup', 80],
        ];
    }

    public function onPreBackup(PreBackupEvent $event): void
    {
        if (null === $this->executableFinder->find('mysql') || null === $this->executableFinder->find('mysqldump')) {
            $this->logger->debug('mysql or mysqldump not found, not dumping MySQL databases.');

            return;
        }

        if (!$this->credentials->ensureCredentials()) {
            return;
        }

        $databases = $this->listDatabases();
        if ([] === $databases) {
            $this->logger->error('No databases found. Not backing up MySQL.');

            return;
        }

        $this->logger->info('Cleaning up old database dumps from '.$this->sqlBackupDir);
        $this->filesystem->mkdir($this->sqlBackupDir, 0700);
        foreach (glob($this->sqlBackupDir.'/*.sql.gz') ?: [] as $file) {
            $this->filesystem->remove($file);
        }

        foreach ($databases as $database) {
            $this->dumpDatabase($database);
        }
    }

    /**
     * @return string[]
     */
    private function listDatabases(): array
    {
        $process = new Process(['mysql', '-N', '-B', '-e', 'SHOW DATABASES;']);
        $process->run();

        if (!$process->isSuccessful()) {
            $this->logger->error('Could not list MySQL databases: '.trim($process->getErrorOutput()));

            return [];
        }

        $databases = [];
        foreach (explode("\n", trim($process->getOutput())) as $line) {
            $line = trim($line);
            if ('' !== $line && !in_array($line, self::SYSTEM_DATABASES, true)) {
                $databases[] = $line;
            }
        }

        return $databases;
    }

    private function dumpDatabase(string $database): void
    {
        $destination = sprintf('%s/%s.sql.gz', $this->sqlBackupDir, $database);
        $this->logger->info(sprintf('Dumping database %s to %s', $database, $destination));

        // Stream mysqldump straight into gzip so the dump never passes through PHP.
        // Symfony Process buffers all stdout it receives in php://temp, which spills
        // to sys_get_temp_dir() (/tmp on the root disk): a full uncompressed copy of
        // the database. pipefail makes a failing mysqldump fail the whole pipeline.
        $dump = new Process([
            'bash', '-o', 'pipefail', '-c',
            'mysqldump --opt --single-transaction --quick --hex-blob --force --skip-lock-tables --max_allowed_packet=128M -- "$1" | gzip -1 > "$2"',
            'bash', $database, $destination,
        ]);
        $dump->setTimeout(null);
        $dump->run();

        if (!$dump->isSuccessful()) {
            $this->logger->error(sprintf('Database dump for %s failed: %s', $database, trim($dump->getErrorOutput())));
        }

        $this->logger->info(sprintf('Finished dumping database %s.', $database));
    }
}
