<?php

namespace App\Service;

use Symfony\Component\Process\Process;

/**
 * Wraps the OpenStack "swift" CLI for the bits that restic's own swift
 * backend does not cover: uploading small status objects and reporting
 * container storage usage (creamcloud-backup-stats).
 */
final class SwiftClient
{
    public function __construct(
        private readonly string $swiftContainer,
        private readonly string $osUsername,
        private readonly string $osPassword,
        private readonly string $osProjectName,
        private readonly string $osUserDomainName,
        private readonly string $osProjectDomainName,
        private readonly string $osRegionName,
        private readonly string $osAuthUrl,
        private readonly string $osIdentityApiVersion,
        private readonly ActivityLogger $logger,
    ) {
    }

    public function isConfigured(): bool
    {
        return '' !== $this->osUsername && '' !== $this->osPassword;
    }

    /**
     * Uploads a local file as $objectName into the configured container.
     */
    public function uploadObject(string $localPath, string $objectName): bool
    {
        if (!$this->isConfigured()) {
            $this->logger->debug('Swift credentials not configured, skipping status upload.');

            return false;
        }

        $process = new Process([
            'swift', 'upload', $this->swiftContainer, $localPath,
            '--object-name', $objectName,
        ], null, $this->env());
        $process->run();

        if (!$process->isSuccessful()) {
            $this->logger->error(sprintf('Could not upload %s to swift container %s.', $objectName, $this->swiftContainer));
            foreach (explode("\n", trim($process->getErrorOutput())) as $line) {
                if ('' !== $line) {
                    $this->logger->error($line);
                }
            }

            return false;
        }

        return true;
    }

    /**
     * Returns the human-readable amount of storage used in the
     * configured container, or null if it could not be determined.
     */
    public function storageUsed(): ?string
    {
        if (!$this->isConfigured()) {
            return null;
        }

        $process = new Process(['swift', 'stat', '--lh', $this->swiftContainer], null, $this->env());
        $process->run();

        if (!$process->isSuccessful()) {
            return null;
        }

        foreach (explode("\n", $process->getOutput()) as $line) {
            if (preg_match('/^\s*Bytes:\s*(.+)$/', $line, $matches)) {
                return trim($matches[1]);
            }
        }

        return null;
    }

    /**
     * @return array<string, string>
     */
    private function env(): array
    {
        return [
            'OS_USERNAME' => $this->osUsername,
            'OS_PASSWORD' => $this->osPassword,
            'OS_PROJECT_NAME' => $this->osProjectName,
            'OS_USER_DOMAIN_NAME' => $this->osUserDomainName,
            'OS_PROJECT_DOMAIN_NAME' => $this->osProjectDomainName,
            'OS_REGION_NAME' => $this->osRegionName,
            'OS_AUTH_URL' => $this->osAuthUrl,
            'OS_IDENTITY_API_VERSION' => $this->osIdentityApiVersion,
        ];
    }
}
