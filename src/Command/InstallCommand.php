<?php

namespace App\Command;

use App\Service\ActivityLogger;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Helper\QuestionHelper;
use Symfony\Component\Console\Input\ArrayInput;
use Symfony\Component\Console\Input\InputArgument;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Question\Question;
use Symfony\Component\Filesystem\Filesystem;

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
                'Safe to re-run: an existing local config, restic password or cron job is left alone.'."\n\n"
                .'For unattended installs, pass all six arguments:'."\n\n"
                .'  creamcloud-backup install \'user@example.org\' \'P@ssw0rd\' \'project-id\' \'NL\' \'transip\' \'transip\''
            )
            ->addArgument('username', InputArgument::OPTIONAL, 'OpenStack Object Store username')
            ->addArgument('password', InputArgument::OPTIONAL, 'OpenStack Object Store password')
            ->addArgument('project-id', InputArgument::OPTIONAL, 'OpenStack project ID')
            ->addArgument('region', InputArgument::OPTIONAL, 'OpenStack region')
            ->addArgument('user-domain-name', InputArgument::OPTIONAL, 'OpenStack user domain name')
            ->addArgument('project-domain-name', InputArgument::OPTIONAL, 'OpenStack project domain name');
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $this->logger->setOutput($output);

        if (\function_exists('posix_getuid') && 0 !== posix_getuid()) {
            $this->logger->error('This command must be run as root.');

            return Command::FAILURE;
        }

        $filesystem = new Filesystem();

        if ($filesystem->exists($this->localConfigFile)) {
            $this->logger->info(sprintf('"%s" already exists, not overwriting it.', $this->localConfigFile));
        } elseif (!$this->writeLocalConfig($input, $output, $filesystem)) {
            return Command::FAILURE;
        }

        $this->ensureResticPassword($filesystem);
        $this->linkBinary($filesystem);

        $application = $this->getApplication();
        if (null === $application) {
            $this->logger->error('Could not run "backup:init": no console application available.');

            return Command::FAILURE;
        }

        $initCommand = $application->find('backup:init');
        if (Command::SUCCESS !== $initCommand->run(new ArrayInput([]), $output)) {
            return Command::FAILURE;
        }

        $this->installCronJob($filesystem);

        $this->logger->info('Cream Cloud Backup installation completed.');
        $this->logger->info('Run "creamcloud-backup backup:stats" to check the configuration and connectivity.');
        $this->logger->info('Run "creamcloud-backup backup:run" to perform a backup manually.');
        $this->logger->info('To receive email notifications on backup failures, set MAILER_DSN and');
        $this->logger->info(sprintf('NOTIFICATION_EMAILS in %s. See README.md for details.', $this->localConfigFile));

        return Command::SUCCESS;
    }

    private function writeLocalConfig(InputInterface $input, OutputInterface $output, Filesystem $filesystem): bool
    {
        $username = $input->getArgument('username');
        $password = $input->getArgument('password');
        $projectId = $input->getArgument('project-id');
        $region = $input->getArgument('region');
        $userDomainName = $input->getArgument('user-domain-name');
        $projectDomainName = $input->getArgument('project-domain-name');

        $unattended = null !== $username && null !== $password && null !== $projectId
            && null !== $region && null !== $userDomainName && null !== $projectDomainName;

        if (!$unattended) {
            $helper = new QuestionHelper();

            $username = $helper->ask($input, $output, new Question('OpenStack Object Store username (user@example.org): '));
            $passwordQuestion = new Question('OpenStack Object Store password (not shown): ');
            $passwordQuestion->setHidden(true);
            $password = $helper->ask($input, $output, $passwordQuestion);
            $projectId = $helper->ask($input, $output, new Question('OpenStack project ID: '));
            $userDomainName = $helper->ask($input, $output, new Question('OpenStack user domain name [transip]: ', 'transip'));
            $projectDomainName = $helper->ask($input, $output, new Question('OpenStack project domain name [transip]: ', 'transip'));
            $region = $helper->ask($input, $output, new Question('OpenStack region [NL]: ', 'NL'));
        }

        if (empty($username) || empty($password) || empty($projectId) || empty($region) || empty($userDomainName) || empty($projectDomainName)) {
            $this->logger->error('Need a username, password, project ID, region and domain names.');

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
            OS_USERNAME=%s
            OS_PASSWORD=%s
            OS_PROJECT_NAME=%s
            OS_USER_DOMAIN_NAME=%s
            OS_PROJECT_DOMAIN_NAME=%s
            OS_REGION_NAME=%s
            OS_AUTH_URL=%s

            CONF,
            (new \DateTimeImmutable())->format(DATE_ATOM),
            $this->quote($this->detectHostname()),
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

    private function detectHostname(): string
    {
        $context = stream_context_create(['http' => ['timeout' => 3, 'ignore_errors' => true]]);
        $metadata = @file_get_contents('http://169.254.169.254/openstack/latest/meta_data.json', false, $context);

        if (false !== $metadata) {
            $data = json_decode($metadata, true);
            if (\is_array($data) && !empty($data['uuid']) && \is_string($data['uuid'])) {
                return $data['uuid'];
            }
        }

        if (is_file('/var/firstboot/settings')) {
            foreach (file('/var/firstboot/settings') ?: [] as $line) {
                if (str_starts_with($line, 'hostname=')) {
                    return trim(substr($line, \strlen('hostname=')));
                }
            }
        }

        return gethostname() ?: php_uname('n');
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

    private function ensureResticPassword(Filesystem $filesystem): void
    {
        if ($filesystem->exists($this->resticPasswordFile)) {
            return;
        }

        $filesystem->mkdir(\dirname($this->resticPasswordFile), 0700);

        $this->logger->info(sprintf('Generating a restic repository password in %s.', $this->resticPasswordFile));
        $filesystem->dumpFile($this->resticPasswordFile, base64_encode(random_bytes(48))."\n");
        $filesystem->chmod($this->resticPasswordFile, 0600);
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

    private function installCronJob(Filesystem $filesystem): void
    {
        if ($filesystem->exists($this->cronFile)) {
            return;
        }

        $minute = random_int(0, 59);
        $hour = random_int(0, 6);

        $contents = sprintf(
            <<<CRON
            # Cream Cloud Backup
            MAILTO="root"

            # Daily backup at a randomized time between 00:00 and 06:59.
            %d %d * * * root %s backup:run

            # Daily cleanup: remove stale locks and prune old snapshots.
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
