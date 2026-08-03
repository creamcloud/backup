<?php

namespace App\Event;

use Symfony\Contracts\EventDispatcher\Event;

/**
 * Dispatched after a successful "restic backup" + "restic forget".
 * Replaces the scripts that used to live in post-backup.d/.
 */
final class PostBackupEvent extends Event
{
}
