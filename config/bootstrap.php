<?php

use Symfony\Component\Dotenv\Dotenv;

require dirname(__DIR__).'/vendor/autoload.php';

if (class_exists(Dotenv::class)) {
    $dotenv = new Dotenv();
    $dotenv->usePutenv()->load(dirname(__DIR__).'/etc/backup.conf');

    // Per-server overrides (OpenStack credentials, hostname, and any other
    // variable from etc/backup.conf), written by the installer. Lives
    // outside the folder so it survives a fresh git clone.
    $localConfigFile = $_ENV['LOCAL_CONFIG_FILE'] ?? '';
    if ('' !== $localConfigFile && is_file($localConfigFile)) {
        $dotenv->overload($localConfigFile);
    }
}
