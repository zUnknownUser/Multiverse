import {
  BadRequestException,
  ConflictException,
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService, type FeedCursor } from '../social/social.service.js';
import { unblocked } from '../social/social-policy.js';
import { RoomEventsService } from '../community/room-events.service.js';
import { recordNotification } from '../notifications/notification-events.js';

export interface MessageInput {
  kind: 'text' | 'workCard';
  text: string;
  itemID?: string;
  spoiler: boolean;
}
const peerExpression = `CASE WHEN t.user_a=$1 THEN t.user_b ELSE t.user_a END`;
const visible = `t.state<>'declined' AND $1 IN(t.user_a,t.user_b) AND p.deletion_requested_at IS NULL AND o.completed AND ${unblocked('$1', 'p.firebase_uid')}`;
const relations = `dm_threads t JOIN profiles p ON p.firebase_uid=${peerExpression} JOIN onboarding o ON o.firebase_uid=p.firebase_uid`;
const messageFields = `m.id,m.sender_uid AS "senderID",m.sequence::text AS sequence,m.created_at AS "createdAt",
 CASE WHEN m.moderation_status='hidden' OR EXISTS(SELECT 1 FROM dm_reports dr WHERE dr.message_id=m.id AND dr.reporter_uid=$1) THEN 'removed' ELSE m.kind END AS kind,
 CASE WHEN m.moderation_status='hidden' OR EXISTS(SELECT 1 FROM dm_reports dr WHERE dr.message_id=m.id AND dr.reporter_uid=$1) THEN '' ELSE m.text END AS text,
 CASE WHEN m.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM dm_reports dr WHERE dr.message_id=m.id AND dr.reporter_uid=$1)
 AND EXISTS(SELECT 1 FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id WHERE i.id=m.item_id AND i.status='published' AND u.status='active') THEN m.item_id ELSE NULL END AS "itemID",m.spoiler`;
