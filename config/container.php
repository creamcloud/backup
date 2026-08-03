<?php

use Symfony\Component\Config\FileLocator;
use Symfony\Component\DependencyInjection\ContainerBuilder;
use Symfony\Component\DependencyInjection\Loader\YamlFileLoader;
use Symfony\Component\EventDispatcher\DependencyInjection\RegisterListenersPass;

require __DIR__.'/bootstrap.php';

$projectDir = dirname(__DIR__);

$containerBuilder = new ContainerBuilder();
$containerBuilder->setParameter('kernel.project_dir', $projectDir);

// Environment-derived parameters. Set directly from $_ENV (populated by
// Dotenv in bootstrap.php) rather than via "%env(...)%" processors, since
// those are only resolved by a dumped/compiled container and this
// ContainerBuilder is used as-is.
$containerBuilder->setParameter('app.hostname', $_ENV['HOSTNAME'] ?? '');
$containerBuilder->setParameter('app.keep_daily', (int) ($_ENV['KEEP_DAILY'] ?? 7));
$containerBuilder->setParameter('app.keep_weekly', (int) ($_ENV['KEEP_WEEKLY'] ?? 2));
$containerBuilder->setParameter('app.tempdir', $_ENV['TEMPDIR'] ?? sys_get_temp_dir());
$containerBuilder->setParameter('app.backup_path', $_ENV['BACKUP_PATH'] ?? '/');

$containerBuilder->setParameter('app.restic_repository', $_ENV['RESTIC_REPOSITORY'] ?? '');
$containerBuilder->setParameter('app.restic_password_file', $_ENV['RESTIC_PASSWORD_FILE'] ?? '');
$containerBuilder->setParameter('app.local_config_file', $_ENV['LOCAL_CONFIG_FILE'] ?? '');

$excludeFile = $_ENV['EXCLUDE_FILE'] ?? '';
$containerBuilder->setParameter('app.exclude_file', '' !== $excludeFile ? $excludeFile : $projectDir.'/etc/exclude.conf');

$containerBuilder->setParameter('app.swift_container', $_ENV['SWIFT_CONTAINER'] ?? '');

$containerBuilder->setParameter('app.os_username', $_ENV['OS_USERNAME'] ?? '');
$containerBuilder->setParameter('app.os_password', $_ENV['OS_PASSWORD'] ?? '');
$containerBuilder->setParameter('app.os_project_name', $_ENV['OS_PROJECT_NAME'] ?? '');
$containerBuilder->setParameter('app.os_user_domain_name', $_ENV['OS_USER_DOMAIN_NAME'] ?? '');
$containerBuilder->setParameter('app.os_project_domain_name', $_ENV['OS_PROJECT_DOMAIN_NAME'] ?? '');
$containerBuilder->setParameter('app.os_region_name', $_ENV['OS_REGION_NAME'] ?? '');
$containerBuilder->setParameter('app.os_auth_url', $_ENV['OS_AUTH_URL'] ?? '');
$containerBuilder->setParameter('app.os_identity_api_version', $_ENV['OS_IDENTITY_API_VERSION'] ?? '');

$containerBuilder->setParameter('app.mailer_dsn', $_ENV['MAILER_DSN'] ?? 'null://null');
$containerBuilder->setParameter('app.mail_from', $_ENV['MAIL_FROM'] ?? '');
$containerBuilder->setParameter('app.notification_emails', array_values(array_filter(array_map(
    'trim',
    explode(',', $_ENV['NOTIFICATION_EMAILS'] ?? ''),
))));

$loader = new YamlFileLoader($containerBuilder, new FileLocator($projectDir.'/config'));
foreach (glob($projectDir.'/config/packages/*.yaml') as $file) {
    $loader->load('packages/'.basename($file));
}
$loader->load('services.yaml');

$containerBuilder->addCompilerPass(new RegisterListenersPass());
$containerBuilder->compile();

return $containerBuilder;
