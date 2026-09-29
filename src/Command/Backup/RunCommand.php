<?php

namespace App\Command\Backup;

use App\Event\BackupFailedEvent;
use App\Event\PostBackupEvent;
use App\Event\PreBackupEvent;
use App\Exception\BackupAbortedException;
use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\EventDispatcher\EventDispatcherInterface;

#[AsCommand(
    name: 'backup:run',
    description: 'Create a new backup.',
)]
final class RunCommand extends Command
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
        private readonly EventDispatcherInterface $dispatcher,
        private readonly string $backupPath,
        private readonly string $excludeFile,
        private readonly int $keepDaily,
        private readonly int $keepWeekly,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        if (!$this->restic->ensureInitialized()) {
            $this->logger->error('Could not initialize the restic repository.');

            return Command::FAILURE;
        }

        try {
            $this->dispatcher->dispatch(new PreBackupEvent(new \DateTimeImmutable()));
        } catch (BackupAbortedException $exception) {
            $this->logger->info($exception->getMessage());

            return Command::SUCCESS;
        }

        $backupResult = $this->restic->backup($this->backupPath, $this->excludeFile);
        if (!$backupResult->success) {
            $this->dispatcher->dispatch(new BackupFailedEvent('backup', $backupResult->lines));

            return Command::FAILURE;
        }

        $forgetResult = $this->restic->forget($this->keepDaily, $this->keepWeekly);
        if (!$forgetResult->success) {
            $this->dispatcher->dispatch(new BackupFailedEvent('forget', $forgetResult->lines));

            return Command::FAILURE;
        }

        $this->dispatcher->dispatch(new PostBackupEvent());

        return Command::SUCCESS;
    }
}
