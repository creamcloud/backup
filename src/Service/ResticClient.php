<?php

namespace App\Service;

use Symfony\Component\Process\Process;

/**
 * Thin wrapper around the restic binary, replacing the inline restic
 * invocations from creamcloud-backup.sh, -cleanup.sh, -list.sh,
 * -verify.sh and -restore.sh.
 *
 * Output is filtered the same way the original scripts did
 * (grep -v -e Warning -e pkg_resources -e oslo -e attr -e kwargs) and
 * forwarded to the ActivityLogger.
 */
final class ResticClient
{
    private const NOISE = ['Warning', 'pkg_resources', 'oslo', 'attr', 'kwargs'];

    public function __construct(
        private readonly string $resticRepository,
        private readonly string $resticPasswordFile,
        private readonly string $tempDir,
        private readonly string $osUsername,
        private readonly string $osPassword,
        private readonly string $osProjectName,
        private readonly string $osUserDomainName,
        private readonly string $osProjectDomainName,
        private readonly string $osRegionName,
        private readonly string $osAuthUrl,
        private readonly string $osIdentityApiVersion,
        private readonly ActivityLogger $logger,
    ) {
    }

    public function isInitialized(): bool
    {
        $process = $this->baseProcess(['cat', 'config']);
        $process->run();

        return $process->isSuccessful();
    }

    public function init(): ResticResult
    {
        return $this->runLogged($this->baseProcess(['init', '--verbose=1']));
    }

    /**
     * Initializes the repository if it has not been already, logging the action.
     */
    public function ensureInitialized(): bool
    {
        if ($this->isInitialized()) {
            return true;
        }

        $this->logger->info('Repository not yet initialized, running "restic init".');

        return $this->init()->success;
    }

    public function backup(string $path, string $excludeFile): ResticResult
    {
        return $this->runLogged($this->baseProcess([
            'backup', $path,
            '--exclude-file', $excludeFile,
            '--exclude-caches',
            '--cleanup-cache',
            '--verbose=1',
        ]), 'backup: ', [0, 3]);
    }

    public function forget(int $keepDaily, int $keepWeekly): ResticResult
    {
        return $this->runLogged($this->baseProcess([
            'forget',
            '--keep-daily', (string) $keepDaily,
            '--keep-weekly', (string) $keepWeekly,
            '--cleanup-cache',
            '--verbose=1',
        ]), 'cleanup: ');
    }

    public function unlock(bool $removeAll = false): ResticResult
    {
        $arguments = ['unlock', '--cleanup-cache', '--verbose=1'];
        if ($removeAll) {
            $arguments[] = '--remove-all';
        }

        return $this->runLogged($this->baseProcess($arguments), 'unlock: ');
    }

    public function listLocks(): array
    {
        $process = $this->baseProcess(['list', 'locks']);
        $process->run();
        if (!$process->isSuccessful()) {
            return [];
        }

        return array_values(array_filter(array_map('trim', explode("\n", $process->getOutput()))));
    }

    public function prune(): ResticResult
    {
        return $this->runLogged($this->baseProcess(['prune', '--cleanup-cache', '--verbose=1']));
    }

    public function check(): ResticResult
    {
        return $this->runLogged($this->baseProcess(['check', '--cleanup-cache', '--verbose=1']));
    }

    public function snapshots(): ResticResult
    {
        return $this->runLogged($this->baseProcess(['snapshots', '--cleanup-cache', '--verbose=1']));
    }

    /**
     * Same as snapshots(), but returns the structured "restic snapshots
     * --json" data (for rendering as a table) instead of logging raw
     * output. Returns null on failure. Unlike snapshots(), there is no
     * $time filter here: "restic snapshots" has no such flag, callers
     * should filter the returned array themselves (each entry has a
     * "time" field).
     *
     * @return array<int, array{short_id: string, time: string, hostname?: string, paths?: string[]}>|null
     */
    public function snapshotsJson(): ?array
    {
        $process = $this->baseProcess(['snapshots', '--cleanup-cache', '--json']);
        $process->run();

        if (!$process->isSuccessful()) {
            foreach ($this->splitLines($process->getErrorOutput()) as $line) {
                $this->logger->error($line);
            }

            return null;
        }

        $snapshots = json_decode($process->getOutput(), true);

        return \is_array($snapshots) ? $snapshots : null;
    }

