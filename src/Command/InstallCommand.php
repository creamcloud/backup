<?php

namespace App\Command;

use App\Service\ActivityLogger;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\QuestionHelper;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Question\Question;
use Symfony\Component\Filesystem\Filesystem;
use Symfony\Component\Process\Process;

/**
 * Configures this server, replacing everything install.sh used to do past
 * "composer install" (which cannot move here, since it is what makes this
 * command available in the first place).
 */
#[AsCommand(
    name: 'install',
    description: 'Configure this server: OpenStack credentials, restic password, "creamcloud-backup" command and cron job.',
)]
final class InstallCommand extends Command
{
    private const AUTH_URL = 'https://auth.teamblue.cloud/v3';

    public function __construct(
        private readonly ActivityLogger $logger,
        private readonly string $projectDir,
        private readonly string $resticPasswordFile,
        private readonly string $localConfigFile,
        private readonly string $binLink,
        private readonly string $cronFile,
    ) {
        parent::__construct();
    }

    protected function configure(): void
    {
        $this
            ->setHelp(
                'Safe to re-run: an existing local config, restic password or cron job is left alone.'."\n"
                .'Pass --reinstall to overwrite the local config (OpenStack credentials,'."\n"
                .'hostname, ...) and the cron job instead - the restic password is never'."\n"
                .'overwritten, even with --reinstall, since that would lock you out of your'."\n"
                .'existing backups.'."\n\n"
                .'For unattended installs, pass all six OpenStack options:'."\n\n"
                .'  creamcloud-backup install --username=\'user@example.org\' --password=\'P@ssw0rd\' \\'."\n"
                .'    --project-id=\'project-id\' --region=\'NL\' --user-domain-name=\'transip\' \\'."\n"
                .'    --project-domain-name=\'transip\''."\n\n"
                .'The hostname and restic repository password are asked for interactively'."\n"
                .'(leave the password empty to generate one); pass --hostname / --restic-password'."\n"
                .'to set them non-interactively, e.g. for unattended installs or when run with'."\n"
                .'--no-interaction.'
            )
            ->addOption('username', null, InputOption::VALUE_REQUIRED, 'OpenStack Object Store username')
            ->addOption('password', null, InputOption::VALUE_REQUIRED, 'OpenStack Object Store password')
            ->addOption('project-id', null, InputOption::VALUE_REQUIRED, 'OpenStack project ID')
            ->addOption('region', null, InputOption::VALUE_REQUIRED, 'OpenStack region')
            ->addOption('user-domain-name', null, InputOption::VALUE_REQUIRED, 'OpenStack user domain name')
            ->addOption('project-domain-name', null, InputOption::VALUE_REQUIRED, 'OpenStack project domain name')
            ->addOption('hostname', null, InputOption::VALUE_REQUIRED, 'Hostname for this server (used as the restic/Swift container identity)')
            ->addOption('restic-password', null, InputOption::VALUE_REQUIRED, 'Restic repository password (generated automatically if not given)')
            ->addOption('reinstall', null, InputOption::VALUE_NONE, 'Overwrite the local config file and cron job if they already exist');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        if (\function_exists('posix_getuid') && 0 !== posix_getuid()) {
            $this->logger->error('This command must be run as root.');

            return Command::FAILURE;
        }

        $filesystem = new Filesystem();

        $configExists = $filesystem->exists($this->localConfigFile);
        if ($configExists && !$input->getOption('reinstall')) {
            $this->logger->info(sprintf('"%s" already exists, not overwriting it. Pass --reinstall to overwrite it.', $this->localConfigFile));
        } else {
            if ($configExists) {
                $this->logger->info(sprintf('--reinstall given, overwriting "%s".', $this->localConfigFile));
            }
            if (!$this->writeLocalConfig($input, $output, $filesystem)) {
                return Command::FAILURE;
            }
        }

        $this->ensureResticPassword($input, $output, $filesystem);
        $this->linkBinary($filesystem);

        // Run as a fresh process rather than in-process (Application::find()
        // ->run()): the config just written above is only picked up by a new
        // process re-reading it at boot, since this process's container was
        // already built (with the old/default values) before we wrote it.
        if (!$this->runBackupInit($output)) {
            return Command::FAILURE;
        }

        $this->installCronJob($filesystem, (bool) $input->getOption('reinstall'));

        $this->logger->info('Cream Cloud Backup installation completed.');
        $this->logger->info('Run "creamcloud-backup backup:stats" to check the configuration and connectivity.');
        $this->logger->info('Run "creamcloud-backup backup:run" to perform a backup manually.');
        $this->logger->info('To receive email notifications on backup failures, set MAILER_DSN and');
        $this->logger->info(sprintf('NOTIFICATION_EMAILS in %s. See README.md for details.', $this->localConfigFile));

        return Command::SUCCESS;
    }

