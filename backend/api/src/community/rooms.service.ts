import {
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';
import { RoomEventsService } from './room-events.service.js';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
import { unblocked } from '../social/social-policy.js';

@Injectable()
export class RoomsService {
  private readonly waiting = new Map<string, number>();
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(RoomEventsService) private readonly events: RoomEventsService,
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  async rooms(uid: string, q: string, after?: string, universe?: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const rows = (
        await client.query(
          `SELECT i.id AS "itemID",u.id AS "universeID",
       (SELECT count(*)::int FROM room_visits v JOIN profiles vp ON vp.firebase_uid=v.firebase_uid WHERE v.item_id=i.id AND v.seen_at>now()-interval '1 minute' AND vp.deletion_requested_at IS NULL AND ${unblocked('$1', 'v.firebase_uid')}) AS online,
       coalesce((SELECT progress FROM room_visits WHERE item_id=i.id AND firebase_uid=$1),0) AS progress
       FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id JOIN catalog_item_translations t ON t.item_id=i.id
       WHERE i.status='published' AND u.status='active' AND ($2::text='' OR strpos(lower(t.title),lower($2))>0)
       AND ($3::text IS NULL OR i.id COLLATE "C">$3 COLLATE "C") AND ($4::text IS NULL OR u.id=$4) GROUP BY i.id,u.id ORDER BY i.id COLLATE "C" LIMIT 31`,
          [uid, q, after ?? null, universe ?? null],
        )
      ).rows;
      return {
        rooms: rows.slice(0, 30),
        nextCursor: rows.length > 30 ? rows[29].itemID : null,
      };
    });
  }
  async changes(
    uid: string,
    item: string,
    after: string | undefined,
    signal: AbortSignal,
  ) {
    if ((this.waiting.get(uid) ?? 0) >= 3)
      throw new HttpException({ code: 'RATE_LIMITED' }, 429);
    this.waiting.set(uid, (this.waiting.get(uid) ?? 0) + 1);
    try {
      // Validate membership/catalog before allocating a waiting subscription.
      await this.visit(uid, item);
      const watch = await this.events.watch(item, signal);
      try {
        const revision = async () =>
          (
            await this.db.query<{ revision: string }>(
              "SELECT coalesce((SELECT revision::text FROM room_revisions WHERE item_id=$1), '0') AS revision",
              [item],
            )
          ).rows[0].revision;
        const current = await revision();
        if (after === current && !signal.aborted) await watch.changed;
        // Revalidate after waiting; account/catalog access may have changed.
        const room = await this.visit(uid, item);
        return { ...room, revision: await revision() };
      } finally {
        watch.dispose();
      }
    } finally {
      const remaining = (this.waiting.get(uid) ?? 1) - 1;
      if (remaining) this.waiting.set(uid, remaining);
      else this.waiting.delete(uid);
    }
  }
  async visit(uid: string, item: string, progress?: number) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      if (
        !(
          await client.query(
            "SELECT 1 FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id WHERE i.id=$1 AND i.status='published' AND u.status='active'",
            [item],
          )
        ).rowCount
      )
        throw new NotFoundException({ code: 'ITEM_UNAVAILABLE' });
      const row = (
        await client.query(
          'INSERT INTO room_visits(item_id,firebase_uid,progress) VALUES($1,$2,coalesce($3,0)) ON CONFLICT(item_id,firebase_uid) DO UPDATE SET seen_at=now(),progress=coalesce($3,room_visits.progress) RETURNING progress',
          [item, uid, progress ?? null],
        )
      ).rows[0];
      const online = (
        await client.query(
          `SELECT count(*)::int AS count FROM room_visits v JOIN profiles p ON p.firebase_uid=v.firebase_uid WHERE v.item_id=$2 AND v.seen_at>now()-interval '1 minute' AND p.deletion_requested_at IS NULL AND ${unblocked('$1', 'v.firebase_uid')}`,
          [uid, item],
        )
      ).rows[0].count;
      return { itemID: item, progress: row.progress, online };
    });
  }
}
