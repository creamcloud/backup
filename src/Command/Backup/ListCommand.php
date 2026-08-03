<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;

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
        $this->addArgument('time', InputArgument::OPTIONAL, 'Only show snapshots newer than this, e.g. "2d" (2 days ago) or "2024-01-01"');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        $time = $input->getArgument('time');
        $cutoff = null;
        if (null !== $time) {
            $cutoff = $this->parseCutoff($time);
            if (null === $cutoff) {
                $this->logger->error(sprintf('Invalid time value "%s". Use e.g. "2d" or "2024-01-01".', $time));

                return Command::FAILURE;
            }
        }

        $snapshots = $this->restic->snapshotsJson();
        if (null === $snapshots) {
            $this->logger->error('Could not list snapshots. Check logging and network connectivity.');

            return Command::FAILURE;
        }

        if (null !== $cutoff) {
            $snapshots = array_values(array_filter(
                $snapshots,
                static fn (array $snapshot): bool => new \DateTimeImmutable($snapshot['time']) >= $cutoff,
            ));
        }

        $io = new SymfonyStyle($input, $output);

        if ([] === $snapshots) {
            $io->note('No snapshots found.');

            return Command::SUCCESS;
        }

        $io->table(
            ['ID', 'Date', 'Hostname', 'Path'],
            array_map(static function (array $snapshot): array {
                return [
                    $snapshot['short_id'] ?? '?',
                    (new \DateTimeImmutable($snapshot['time']))->format('Y-m-d H:i:s'),
                    $snapshot['hostname'] ?? '?',
                    implode(', ', $snapshot['paths'] ?? []),
                ];
            }, $snapshots),
        );

        $io->comment(sprintf('%d snapshot(s). Use the ID with "backup:restore" to restore one.', \count($snapshots)));

        return Command::SUCCESS;
    }

    /**
     * Parses either a relative shorthand ("2d", "3w", "1m", "1y") or
     * anything DateTimeImmutable understands (e.g. "2024-01-01").
     */
    private function parseCutoff(string $time): ?\DateTimeImmutable
    {
        if (preg_match('/^(\d+)([hdwmy])$/', $time, $matches)) {
            $unit = ['h' => 'hours', 'd' => 'days', 'w' => 'weeks', 'm' => 'months', 'y' => 'years'][$matches[2]];

            return (new \DateTimeImmutable())->modify(sprintf('-%d %s', (int) $matches[1], $unit));
        }

        try {
            return new \DateTimeImmutable($time);
        } catch (\Exception) {
            return null;
        }
    }
}
