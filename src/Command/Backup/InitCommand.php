<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:init',
    description: 'Initialize the restic repository, if it has not been already.',
)]
final class InitCommand extends Command
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        if ($this->restic->isInitialized()) {
            $this->logger->info('Repository is already initialized.');

            return Command::SUCCESS;
        }

        return $this->restic->ensureInitialized() ? Command::SUCCESS : Command::FAILURE;
    }
}
