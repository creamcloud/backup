<?php

namespace App\Event;

use Symfony\Contracts\EventDispatcher\Event;

/**
 * Dispatched when "restic backup" itself fails. Replaces the scripts
 * that used to live in post-fail-backup.d/.
 */
final class BackupFailedEvent extends Event
{
    /**
     * @param string[] $errorLines
     */
    public function __construct(
        private readonly string $stage,
        private readonly array $errorLines,
    ) {
    }

    public function getStage(): string
    {
        return $this->stage;
    }

    /**
     * @return string[]
     */
    public function getErrorLines(): array
    {
        return $this->errorLines;
    }
}
