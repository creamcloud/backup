<?php

namespace App\EventSubscriber;

use App\Event\BackupFailedEvent;
use App\Service\ActivityLogger;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\Mailer\Exception\TransportExceptionInterface;
use Symfony\Component\Mailer\MailerInterface;
use Symfony\Component\Mime\Email;

/**
 * Sends a failure notification email, replacing
 * post-fail-backup.d/20-failure-notify.sh. Recipients are configured via
 * the NOTIFICATION_EMAILS environment variable (comma separated).
 */
final class FailureNotificationSubscriber implements EventSubscriberInterface
{
    /**
     * @param string[] $notificationEmails
     */
    public function __construct(
        private readonly MailerInterface $mailer,
        private readonly ActivityLogger $logger,
        private readonly string $hostname,
        private readonly string $mailFrom,
        private readonly array $notificationEmails,
    ) {
    }

    public static function getSubscribedEvents(): array
    {
        return [
            BackupFailedEvent::class => ['onBackupFailed', 90],
        ];
    }

    public function onBackupFailed(BackupFailedEvent $event): void
    {
        $recipients = array_values(array_filter(array_map('trim', $this->notificationEmails)));
        if ([] === $recipients) {
            $this->logger->debug('No notification email addresses configured, not sending failure email.');

            return;
        }

        $email = (new Email())
            ->from($this->mailFrom)
            ->subject(sprintf('[Cream Cloud Backup] %s: backup failed', $this->hostname))
            ->text($this->buildBody($event));

        foreach ($recipients as $recipient) {
            $email->addTo($recipient);
        }

        try {
            $this->mailer->send($email);
        } catch (TransportExceptionInterface $exception) {
            $this->logger->error('Could not send failure notification email: '.$exception->getMessage());
        }
    }

    private function buildBody(BackupFailedEvent $event): string
    {
        $lines = [
            sprintf('The backup on %s did not complete successfully.', $this->hostname),
            sprintf('Date: %s (server date/time).', date('Y-m-d H:i:s')),
            sprintf('Failed stage: restic %s', $event->getStage()),
            '',
            '===== BEGIN ERROR OUTPUT =====',
            ...$event->getErrorLines(),
            '===== END ERROR OUTPUT =====',
            '',
            'Your files have NOT been backed up during this session. Please investigate this issue.',
        ];

        return implode("\n", $lines);
    }
}
