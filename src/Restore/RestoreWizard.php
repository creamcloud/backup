<?php

namespace App\Restore;

use App\Service\ActivityLogger;
use App\Service\ResticClient;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\QuestionHelper;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Question\ChoiceQuestion;
use Symfony\Component\Console\Question\ConfirmationQuestion;
use Symfony\Component\Console\Question\Question;
use Symfony\Component\Console\Style\SymfonyStyle;
use Symfony\Component\Filesystem\Exception\IOExceptionInterface;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Process\Process;

/**
 * Interactive restore wizard, replacing the dialog(1)-based
 * creamcloud-backup-restore.sh script.
 */
final class RestoreWizard
{
    public function __construct(
        private readonly ResticClient $restic,
        private readonly ActivityLogger $logger,
        private readonly string $hostname,
        private readonly string $restoreDir,
        private readonly string $sqlBackupDir,
    ) {
    }

    public function run(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);
        $helper = new QuestionHelper();

        $io->title('Cream Cloud Backup Restore');
        $io->text([
            'This restores either a file/folder or a MySQL database from a Restic snapshot.',
            'You will be asked for the restore type, a path or database name, and a snapshot ID.',
            'Use "creamcloud-backup backup:list" to see the available snapshot IDs.',
        ]);

        $hostname = $helper->ask($input, $output, new Question(
            sprintf('Hostname the backup was made on [%s]: ', $this->hostname),
            $this->hostname,
        ));

        $type = $helper->ask($input, $output, new ChoiceQuestion(
            'What do you want to restore?',
            ['File or folder', 'MySQL database'],
            'File or folder',
        ));

        return 'MySQL database' === $type
            ? $this->restoreMysql($io, $helper, $input, $output, $hostname)
            : $this->restoreFile($io, $helper, $input, $output, $hostname);
    }

    private function restoreFile(SymfonyStyle $io, QuestionHelper $helper, InputInterface $input, OutputInterface $output, string $hostname): int
    {
        $pathQuestion = new Question('Full path to the file or folder to restore (e.g. /home/user/test/): ');
        $pathQuestion->setValidator(function (?string $value): string {
            if (null === $value || !str_starts_with($value, '/')) {
                throw new \RuntimeException('Please enter an absolute path, starting with "/".');
            }

            return $value;
        });
        $path = $helper->ask($input, $output, $pathQuestion);

        $restoreDir = rtrim($this->restoreDir, '/').'/'.date('Ymd-His').'/';
        $destination = $helper->ask($input, $output, new ChoiceQuestion(
            sprintf('Restore to the original location (overwrites existing files) or to %s?', $restoreDir),
            ['original' => 'Original location ('.$path.')', 'restore-dir' => $restoreDir],
            'original',
        ));
        $target = 'original' === $destination ? '/' : $restoreDir;

        $snapshotId = $this->askSnapshotId($helper, $input, $output);

        $io->section('About to restore');
        $io->definitionList(
            ['Hostname' => $hostname],
            ['Snapshot' => $snapshotId],
            ['Path' => $path],
            ['Target' => $target],
        );

        if (!$helper->ask($input, $output, new ConfirmationQuestion('Continue? [y/N] ', false))) {
            $io->writeln('Aborted.');

            return Command::SUCCESS;
        }

        $this->logger->info(sprintf(
            'Restoring "%s" from snapshot %s for host %s to %s.',
            $path, $snapshotId, $hostname, $target,
        ));

        if ('restore-dir' === $destination) {
            try {
                (new Filesystem())->mkdir($target, 0700);
            } catch (IOExceptionInterface $exception) {
                $this->logger->error('Could not create restore directory: '.$exception->getMessage());

                return Command::FAILURE;
            }
        }

        $result = $this->restic->restore($snapshotId, $path, $target);
        if (!$result->success) {
            $this->logger->error('Restore FAILED. Please check logging, the path name and network connectivity.');

            return Command::FAILURE;
        }

        $this->logger->info('Restore successful.');

        return Command::SUCCESS;
    }

    private function restoreMysql(SymfonyStyle $io, QuestionHelper $helper, InputInterface $input, OutputInterface $output, string $hostname): int
    {
        $databaseQuestion = new Question('MySQL database name: ');
        $databaseQuestion->setValidator(function (?string $value): string {
            if (null === $value || !preg_match('/^[A-Za-z0-9_]+$/', $value)) {
                throw new \RuntimeException('Database name may only contain letters, digits and underscores.');
            }

            return $value;
        });
        $database = $helper->ask($input, $output, $databaseQuestion);

        $snapshotId = $this->askSnapshotId($helper, $input, $output);
        $targetDatabase = $database.'_backup';

        $io->section('About to restore');
        $io->definitionList(
            ['Hostname' => $hostname],
            ['Snapshot' => $snapshotId],
            ['Database' => $database],
            ['Restored into' => $targetDatabase],
        );
        $io->note(sprintf('If "%s" already exists its contents will be overwritten.', $targetDatabase));

        if (!$helper->ask($input, $output, new ConfirmationQuestion('Continue? [y/N] ', false))) {
            $io->writeln('Aborted.');

            return Command::SUCCESS;
        }

        $this->logger->info(sprintf(
            'Restoring MySQL database %s from snapshot %s for host %s into %s.',
            $database, $snapshotId, $hostname, $targetDatabase,
        ));

        $create = new Process(['mysql', '-e', sprintf('CREATE DATABASE IF NOT EXISTS `%s`;', $targetDatabase)]);
        $create->run();
        if (!$create->isSuccessful()) {
            $this->logger->error('Could not create database '.$targetDatabase.': '.trim($create->getErrorOutput()));

            return Command::FAILURE;
        }

        $dumpFile = tempnam(sys_get_temp_dir(), 'creamcloud-restore-');
        $remotePath = sprintf('%s/%s.sql.gz', $this->sqlBackupDir, $database);

        if (!$this->restic->dumpToFile($snapshotId, $remotePath, $dumpFile)) {
            $this->logger->error('Could not read the database dump from the backup repository.');
            @unlink($dumpFile);

            return Command::FAILURE;
        }

        $import = Process::fromShellCommandline(sprintf(
            'gunzip -c %s | mysql %s',
            escapeshellarg($dumpFile),
            escapeshellarg($targetDatabase),
        ));
        $import->setTimeout(null);
        $import->run();
        unlink($dumpFile);

        if (!$import->isSuccessful()) {
            $this->logger->error('Database import unsuccessful: '.trim($import->getErrorOutput()));

            return Command::FAILURE;
        }

        $this->logger->info('MySQL restore successful.');

        return Command::SUCCESS;
    }

    private function askSnapshotId(QuestionHelper $helper, InputInterface $input, OutputInterface $output): string
    {
        $question = new Question('Snapshot ID to restore from (see "creamcloud-backup backup:list"): ');
        $question->setValidator(function (?string $value): string {
            if (null === $value || !preg_match('/^[0-9a-f]{8,64}$/', $value)) {
                throw new \RuntimeException('Please enter a valid restic snapshot ID (hexadecimal, as shown by "creamcloud-backup backup:list").');
            }

            return $value;
        });

        return $helper->ask($input, $output, $question);
    }
}
