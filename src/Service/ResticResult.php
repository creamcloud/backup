<?php

namespace App\Service;

/**
 * Outcome of a restic invocation: whether it succeeded and the
 * (already filtered) output lines that were logged.
 */
final class ResticResult
{
    /**
     * @param string[] $lines
     */
    public function __construct(
        public readonly bool $success,
        public readonly array $lines,
    ) {
    }
}
