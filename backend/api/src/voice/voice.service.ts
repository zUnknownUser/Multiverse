import { createHash } from 'node:crypto';
import {
  ConflictException,
  ForbiddenException,
  Inject,
  HttpException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
  type OnModuleDestroy,
  type OnModuleInit,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { DatabaseService } from '../database/database.service.js';
import { SocialService } from '../social/social.service.js';
import { VoiceMediaService } from './voice-media.service.js';

type Lease = {
  id: string;
  firebase_uid: string;
  item_id: string;
  segment: number;
  room_name: string;
  revoked_at: Date | null;
  expires_at: Date;
};
@Injectable()
export class VoiceService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private cleaning = false;
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
    @Inject(VoiceMediaService) private readonly media: VoiceMediaService,
  ) {}
  availability() {
    return { enabled: this.media.enabled, maxParticipants: 8 };
  }
  private room(item: string, segment: number) {
    return (
      'mv-voice-' +
      createHash('sha256')
        .update(item + ':' + segment)
        .digest('hex')
        .slice(0, 32)
    );
  }
  private async authorize(
    client: PoolClient,
    uid: string,
    item: string,
    segment: number,
    room: string,
  ) {
    const member = await this.social.member(client, uid);
    const work = await client.query(
      "SELECT 1 FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id WHERE i.id=$1 AND i.status='published' AND u.status='active'",
      [item],
    );
    if (!work.rowCount)
      throw new NotFoundException({ code: 'ITEM_UNAVAILABLE' });
    const progress =
      (
        await client.query(
          'SELECT progress FROM room_visits WHERE item_id=$1 AND firebase_uid=$2',
          [item, uid],
        )
      ).rows[0]?.progress ?? 0;
    if (progress < segment * 50)
      throw new ForbiddenException({ code: 'ROOM_PROGRESS_REQUIRED' });
    const blocked = await client.query(
      `SELECT 1 FROM room_voice_sessions v JOIN user_blocks b
      ON (b.blocker_uid=$1 AND b.blocked_uid=v.firebase_uid) OR (b.blocked_uid=$1 AND b.blocker_uid=v.firebase_uid)
      WHERE v.room_name=$2 AND v.revoked_at IS NULL LIMIT 1`,
      [uid, room],
    );
    if (blocked.rowCount)
      throw new ForbiddenException({ code: 'VOICE_BLOCKED' });
    return member;
  }
  async join(uid: string, item: string, segment: number, id: string) {
    if (!this.media.enabled)
      throw new ServiceUnavailableException({ code: 'VOICE_UNAVAILABLE' });
    const room = this.room(item, segment);
    const name = await this.lifecycle.withActiveAccount(uid, async (client) => {
      await client.query(
        'SELECT pg_advisory_xact_lock(1297502532, hashtext($1))',
        [room],
      );
      await this.authorize(client, uid, item, segment, room);
      const old = (
        await client.query<Lease>(
          'SELECT * FROM room_voice_sessions WHERE id=$1 OR (firebase_uid=$2 AND revoked_at IS NULL)',
          [id, uid],
        )
      ).rows;
      if (
        old.some(
          (s) =>
            s.id !== id ||
            s.firebase_uid !== uid ||
            s.room_name !== room ||
            s.revoked_at !== null ||
            s.expires_at <= new Date(),
        )
      )
        throw new ConflictException({ code: 'VOICE_SESSION_CONFLICT' });
      if (!old.length) {
        const quota = (
          await client.query(
            `INSERT INTO room_voice_join_limits(firebase_uid) VALUES($1)
          ON CONFLICT(firebase_uid) DO UPDATE SET
          attempts=CASE WHEN room_voice_join_limits.window_start<now()-interval '1 hour' THEN 1 ELSE room_voice_join_limits.attempts+1 END,
          window_start=CASE WHEN room_voice_join_limits.window_start<now()-interval '1 hour' THEN now() ELSE room_voice_join_limits.window_start END
          RETURNING attempts`,
            [uid],
          )
        ).rows[0].attempts;
        if (quota > 30)
          throw new HttpException({ code: 'VOICE_JOIN_LIMIT' }, 429);

        const count = (
          await client.query(
            'SELECT count(*)::int AS n FROM room_voice_sessions WHERE room_name=$1 AND revoked_at IS NULL',
            [room],
          )
        ).rows[0].n;
        if (count >= 8) throw new ConflictException({ code: 'VOICE_FULL' });
        await client.query(
          'INSERT INTO room_voice_sessions(id,firebase_uid,item_id,segment,room_name) VALUES($1,$2,$3,$4,$5)',
          [id, uid, item, segment, room],
        );
      }
      const profile = (
        await client.query(
          'SELECT display_name FROM profiles WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0];
      return profile.display_name as string;
    });
    try {
      const ticket = await this.media.ticket(room, id, name);
      // A concurrent leave must never turn into a successful new connection.
      const renewed = await this.db.query(
        "UPDATE room_voice_sessions SET expires_at=now()+interval '60 seconds' WHERE id=$1 AND revoked_at IS NULL RETURNING id",
        [id],
      );
      if (!renewed.rowCount) {
        await this.media.remove(room, id);
        throw new ConflictException({ code: 'VOICE_SESSION_CONFLICT' });
      }
      return { id, room, ...ticket };
    } catch (error) {
      await this.db.query(
        'UPDATE room_voice_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE id=$1',
        [id],
      );
      throw error;
    }
  }
  async heartbeat(uid: string, id: string) {
    try {
      if (!this.media.enabled)
        throw new ForbiddenException({ code: 'VOICE_SESSION_ENDED' });
      return await this.lifecycle.withActiveAccount(uid, async (client) => {
        const lease = (
          await client.query<Lease>(
            'SELECT * FROM room_voice_sessions WHERE id=$1 AND firebase_uid=$2 AND revoked_at IS NULL AND expires_at>now() FOR UPDATE',
            [id, uid],
          )
        ).rows[0];
        if (!lease)
          throw new ForbiddenException({ code: 'VOICE_SESSION_ENDED' });
        await this.authorize(
          client,
          uid,
          lease.item_id,
          lease.segment,
          lease.room_name,
        );
        await client.query(
          "UPDATE room_voice_sessions SET expires_at=now()+interval '60 seconds' WHERE id=$1",
          [id],
        );
        return { active: true };
      });
    } catch (error) {
      await this.leave(uid, id);
      throw error;
    }
  }
  async leave(uid: string, id: string) {
    const lease = (
      await this.db.query<Lease>(
        'UPDATE room_voice_sessions SET revoked_at=coalesce(revoked_at,now()) WHERE id=$1 AND firebase_uid=$2 RETURNING *',
        [id, uid],
      )
    ).rows[0];
    if (lease) await this.media.remove(lease.room_name, id);
    return { left: true };
  }
  onModuleInit() {
    if (!this.media.configured) return;
    this.timer = setInterval(() => {
      void this.cleanup();
    }, 15_000);
    this.timer.unref();
  }
  onModuleDestroy() {
    if (this.timer) clearInterval(this.timer);
  }
  async cleanup() {
    if (this.cleaning || !this.media.configured) return;
    this.cleaning = true;
    try {
      const leases = (
        await this.db.query<Lease>(
          `SELECT v.* FROM room_voice_sessions v
        WHERE NOT $1::boolean OR v.revoked_at IS NOT NULL OR v.expires_at<=now()
        OR NOT EXISTS(SELECT 1 FROM profiles p JOIN onboarding o USING(firebase_uid)
          JOIN catalog_items i ON i.id=v.item_id JOIN catalog_universes u ON u.id=i.universe_id
          LEFT JOIN room_visits rv ON rv.item_id=v.item_id AND rv.firebase_uid=v.firebase_uid
          WHERE p.firebase_uid=v.firebase_uid AND p.deletion_requested_at IS NULL AND o.completed
          AND i.status='published' AND u.status='active' AND coalesce(rv.progress,0)>=v.segment*50
          AND NOT EXISTS(SELECT 1 FROM account_deletions d WHERE d.firebase_uid=v.firebase_uid))
        OR EXISTS(SELECT 1 FROM room_voice_sessions other JOIN user_blocks b
          ON (b.blocker_uid=v.firebase_uid AND b.blocked_uid=other.firebase_uid)
          OR (b.blocked_uid=v.firebase_uid AND b.blocker_uid=other.firebase_uid)
          WHERE other.room_name=v.room_name AND other.revoked_at IS NULL)
        ORDER BY v.expires_at LIMIT 200`,
          [this.media.enabled],
        )
      ).rows;
      // Bound media requests so a provider outage does not monopolize the worker.
      for (let offset = 0; offset < leases.length; offset += 8) {
        await Promise.all(
          leases.slice(offset, offset + 8).map(async (lease) => {
            try {
              await this.leave(lease.firebase_uid, lease.id);
              await this.db.query(
                "DELETE FROM room_voice_sessions WHERE id=$1 AND revoked_at<now()-interval '2 minutes'",
                [lease.id],
              );
            } catch {
              /* Retry media cleanup; never log credentials or tokens. */
            }
          }),
        );
      }
    } catch {
      /* The next sweep retries database outages. */
    } finally {
      this.cleaning = false;
    }
  }
}