function user(row: Record<string, unknown>) {
  return {
    id: row.firebase_uid,
    name: row.display_name,
    handle: '@' + row.username,
    avatarColor: row.avatar_color,
    avatarID: row.avatar_id,
    bio: row.bio,
    followers: null,
    badgeUniverse: '',
  };
}
@Injectable()
export class MessagesService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
    @Inject(RoomEventsService) private readonly events: RoomEventsService,
  ) {}
  private unavailable(): never {
    throw new NotFoundException({ code: 'MESSAGE_UNAVAILABLE' });
  }
  private async peer(c: PoolClient, uid: string, peer: string) {
    if (uid === peer || peer === 'multiverse-editorial') this.unavailable();
    const r = await c.query(
      `SELECT p.* FROM profiles p JOIN onboarding o USING(firebase_uid) WHERE p.firebase_uid=$2 AND p.deletion_requested_at IS NULL AND o.completed AND ${unblocked('$1', 'p.firebase_uid')}`,
      [uid, peer],
    );
    if (!r.rowCount) this.unavailable();
    return r.rows[0];
  }
  private async thread(
    c: PoolClient,
    uid: string,
    peer: string,
    lock = false,
    includeDeclined = false,
  ) {
    const r = await c.query(
      `SELECT * FROM dm_threads WHERE user_a=least($1::text COLLATE "C",$2::text COLLATE "C") AND user_b=greatest($1::text COLLATE "C",$2::text COLLATE "C") ${lock ? 'FOR UPDATE' : ''}`,
      [uid, peer],
    );
    if (!includeDeclined && r.rows[0]?.state === 'declined') this.unavailable();
    return r.rows[0];
  }
  private async revision(c: PoolClient, uid: string) {
    return (
      (
        await c.query(
          'SELECT revision::text FROM dm_revisions WHERE firebase_uid=$1',
          [uid],
        )
      ).rows[0]?.revision ?? '0'
    );
  }
  async inbox(uid: string, after?: FeedCursor) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      const r = await c.query(
        `SELECT t.id,p.*,t.state,t.initiator,t.updated_at AS "updatedAt",
    to_char(t.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime",
    (SELECT count(*)::int FROM dm_messages m WHERE m.thread_id=t.id AND m.sender_uid<>$1 AND m.sequence>coalesce(dr.sequence,0) AND m.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM dm_reports rr WHERE rr.message_id=m.id AND rr.reporter_uid=$1)) AS unread,
    (SELECT row_to_json(last_message) FROM (SELECT ${messageFields} FROM dm_messages m WHERE m.thread_id=t.id ORDER BY m.sequence DESC LIMIT 1) last_message) AS "lastMessage"
    FROM ${relations} LEFT JOIN dm_reads dr ON dr.thread_id=t.id AND dr.firebase_uid=$1
    WHERE ${visible} AND ($2::timestamptz IS NULL OR (t.updated_at,t.id)<($2::timestamptz,$3::uuid)) ORDER BY t.updated_at DESC,t.id DESC LIMIT 31`,
        [uid, after?.time ?? null, after?.id ?? null],
      );
      const count = await c.query(
        `SELECT count(*)::int AS count FROM ${relations} JOIN dm_messages m ON m.thread_id=t.id LEFT JOIN dm_reads dr ON dr.thread_id=t.id AND dr.firebase_uid=$1 WHERE ${visible} AND m.sender_uid<>$1 AND m.sequence>coalesce(dr.sequence,0) AND m.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM dm_reports rr WHERE rr.message_id=m.id AND rr.reporter_uid=$1)`,
        [uid],
      );
      const rows = r.rows.slice(0, 30),
        last = rows.at(-1);
      return {
        conversations: rows.map((x) => ({
          id: x.id,
          user: user(x),
          state: x.state,
          incomingRequest: x.state === 'pending' && x.initiator !== uid,
          unreadCount: x.unread,
          updatedAt: x.updatedAt,
          lastMessage: x.lastMessage,
        })),
        unreadCount: count.rows[0].count,
        revision: await this.revision(c, uid),
        nextCursor:
          r.rows.length > 30
            ? Buffer.from(
                JSON.stringify({ time: last!.cursorTime, id: last!.id }),
              ).toString('base64url')
            : null,
      };
    });
  }
  async history(uid: string, peer: string, before?: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      const p = await this.peer(c, uid, peer);
      const t = await this.thread(c, uid, peer);
      if (!t)
        return {
          user: user(p),
          state: 'new',
          incomingRequest: false,
          messages: [],
          before: null,
          readThrough: '0',
        };
      const r = await c.query(
        `SELECT ${messageFields} FROM dm_messages m WHERE m.thread_id=$2 AND ($3::bigint IS NULL OR m.sequence<$3) ORDER BY m.sequence DESC LIMIT 41`,
        [uid, t.id, before ?? null],
      );
      const rows = r.rows.slice(0, 40).reverse();
      const read =
        (
          await c.query(
            'SELECT sequence::text FROM dm_reads WHERE thread_id=$1 AND firebase_uid=$2',
            [t.id, peer],
          )
        ).rows[0]?.sequence ?? '0';
      return {
        user: user(p),
        state: t.state,
        incomingRequest: t.state === 'pending' && t.initiator !== uid,
        messages: rows,
        before: r.rows.length > 40 ? rows[0].sequence : null,
        readThrough: read,
      };
    });
  }
  async send(uid: string, peer: string, id: string, input: MessageInput) {
    if (
      (input.kind === 'text' &&
        (!input.text.trim() || input.itemID !== undefined)) ||
      (input.kind === 'workCard' && !input.itemID)
    )
      throw new BadRequestException({ code: 'INVALID_MESSAGE' });
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await this.peer(c, uid, peer);
      const pair = [uid, peer].sort().join('|');
      await c.query('SELECT pg_advisory_xact_lock(1297502537,hashtext($1))', [
        pair,
      ]);
      let t = await this.thread(c, uid, peer, true);
      const existing = (
        await c.query('SELECT * FROM dm_messages WHERE id=$1', [id])
      ).rows[0];
      if (existing) {
        if (
          existing.thread_id !== t?.id ||
          existing.sender_uid !== uid ||
          existing.kind !== input.kind ||
          existing.text !== input.text.trim() ||
          existing.item_id !== (input.itemID ?? null) ||
          existing.spoiler !== input.spoiler
        )
          throw new ConflictException({ code: 'MESSAGE_CONFLICT' });
        return { id, saved: true };
      }
      if (
        input.itemID &&
        !(
          await c.query(
            "SELECT 1 FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id WHERE i.id=$1 AND i.status='published' AND u.status='active'",
            [input.itemID],
          )
        ).rowCount
      )
        throw new ConflictException({ code: 'ITEM_UNAVAILABLE' });
      const budget = await c.query(
        "SELECT count(*)::int AS count FROM dm_messages WHERE sender_uid=$1 AND created_at>now()-interval '1 hour'",
        [uid],
      );
      if (budget.rows[0].count >= 120)
        throw new HttpException({ code: 'MESSAGE_LIMIT' }, 429);
      if (!t) {
        const starts = await c.query(
          "SELECT count(*)::int AS count FROM dm_threads WHERE initiator=$1 AND created_at>now()-interval '1 hour'",
          [uid],
        );
        if (starts.rows[0].count >= 10)
          throw new HttpException({ code: 'MESSAGE_LIMIT' }, 429);
        t = (
          await c.query(
            `INSERT INTO dm_threads(user_a,user_b,initiator,state) VALUES(least($1::text COLLATE "C",$2::text COLLATE "C"),greatest($1::text COLLATE "C",$2::text COLLATE "C"),$1,
    CASE WHEN EXISTS(SELECT 1 FROM visible_follows WHERE follower_uid=$2 AND followed_uid=$1) THEN 'accepted' ELSE 'pending' END) RETURNING *`,
            [uid, peer],
          )
        ).rows[0];
      } else if (t.state === 'pending')
        throw new ConflictException({ code: 'MESSAGE_REQUEST_PENDING' });
      const seq = (
        await c.query(
          'UPDATE dm_threads SET sequence=sequence+1,updated_at=clock_timestamp() WHERE id=$1 RETURNING sequence',
          [t.id],
        )
      ).rows[0].sequence;
      await c.query(
        'INSERT INTO dm_messages(id,thread_id,sender_uid,sequence,kind,text,item_id,spoiler) VALUES($1,$2,$3,$4,$5,$6,$7,$8)',
        [
          id,
          t.id,
          uid,
          seq,
          input.kind,
          input.text.trim(),
          input.itemID ?? null,
          input.spoiler,
        ],
      );
      await recordNotification(c, peer, uid, 'message', 'message', id);
      return { id, saved: true };
    });
  }
  async decide(uid: string, peer: string, accepted: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await this.peer(c, uid, peer);
      const t = await this.thread(c, uid, peer, true, true);
      if (!t || t.initiator === uid) this.unavailable();
      if (t.state === 'declined' && accepted) this.unavailable();
      if (t.state === 'accepted' && !accepted)
        throw new ConflictException({ code: 'MESSAGE_CONFLICT' });
      if (t.state === 'pending')
        await c.query('UPDATE dm_threads SET state=$2 WHERE id=$1', [
          t.id,
          accepted ? 'accepted' : 'declined',
        ]);
      return { saved: true };
    });
  }
  async read(uid: string, peer: string, through: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await this.peer(c, uid, peer);
      const t = await this.thread(c, uid, peer, true);
      if (!t) this.unavailable();
      if (BigInt(through) > BigInt(t.sequence))
        throw new BadRequestException({ code: 'INVALID_MESSAGE' });
      await c.query(
        `INSERT INTO dm_reads(thread_id,firebase_uid,sequence) VALUES($1,$2,$3) ON CONFLICT(thread_id,firebase_uid) DO UPDATE SET sequence=EXCLUDED.sequence WHERE dm_reads.sequence<EXCLUDED.sequence`,
        [t.id, uid, through],
      );
      await c.query(
        `UPDATE notifications SET read_at=coalesce(read_at,now()) WHERE recipient_uid=$1 AND target_type='message' AND target_id IN(SELECT id::text FROM dm_messages WHERE thread_id=$2 AND sequence<=$3)`,
        [uid, t.id, through],
      );
      return { saved: true };
    });
  }
  async report(
    uid: string,
    peer: string,
    id: string,
    reason: string,
    alsoBlock: boolean,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await this.peer(c, uid, peer);
      const t = await this.thread(c, uid, peer, true);
      if (
        !t ||
        !(
          await c.query(
            'SELECT 1 FROM dm_messages WHERE id=$1 AND thread_id=$2 AND sender_uid=$3',
            [id, t.id, peer],
          )
        ).rowCount
      )
        this.unavailable();
      if (
        (
          await c.query(
            "SELECT count(*)::int AS count FROM dm_reports WHERE reporter_uid=$1 AND created_at>now()-interval '1 hour'",
            [uid],
          )
        ).rows[0].count >= 30
      )
        throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
      await c.query(
        'INSERT INTO dm_reports(reporter_uid,message_id,reason) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',
        [uid, id, reason],
      );
      if (alsoBlock)
        await c.query(
          'INSERT INTO user_blocks(blocker_uid,blocked_uid) VALUES($1,$2) ON CONFLICT DO NOTHING',
          [uid, peer],
        );
      await c.query('SELECT dm_changed($1)', [uid]);
      return { saved: true };
    });
  }
  async changes(uid: string, after: string | undefined, signal: AbortSignal) {
    const read = () =>
      this.lifecycle.withActiveAccount(uid, async (c) => {
        await this.social.member(c, uid);
        return this.revision(c, uid);
      });
    await read();
    const watcher = await this.events.watch('dm:' + uid, signal);
    try {
      let revision = await read();
      if (after === revision && !signal.aborted) {
        await watcher.changed;
        revision = await read();
      }
      return { revision };
    } finally {
      watcher.dispose();
    }
  }
}
