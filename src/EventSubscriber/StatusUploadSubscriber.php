<?php

namespace App\EventSubscriber;

use App\Event\BackupFailedEvent;
use App\Event\PostBackupEvent;
use App\Event\PreBackupEvent;
use App\Service\ActivityLogger;
use App\Service\SwiftClient;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\Filesystem\Filesystem;

/**
 * Uploads small marker objects ("started", "completed", "failed",
 * "version-x.y.z") to the Swift container, replacing
 * pre-backup.d/10-upload-starting-status.sh,
 * post-backup.d/10-upload-completed-status.sh and
 * post-fail-backup.d/10-upload-fail-status.sh.
 */
final class StatusUploadSubscriber implements EventSubscriberInterface
{
    private readonly Filesystem $filesystem;

    public function __construct(
        private readonly SwiftClient $swift,
        private readonly ActivityLogger $logger,
        private readonly string $hostname,
        private readonly string $varDir,
        private readonly string $version,
    ) {
        $this->filesystem = new Filesystem();
    }

    public static function getSubscribedEvents(): array
    {
        return [
            PreBackupEvent::class => ['onPreBackup', 100],
            PostBackupEvent::class => ['onPostBackup', 100],
            BackupFailedEvent::class => ['onBackupFailed', 100],
        ];
    }

    public function onPreBackup(PreBackupEvent $event): void
    {
        $this->uploadStatus('started');
        $this->uploadStatus('version-'.$this->version);
    }

    public function onPostBackup(PostBackupEvent $event): void
    {
        $this->uploadStatus('completed');
    }

    public function onBackupFailed(BackupFailedEvent $event): void
    {
        $this->uploadStatus('failed');
    }

    private function uploadStatus(string $name): void
    {
        $directory = sprintf('%s/status/%s', $this->varDir, $this->hostname);
        $this->filesystem->mkdir($directory, 0700);

        $file = $directory.'/'.$name;
        $this->filesystem->touch($file);

        if (!$this->swift->uploadObject($file, sprintf('status/%s/%s', $this->hostname, $name))) {
            $this->logger->error(sprintf('Could not upload status object "%s".', $name));
        }
    }
}