    private function writeLocalConfig(InputInterface $input, OutputInterface $output, Filesystem $filesystem): bool
    {
        $username = $input->getOption('username');
        $password = $input->getOption('password');
        $projectId = $input->getOption('project-id');
        $region = $input->getOption('region');
        $userDomainName = $input->getOption('user-domain-name');
        $projectDomainName = $input->getOption('project-domain-name');

        $unattended = null !== $username && null !== $password && null !== $projectId
            && null !== $region && null !== $userDomainName && null !== $projectDomainName;

        if (!$unattended) {
            $helper = new QuestionHelper();

            $username = $helper->ask($input, $output, new Question('OpenStack Object Store username (user@example.org): '));
            $passwordQuestion = new Question('OpenStack Object Store password: ');
            $passwordQuestion->setHidden(true);
            $password = $helper->ask($input, $output, $passwordQuestion);
            $projectId = $helper->ask($input, $output, new Question('OpenStack Project ID: '));
            $userDomainName = $helper->ask($input, $output, new Question('OpenStack user domain name [transip]: ', 'transip'));
            $projectDomainName = $helper->ask($input, $output, new Question('OpenStack project domain name [transip]: ', 'transip'));
            $region = $helper->ask($input, $output, new Question('OpenStack region [NL]: ', 'NL'));
        }

        if (empty($username) || empty($password) || empty($projectId) || empty($region) || empty($userDomainName) || empty($projectDomainName)) {
            $this->logger->error('Need a username, password, project ID, region and domain names.');

            return false;
        }

        $hostname = $this->askHostname($input, $output);
        if (empty($hostname)) {
            $this->logger->error('Need a hostname.');

            return false;
        }

        $this->logger->info(sprintf('Looking up the OpenStack project name for project ID %s.', $projectId));
        $projectName = $this->lookupProjectName($username, $password, $userDomainName, $projectId);

        if (null === $projectName) {
            $this->logger->error('Authentication with the OpenStack Object Store failed.');
            $this->logger->error('Check the username, password, project ID and network connectivity.');

            return false;
        }

        $this->logger->info(sprintf('Authenticated as project "%s".', $projectName));


        $contents = sprintf(
            <<<CONF
            # Per-server configuration, generated by "creamcloud-backup install" on %s.
            # Lives outside the project folder, see LOCAL_CONFIG_FILE in etc/backup.conf.
            # Any variable from that file may be overridden here.
            HOSTNAME=%s
            # Isolates this server's backups in their own Swift container,
            # named after its hostname, instead of sharing one container.
            SWIFT_CONTAINER=%s
            RESTIC_REPOSITORY=%s
            OS_USERNAME=%s
            OS_PASSWORD=%s
            OS_PROJECT_NAME=%s
            OS_USER_DOMAIN_NAME=%s
            OS_PROJECT_DOMAIN_NAME=%s
            OS_REGION_NAME=%s
            OS_AUTH_URL=%s

            CONF,
            (new \DateTimeImmutable())->format(DATE_ATOM),
            $this->quote($hostname),
            $this->quote($hostname),
            $this->quote('swift:'.$hostname.':/'),
            $this->quote($username),
            $this->quote($password),
            $this->quote($projectName),
            $this->quote($userDomainName),
            $this->quote($projectDomainName),
            $this->quote($region),
            $this->quote(self::AUTH_URL),
        );

        $filesystem->mkdir(\dirname($this->localConfigFile), 0700);
        $filesystem->dumpFile($this->localConfigFile, $contents);
        $filesystem->chmod($this->localConfigFile, 0600);

        $this->logger->info(sprintf('Written server configuration to %s.', $this->localConfigFile));

        return true;
    }

    /**
     * Single-quotes a value for use in a Dotenv file, escaping any embedded
     * single quote the same way a shell would ('it'\''s' -> "it's").
     */
    private function quote(string $value): string
    {
        return "'".str_replace("'", "'\\''", $value)."'";
    }

