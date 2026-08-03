<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use App\Service\SwiftClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;

#[AsCommand(
    name: 'backup:stats',
    description: 'Show configuration, Swift storage usage and the snapshot list.',
)]
final class StatsCommand extends Command
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly SwiftClient $swift,
        private readonly ActivityLogger $logger,
        private readonly string $hostname,
        private readonly string $version,
        private readonly string $resticRepository,
        private readonly int $keepDaily,
        private readonly int $keepWeekly,
        private readonly string $swiftContainer,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        $this->logger->info('===== Cream Cloud Backup status =====');
        $this->logger->info('Hostname: '.$this->hostname);
        $this->logger->info('Version: '.$this->version);
        $this->logger->info('Restic repository: '.$this->resticRepository);
        $this->logger->info('Keep daily: '.$this->keepDaily);
        $this->logger->info('Keep weekly: '.$this->keepWeekly);

        if ($this->swift->isConfigured()) {
            $used = $this->swift->storageUsed();
            $this->logger->info(sprintf('Storage used (container "%s"): %s', $this->swiftContainer, $used ?? 'unknown'));
        }

        $this->logger->info('-----------------------------------------');
        $this->logger->info('Restic snapshots:');
        $result = $this->restic->snapshots();
        $this->logger->info('===== End of Cream Cloud Backup status =====');

        return $result->success ? Command::SUCCESS : Command::FAILURE;
    }
}