    /**
     * Deletes the given snapshots and immediately reclaims their storage
     * ("restic forget <id>... --prune"), rather than just marking them as
     * forgotten and leaving the data for a later "restic prune".
     *
     * @param string[] $snapshotIds
     */
    public function deleteSnapshots(array $snapshotIds): ResticResult
    {
        return $this->runLogged($this->baseProcess([
            'forget', ...$snapshotIds,
            '--prune',
            '--cleanup-cache',
            '--verbose=1',
        ]));
    }

    public function restore(string $snapshotId, string $include, string $target): ResticResult
    {
        return $this->runLogged($this->baseProcess([
            'restore', $snapshotId,
            '--include', $include,
            '--target', $target,
            '--verbose=1',
        ]));
    }

    /**
     * Streams `restic dump <snapshotId> <path>` to a local file. Used to
     * pull a MySQL dump (written pre-backup by MysqlDumpSubscriber) back
     * out of the repository for restores.
     */
    public function dumpToFile(string $snapshotId, string $path, string $destination): bool
    {
        $process = $this->baseProcess(['dump', $snapshotId, $path]);
        $process->setTimeout(null);

        $handle = fopen($destination, 'wb');
        $process->run(function (string $type, string $buffer) use ($handle): void {
            if (Process::OUT === $type) {
                fwrite($handle, $buffer);
            }
        });
        fclose($handle);

        if (!$process->isSuccessful()) {
            @unlink($destination);
            foreach ($this->splitLines($process->getErrorOutput()) as $line) {
                $this->logger->error($line);
            }

            return false;
        }

        return true;
    }

    private function baseProcess(array $arguments): Process
    {
        $base = ['restic', ...$arguments];
        if (!in_array('--repo', $arguments, true)) {
            $base[] = '--repo';
            $base[] = $this->resticRepository;
            $base[] = '--password-file';
            $base[] = $this->resticPasswordFile;
        }

        $process = new Process($base);
        $process->setTimeout(null);
        $process->setEnv([
            // Have restic use less memory while backing up.
            'GOGC' => '10',
            'TMPDIR' => $this->tempDir,
            'TMP' => $this->tempDir,
            'TEMP' => $this->tempDir,
            // Credentials for the restic "swift" backend, if used.
            'OS_USERNAME' => $this->osUsername,
            'OS_PASSWORD' => $this->osPassword,
            'OS_PROJECT_NAME' => $this->osProjectName,
            'OS_USER_DOMAIN_NAME' => $this->osUserDomainName,
            'OS_PROJECT_DOMAIN_NAME' => $this->osProjectDomainName,
            'OS_REGION_NAME' => $this->osRegionName,
            'OS_AUTH_URL' => $this->osAuthUrl,
            'OS_IDENTITY_API_VERSION' => $this->osIdentityApiVersion,
        ]);

        return $process;
    }

    /**
     * @param int[] $acceptableExitCodes exit codes that count as success, in
     *                                    addition to restic's own notion of
     *                                    success (exit code 0)
     */
    private function runLogged(Process $process, string $logPrefix = '', array $acceptableExitCodes = [0]): ResticResult
    {
        $process->run();

        $success = $process->isSuccessful() || in_array($process->getExitCode(), $acceptableExitCodes, true);

        $lines = [
            ...$this->splitLines($process->getOutput()),
            ...$this->splitLines($process->getErrorOutput()),
        ];

        foreach ($lines as $line) {
            if ($process->isSuccessful()) {
                $this->logger->info($logPrefix.$line);
            } else {
                $this->logger->error($line);
            }
        }

        return new ResticResult($success, $lines);
    }

    /**
     * @return string[]
     */
    private function splitLines(string $output): array
    {
        $lines = preg_split('/\r\n|\r|\n/', trim($output)) ?: [];

        return array_values(array_filter($lines, function (string $line): bool {
            if ('' === $line) {
                return false;
            }
            foreach (self::NOISE as $needle) {
                if (str_contains($line, $needle)) {
                    return false;
                }
            }

            return true;
        }));
    }
}
