<?php

namespace App\Exception;

/**
 * Thrown by a pre-backup subscriber to cleanly abort a "run" before any
 * restic command has been issued (e.g. another backup is still running).
 */
final class BackupAbortedException extends \RuntimeException
{
}
