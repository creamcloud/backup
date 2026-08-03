<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:list',
    description: 'List available snapshots, optionally restricted to those newer than a given time.',
)]
final class ListCommand extends Command
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this->addArgument('time', InputArgument::OPTIONAL, 'Only show snapshots newer than this restic --time value, e.g. "2d" or "2024-01-01"');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        return $this->restic->snapshots($input->getArgument('time'))->success ? Command::SUCCESS : Command::FAILURE;
    }
}
