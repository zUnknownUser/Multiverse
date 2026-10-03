import {
  Inject,
  Injectable,
  type OnModuleInit,
  type OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { getMessaging, type BatchResponse } from 'firebase-admin/messaging';
import { DatabaseService } from '../database/database.service.js';
import { FirebaseTokenVerifier } from '../auth/firebase-token-verifier.js';
import {
  notificationRelations,
  notificationVisible,
} from './notification-policy.js';
@Injectable()
export class PushService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private running = false;
  constructor(
    @Inject(ConfigService) private readonly config: ConfigService,
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(FirebaseTokenVerifier)
    private readonly firebase: FirebaseTokenVerifier,
  ) {}
  onModuleInit() {
    if (this.config.get<string>('PUSH_ENABLED') !== 'true') return;
    this.timer = setInterval(() => {
      void this.tick();
    }, 15000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  async tick() {
    if (this.running || this.config.get<string>('PUSH_ENABLED') !== 'true')
      return;
    this.running = true;
    try {
      for (let i = 0; i < 10; i++) {
        if (!(await this.deliverNext())) break;
      }
    } catch {
      /* Never log tokens, credentials or payloads. Pending jobs retry on the next tick. */
    } finally {
      this.running = false;
    }
  }
  private async deliverNext() {
    return this.db.transaction(async (client) => {
      const job = (
        await client.query(
          `SELECT * FROM notifications WHERE push_state='pending' AND push_after<=now() ORDER BY push_after,id LIMIT 1 FOR UPDATE SKIP LOCKED`,
        )
      ).rows[0];
      if (!job) return false;
      const eligible = await client.query(
        `SELECT n.id FROM ${notificationRelations}
    JOIN notification_preferences np ON np.firebase_uid=n.recipient_uid AND np.activity AND np.push
    JOIN profiles recipient ON recipient.firebase_uid=n.recipient_uid AND recipient.deletion_requested_at IS NULL
    WHERE n.id=$2 AND ${notificationVisible} AND n.read_at IS NULL AND n.created_at>now()-interval '24 hours'`,
        [job.recipient_uid, job.id],
      );
      if (!eligible.rowCount || job.push_attempts >= 5) {
        await client.query(
          "UPDATE notifications SET push_state='skipped' WHERE id=$1",
          [job.id],
        );
        return true;
      }
      const devices = (
        await client.query(
          `SELECT d.id,d.token FROM push_devices d WHERE d.firebase_uid=$1 AND d.updated_at>now()-interval '60 days'
    AND NOT EXISTS(SELECT 1 FROM push_deliveries sent WHERE sent.notification_id=$2 AND sent.device_id=d.id) ORDER BY d.id FOR UPDATE OF d`,
          [job.recipient_uid, job.id],
        )
      ).rows;
      let retry = false;
      if (devices.length) {
        const unread = await client.query(
          `SELECT count(*)::int AS count FROM ${notificationRelations} WHERE ${notificationVisible} AND n.read_at IS NULL`,
          [job.recipient_uid],
        );
        let result: BatchResponse | undefined;
        try {
          result = await getMessaging(this.firebase.app()).sendEachForMulticast(
            {
              tokens: devices.map((d) => d.token),
              notification: {
                title: 'Multiverse',
                body: 'Nova atividade · New activity',
              },
              data: { notificationID: job.id },
              apns: {
                headers: {
                  'apns-collapse-id': job.id,
                  'apns-expiration': String(
                    Math.floor(Date.now() / 1000) + 3600,
                  ),
                },
                payload: {
                  aps: { sound: 'default', badge: unread.rows[0].count },
                },
              },
            },
          );
        } catch {
          retry = true;
        }
        for (const [index, response] of (result?.responses ?? []).entries()) {
          const device = devices[index];
          if (response.success)
            await client.query(
              'INSERT INTO push_deliveries(notification_id,device_id) VALUES($1,$2) ON CONFLICT DO NOTHING',
              [job.id, device.id],
            );
          else if (
            [
              'messaging/registration-token-not-registered',
              'messaging/invalid-registration-token',
            ].includes(response.error?.code ?? '')
          )
            await client.query('DELETE FROM push_devices WHERE id=$1', [
              device.id,
            ]);
          else retry = true;
        }
      }
      await client.query(
        `UPDATE notifications SET push_state=$2,push_attempts=push_attempts+1,push_after=now()+interval '1 minute'*power(2,push_attempts) WHERE id=$1`,
        [job.id, retry ? 'pending' : 'sent'],
      );
      return true;
    });
  }
}
