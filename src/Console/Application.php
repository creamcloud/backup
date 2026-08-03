<?php

namespace App\Console;

use Symfony\Component\Console\Application as BaseApplication;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Terminal;

/**
 * Adds the Cream Cloud Backup banner to the default `list`/`help` output,
 * matching the look of Cream's other console applications (e.g. Bull).
 */
final class Application extends BaseApplication
{
    private const LOGO = <<<'LOGO'

        ▄▄███████▄▄
     ▄███████████████▄
   ▄███▐███▀▀▄▄▄▄▀▀████▄
  ████▐██ ███▀▀▀███▄▀███▌   ▄█████▄ ██▄▄███▌ ▄█████▄  ▄██████▄ ██▌▄████▄▄████▄
 ▐███▌██ ██       ██▌████  ▐███   ▀ ▀███▀▀▀ ███▀  ███ ▀▀   ███  ███▀▀████▀▀███▌
 ▐███▌██ ▀█     █ ▐██▐███  ▐██▌     ▐██▌    █████████ ▄███████▌ ███   ███  ▐██▌
 ▐████▄▀█▄ ▀▀  ▄█ ███▐███  ▐██▌     ▐██▌    ███      ▐███   ██▌ ███   ███  ▐██▌
  █████▌▀▀████▀▀ ███▐███▌   ▀█████▀ ▐██▌    ▀███████▀ █████████ ███   ██▌   ██▌
   ▀██████▄▄▄▄█████▐███▀
     ▀███████████████▀
        ▀▀███████▀▀
LOGO;

    /**
     * @param iterable<Command> $commands
     */
    public function __construct(iterable $commands, string $version)
    {
        parent::__construct('Cream Cloud Backup', $version);

        foreach ($commands as $command) {
            $this->add($command);
        }
    }

    public function getHelp(): string
    {
        $separator = str_repeat('―', (new Terminal())->getWidth());

        return self::LOGO."\n\n".$separator."\n"
            .sprintf('%s - Restic Backup Wrapper <info>%s</info>', $this->getName(), $this->getVersion());
    }
}
