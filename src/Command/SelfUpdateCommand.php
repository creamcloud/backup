<?php

namespace App\Command;

use App\Service\ActivityLogger;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Process\Process;

#[AsCommand(
    name: 'self-update',
    description: 'Update Cream Cloud Backup and Restic to the latest version.',
)]
final class SelfUpdateCommand extends Command
{
    public function __construct(
        private readonly ActivityLogger $logger,
        private readonly string $projectDir,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        if (!(new Filesystem())->exists($this->projectDir.'/.git')) {
            $this->logger->error(sprintf('"%s" is not a git checkout, cannot update automatically.', $this->projectDir));

            return Command::FAILURE;
        }

        $this->logger->info('Updating Cream Cloud Backup in '.$this->projectDir);

        if (!$this->runLoggedProcess(['git', 'pull', '--ff-only'])) {
            return Command::FAILURE;
        }

        if (!$this->runLoggedProcess(['composer', 'install', '--no-dev', '--optimize-autoloader'])) {
            return Command::FAILURE;
        }

        // Not fatal: distro-packaged restic builds (e.g. Debian/Ubuntu) have
        // "self-update" disabled and must be updated via the package manager.
        $this->logger->info('Updating restic.');
        if (!$this->runLoggedProcess(['restic', 'self-update'])) {
            $this->logger->info('Could not update restic, it may have been installed by the system package manager. Update it from there instead.');
        }

        $this->logger->info('Update finished.');

        return Command::SUCCESS;
    }

    /**
     * @param string[] $command
     */
    private function runLoggedProcess(array $command): bool
    {
        $process = new Process($command, $this->projectDir);
        $process->setTimeout(300);
        $process->run(function (string $type, string $buffer): void {
            foreach (explode("\n", trim($buffer)) as $line) {
                if ('' !== $line) {
                    $this->logger->info($line);
                }
            }
        });

        if (!$process->isSuccessful()) {
            $this->logger->error(sprintf('"%s" failed.', implode(' ', $command)));

            return false;
        }

        return true;
    }
}
