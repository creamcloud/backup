<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:verify',
    description: 'Check the integrity of the repository ("restic check").',
)]
final class VerifyCommand extends Command
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

        return $this->restic->check()->success ? Command::SUCCESS : Command::FAILURE;
    }
}
