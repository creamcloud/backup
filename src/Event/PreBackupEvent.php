<?php

namespace App\Event;

use Symfony\Contracts\EventDispatcher\Event;

/**
 * Dispatched before "restic backup" runs. Replaces the scripts that used
 * to live in pre-backup.d/ (status upload, lock check, MySQL dump).
 */
final class PreBackupEvent extends Event
{
    public function __construct(
        private readonly \DateTimeImmutable $startedAt,
    ) {
    }

    public function getStartedAt(): \DateTimeImmutable
    {
        return $this->startedAt;
    }
}
