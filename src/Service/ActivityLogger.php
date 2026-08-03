<?php

namespace App\Service;

use Symfony\Component\Console\Output\ConsoleOutput;
use Symfony\Component\Console\Output\OutputInterface;

/**
 * Replacement for the lecho/lerror/log helpers from common.sh: every
 * message is recorded to syslog under the "creamcloud-backup" tag, and
 * info/error messages are also written to the console.
 */
final class ActivityLogger
{
    private OutputInterface $output;
    private bool $syslogOpen = false;

    public function __construct()
    {
        $this->output = new ConsoleOutput();
    }

    public function setOutput(OutputInterface $output): void
    {
        $this->output = $output;
    }

    /**
     * Logs and prints an informational message, prefixed with "# " (lecho).
     */
    public function info(string $message): void
    {
        $this->syslog(LOG_INFO, $message);
        $this->output->writeln('# '.$message);
    }

    /**
     * Logs and prints an error message to stderr (lerror).
     */
    public function error(string $message): void
    {
        $this->syslog(LOG_ERR, 'ERROR - '.$message);
        $this->errorOutput()->writeln('<error>'.$message.'</error>');
    }

    /**
     * Logs to syslog only, without console output (log).
     */
    public function debug(string $message): void
    {
        $this->syslog(LOG_DEBUG, $message);
    }

    private function errorOutput(): OutputInterface
    {
        return $this->output instanceof ConsoleOutput ? $this->output->getErrorOutput() : $this->output;
    }

    private function syslog(int $priority, string $message): void
    {
        if (!$this->syslogOpen) {
            openlog('creamcloud-backup', LOG_PID, LOG_USER);
            $this->syslogOpen = true;
        }

        syslog($priority, $message);
    }

    public function __destruct()
    {
        if ($this->syslogOpen) {
            closelog();
        }
    }
}
