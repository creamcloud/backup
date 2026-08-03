<?php

namespace App\Command\Backup;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\QuestionHelper;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Question\ConfirmationQuestion;

#[AsCommand(
    name: 'backup:delete',
    description: 'Delete a snapshot (or all snapshots with --all) and reclaim its storage.',
)]
final class DeleteCommand extends Command
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->setHelp(
                'Deletes a snapshot and immediately reclaims its storage (unlike restic\'s'."\n"
                .'own "forget", which only marks it as forgotten until "prune" runs).'."\n"
                .'This cannot be undone. Use "backup:list" to find snapshot IDs.'
            )
            ->addArgument('snapshot-id', InputArgument::OPTIONAL, 'Snapshot ID to delete (see "backup:list")')
            ->addOption('all', null, InputOption::VALUE_NONE, 'Delete ALL snapshots in the repository')
            ->addOption('force', 'f', InputOption::VALUE_NONE, 'Do not ask for confirmation');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        $all = (bool) $input->getOption('all');
        $snapshotId = $input->getArgument('snapshot-id');

        if ($all && null !== $snapshotId) {
            $this->logger->error('Pass either a snapshot ID or --all, not both.');

            return Command::FAILURE;
        }

        if (!$all && null === $snapshotId) {
            $this->logger->error('Specify a snapshot ID to delete, or pass --all to delete every snapshot.');

            return Command::FAILURE;
        }

        if ($all) {
            $snapshots = $this->restic->snapshotsJson();
            if (null === $snapshots) {
                $this->logger->error('Could not list snapshots. Check logging and network connectivity.');

                return Command::FAILURE;
            }

            if ([] === $snapshots) {
                $this->logger->info('No snapshots to delete.');

                return Command::SUCCESS;
            }

            $ids = array_map(static fn (array $snapshot): string => $snapshot['short_id'] ?? $snapshot['id'], $snapshots);
            $confirmationMessage = sprintf('Delete ALL %d snapshot(s)? This cannot be undone. [y/N] ', \count($ids));
        } else {
            $ids = [$snapshotId];
            $confirmationMessage = sprintf('Delete snapshot "%s"? This cannot be undone. [y/N] ', $snapshotId);
        }

        if (!$input->getOption('force')) {
            $confirmed = (new QuestionHelper())->ask($input, $output, new ConfirmationQuestion($confirmationMessage, false));
            if (!$confirmed) {
                $this->logger->info('Aborted.');

                return Command::SUCCESS;
            }
        }

        return $this->restic->deleteSnapshots($ids)->success ? Command::SUCCESS : Command::FAILURE;
    }
}