    private function askHostname(InputInterface $input, OutputInterface $output): string
    {
        $hostname = $input->getOption('hostname');
        if (!empty($hostname)) {
            return $hostname;
        }

        $default = gethostname() ?: php_uname('n');

        if (!$input->isInteractive()) {
            return $default;
        }

        return (new QuestionHelper())->ask($input, $output, new Question(
            sprintf('Hostname for this server (used as the restic/Swift container identity) [%s]: ', $default),
            $default,
        ));
    }

    private function lookupProjectName(string $username, string $password, string $userDomainName, string $projectId): ?string
    {
        $payload = json_encode([
            'auth' => [
                'identity' => [
                    'methods' => ['password'],
                    'password' => [
                        'user' => [
                            'name' => $username,
                            'domain' => ['name' => $userDomainName],
                            'password' => $password,
                        ],
                    ],
                ],
                'scope' => ['project' => ['id' => $projectId]],
            ],
        ]);

        $ch = curl_init(self::AUTH_URL.'/auth/tokens');
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $payload,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Accept: application/json'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 10,
        ]);
        $response = curl_exec($ch);
        curl_close($ch);



        if (false === $response || !\is_string($response)) {
            return null;
        }

        $data = json_decode($response, true);
        $name = $data['token']['project']['name'] ?? null;

        return \is_string($name) ? $name : null;
    }

    private function ensureResticPassword(InputInterface $input, OutputInterface $output, Filesystem $filesystem): void
    {
        if ($filesystem->exists($this->resticPasswordFile)) {
            return;
        }

        $password = $input->getOption('restic-password');

        if (empty($password) && $input->isInteractive()) {
            $question = new Question('Restic repository password (leave empty to generate one, not shown): ');
            $question->setHidden(true);
            $password = (new QuestionHelper())->ask($input, $output, $question);
        }

        if (empty($password)) {
            $password = base64_encode(random_bytes(48));
            $this->logger->info(sprintf('Generating a restic repository password in %s.', $this->resticPasswordFile));
        } else {
            $this->logger->info(sprintf('Using the provided restic repository password, storing it in %s.', $this->resticPasswordFile));
        }

        $filesystem->mkdir(\dirname($this->resticPasswordFile), 0700);
        $filesystem->dumpFile($this->resticPasswordFile, $password."\n");
        $filesystem->chmod($this->resticPasswordFile, 0600);
    }

    private function runBackupInit(OutputInterface $output): bool
    {
        $process = new Process([$this->projectDir.'/bin/creamcloud-backup', 'backup:init']);
        $process->setTimeout(null);
        $process->run(function (string $type, string $buffer) use ($output): void {
            $output->write($buffer);
        });

        if (!$process->isSuccessful()) {
            $this->logger->error('"backup:init" failed.');

            return false;
        }

        return true;
    }

    private function linkBinary(Filesystem $filesystem): void
    {
        $console = $this->projectDir.'/bin/creamcloud-backup';
        $filesystem->chmod($console, 0755);

        if (is_link($this->binLink) || $filesystem->exists($this->binLink)) {
            $filesystem->remove($this->binLink);
        }

        $filesystem->symlink($console, $this->binLink);
    }

    private function installCronJob(Filesystem $filesystem, bool $reinstall): void
    {
        $cronExists = $filesystem->exists($this->cronFile);
        if ($cronExists && !$reinstall) {
            return;
        }

        if ($cronExists) {
            $this->logger->info(sprintf('--reinstall given, overwriting "%s".', $this->cronFile));
        }

        $minute = random_int(0, 59);
        $hour = random_int(0, 6);

        $contents = sprintf(
            <<<CRON
            # Cream Cloud Backup
            MAILTO="root"

            # Daily backup at a randomized time between 00:00 and 06:59.
            %d %d * * * root %s backup:run

            # Daily cleanup: remove stale locks, repair the index and prune old snapshots.
            0 0 * * * root %s backup:cleanup

            # Self-update on the first day of the month.
            0 1 1 * * root %s self-update

            CRON,
            $minute,
            $hour,
            $this->binLink,
            $this->binLink,
            $this->binLink,
        );

        $filesystem->mkdir(\dirname($this->cronFile));
        $filesystem->dumpFile($this->cronFile, $contents);

        $this->logger->info(sprintf('Installed cron job in %s, daily backup will run at %02d:%02d.', $this->cronFile, $hour, $minute));
    }
}
