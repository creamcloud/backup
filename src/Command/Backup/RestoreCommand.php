<?php

namespace App\Command\Backup;

use App\Restore\RestoreWizard;
use App\Service\ActivityLogger;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:restore',
    description: 'Interactively restore a file, folder or MySQL database.',
)]
final class RestoreCommand extends Command
{
    public function __construct(
        private readonly RestoreWizard $restoreWizard,
        private readonly ActivityLogger $logger,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        return $this->restoreWizard->run($input, $output);
    }
}
