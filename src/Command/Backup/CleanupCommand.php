<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:cleanup',
    description: 'Remove stale locks, repair the index and prune old data.',
)]
final class CleanupCommand extends Command
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

        $unlock = $this->restic->unlock(removeAll: true);

        // Pruning relies on the index being correct, so don't prune on top
        // of an index that could not be repaired.
        if (!$this->restic->repairIndex()->success) {
            return Command::FAILURE;
        }

        $prune = $this->restic->prune();

        return $unlock->success && $prune->success ? Command::SUCCESS : Command::FAILURE;
    }
}
