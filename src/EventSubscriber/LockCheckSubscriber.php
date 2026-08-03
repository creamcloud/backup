<?php

namespace App\EventSubscriber;

use App\Event\PreBackupEvent;
use App\Exception\BackupAbortedException;
use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;

/**
 * Checks for leftover restic locks before starting a backup, replacing
 * pre-backup.d/20-lockfile_check.sh.
 *
 * restic itself only removes locks held by processes that are no longer
 * running and that are older than its staleness threshold, so calling
 * "restic unlock" is enough to clear genuinely stale locks. If a lock
 * remains afterwards, another backup is still in progress and this run
 * is aborted.
 */
final class LockCheckSubscriber implements EventSubscriberInterface
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            PreBackupEvent::class => ['onPreBackup', 90],
        ];
    }

    /**
     * @throws BackupAbortedException if another backup is still running
     */
    public function onPreBackup(PreBackupEvent $event): void
    {
        $locks = $this->restic->listLocks();
        if ([] === $locks) {
            return;
        }

        $this->logger->info('Found existing restic lock(s), checking whether they are stale.');
        $this->restic->unlock();

        if ([] !== $this->restic->listLocks()) {
            throw new BackupAbortedException('Repository is locked by another, still running backup process. Skipping this run.');
        }

        $this->logger->info('Removed stale restic lock(s).');
    }
}
