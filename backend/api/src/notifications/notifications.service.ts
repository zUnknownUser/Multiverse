import { ConflictException, Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService, type FeedCursor } from '../social/social.service.js';
import {
  notificationRelations,
  notificationVisible,
} from './notification-policy.js';
@Injectable()
export class NotificationsService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
    @Inject(ConfigService) private readonly config: ConfigService,
  ) {}
  async list(uid: string, cursor?: FeedCursor) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const result = await client.query(
        `SELECT n.id,n.kind,n.target_type AS "targetType",n.target_id AS "targetID",n.comment_id AS "commentID",n.created_at AS "createdAt",n.read_at AS "readAt",
  n.actor_uid AS "user",ap.display_name AS name,ap.username,ap.avatar_color AS "avatarColor",ap.avatar_id AS "avatarID",
  to_char(n.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime"
  FROM ${notificationRelations} WHERE ${notificationVisible}
  AND ($2::timestamptz IS NULL OR (n.created_at,n.id)<($2::timestamptz,$3::uuid)) ORDER BY n.created_at DESC,n.id DESC LIMIT 31`,
        [uid, cursor?.time ?? null, cursor?.id ?? null],
      );
      const rows = result.rows.slice(0, 30),
        last = rows.at(-1);
      const count = await client.query(
        `SELECT count(*)::int AS count FROM ${notificationRelations} WHERE ${notificationVisible} AND n.read_at IS NULL`,
        [uid],
      );
      return {
        notifications: rows.map((r) => ({
          id: r.id,
          kind: r.kind,
          targetType: r.targetType,
          targetID: r.targetID,
          commentID: r.commentID,
          createdAt: r.createdAt,
          readAt: r.readAt,
          user: r.user,
        })),
        users: [
          ...new Map(
            rows.map((r) => [
              r.user,
              {
                id: r.user,
                name: r.name,
                handle: '@' + r.username,
                avatarColor: r.avatarColor,
                avatarID: r.avatarID,
                bio: '',
                followers: null,
                badgeUniverse: '',
              },
            ]),
          ).values(),
        ],
        unreadCount: count.rows[0].count,
        nextCursor:
          result.rows.length > 30
            ? Buffer.from(
                JSON.stringify({ time: last!.cursorTime, id: last!.id }),
              ).toString('base64url')
            : null,
      };
    });
  }
  async read(uid: string, ids: string[]) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      // Explicit IDs: an alert arriving while the screen loads must stay unread.
      await client.query(
        'UPDATE notifications SET read_at=coalesce(read_at,now()) WHERE recipient_uid=$1 AND id=ANY($2::uuid[])',
        [uid, ids],
      );
      return { saved: true };
    });
  }
  async preferences(uid: string, input?: { activity: boolean; push: boolean }) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const pushAvailable = this.config.get<string>('PUSH_ENABLED') === 'true';
      if (input?.push && !pushAvailable)
        throw new ConflictException({ code: 'PUSH_NOT_CONFIGURED' });
      if (input)
        await client.query(
          `INSERT INTO notification_preferences(firebase_uid,activity,push) VALUES($1,$2,$3)
   ON CONFLICT(firebase_uid) DO UPDATE SET activity=EXCLUDED.activity,push=EXCLUDED.push`,
          [uid, input.activity, input.push],
        );
      const row = (
        await client.query(
          'SELECT activity,push FROM notification_preferences WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0];
      return {
        activity: row?.activity ?? true,
        push: row?.push ?? false,
        pushAvailable,
      };
    });
  }
  async device(uid: string, id: string, token?: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      if (token) {
        if (this.config.get<string>('PUSH_ENABLED') !== 'true')
          throw new ConflictException({ code: 'PUSH_NOT_CONFIGURED' });
        // Do not reassign tokens between accounts. The old authenticated session must unregister first.
        const old = (
          await client.query(
            'SELECT firebase_uid,id,token FROM push_devices WHERE id=$1 OR token=$2 FOR UPDATE',
            [id, token],
          )
        ).rows;
        if (old.some((r) => r.firebase_uid !== uid || r.id !== id))
          throw new ConflictException({ code: 'DEVICE_CONFLICT' });
        if (
          (
            await client.query(
              'SELECT count(*)::int AS count FROM push_devices WHERE firebase_uid=$1',
              [uid],
            )
          ).rows[0].count >= 10 &&
          !old.length
        )
          throw new ConflictException({ code: 'DEVICE_LIMIT' });
        try {
          await client.query(
            `INSERT INTO push_devices(id,firebase_uid,token) VALUES($1,$2,$3)
    ON CONFLICT(id) DO UPDATE SET token=EXCLUDED.token,updated_at=now()`,
            [id, uid, token],
          );
        } catch (error) {
          if ((error as { code?: string }).code === '23505')
            throw new ConflictException({ code: 'DEVICE_CONFLICT' });
          throw error;
        }
      } else
        await client.query(
          'DELETE FROM push_devices WHERE id=$1 AND firebase_uid=$2',
          [id, uid],
        );
      return { saved: true };
    });
  }
}
