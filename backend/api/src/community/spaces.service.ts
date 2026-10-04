import { RoomEventsService } from './room-events.service.js';
import { DatabaseService } from '../database/database.service.js';
import { reportQuotaSQL } from './community-policy.js';
import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
import { unblocked } from '../social/social-policy.js';

const visible = `cl.deleted_at IS NULL AND cl.moderation_status='visible' AND NOT EXISTS(SELECT 1 FROM club_reports clr WHERE clr.club_id=cl.id AND clr.reporter_uid=$1) AND p.deletion_requested_at IS NULL AND u.status='active' AND ${unblocked('$1', 'cl.owner_uid')}`;
const relations = `community_clubs cl JOIN profiles p ON p.firebase_uid=cl.owner_uid JOIN catalog_universes u ON u.id=cl.universe_id`;
const fields = `cl.id,cl.owner_uid AS owner,cl.universe_id AS "universeID",cl.name,cl.description,cl.version,cl.created_at AS "createdAt",
 (SELECT count(*)::int FROM club_members m JOIN profiles mp ON mp.firebase_uid=m.firebase_uid WHERE m.club_id=cl.id AND mp.deletion_requested_at IS NULL AND ${unblocked('$1', 'm.firebase_uid')}) AS "memberCount",
 EXISTS(SELECT 1 FROM club_members m WHERE m.club_id=cl.id AND m.firebase_uid=$1) AS joined`;
@Injectable()
export class SpacesService {
  private readonly waiting = new Map<string, number>();
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(RoomEventsService) private readonly events: RoomEventsService,
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  private async club(
    client: PoolClient,
    uid: string,
    id: string,
    owner = false,
    member = false,
  ) {
    const row = (
      await client.query(
        `SELECT cl.* FROM ${relations} WHERE cl.id=$2 AND ${visible} FOR UPDATE OF cl`,
        [uid, id],
      )
    ).rows[0];
    if (!row) throw new NotFoundException({ code: 'CLUB_UNAVAILABLE' });
    if (owner && row.owner_uid !== uid)
      throw new ForbiddenException({ code: 'CLUB_OWNER_REQUIRED' });
    if (
      member &&
      !(
        await client.query(
          'SELECT 1 FROM club_members WHERE club_id=$1 AND firebase_uid=$2',
          [id, uid],
        )
      ).rowCount
    )
      throw new ForbiddenException({ code: 'CLUB_MEMBERSHIP_REQUIRED' });
    return row;
  }
  async list(uid: string, q: string, after?: string, universe?: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const rows = (
        await client.query(
          `SELECT ${fields} FROM ${relations} WHERE ${visible} AND strpos(lower(cl.name || ' ' || cl.description),lower($2))>0 AND ($3::uuid IS NULL OR cl.id>$3) AND ($4::text IS NULL OR cl.universe_id=$4) ORDER BY cl.id LIMIT 31`,
          [uid, q, after ?? null, universe ?? null],
        )
      ).rows;
      return {
        clubs: rows.slice(0, 30),
        nextCursor: rows.length > 30 ? rows[29].id : null,
      };
    });
  }
  async detail(uid: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      await this.club(client, uid, id);
      const club = (
        await client.query(
          `SELECT ${fields} FROM ${relations} WHERE cl.id=$2 AND ${visible}`,
          [uid, id],
        )
      ).rows[0];
      const schedule = (
        await client.query(
          `SELECT s.id,s.item_id AS "itemID",to_char(s.starts_on,'YYYY-MM-DD') AS "startsOn",s.total_units AS "totalUnits",s.unit_label AS "unitLabel",coalesce(pr.units,0) AS "myUnits" FROM club_schedule s
       JOIN catalog_items ci ON ci.id=s.item_id AND ci.status='published'
       LEFT JOIN club_progress pr ON pr.schedule_id=s.id AND pr.firebase_uid=$1 WHERE s.club_id=$2 ORDER BY s.starts_on,s.id`,
          [uid, id],
        )
      ).rows;
      return { club, schedule };
    });
  }
  async save(
    uid: string,
    id: string,
    input: {
      name: string;
      description: string;
      universeID: string;
      version?: number;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const old = (
        await client.query(
          'SELECT * FROM community_clubs WHERE id=$1 FOR UPDATE',
          [id],
        )
      ).rows[0];
      if (old) {
        if (
          old.owner_uid !== uid ||
          old.deleted_at ||
          old.moderation_status !== 'visible'
        )
          throw new NotFoundException({ code: 'CLUB_UNAVAILABLE' });
        if (
          old.name === input.name &&
          old.description === input.description &&
          old.universe_id === input.universeID
        )
          return { id, saved: true };
        if (
          old.version !== input.version ||
          old.universe_id !== input.universeID
        )
          throw new ConflictException({ code: 'POST_STALE' });
        await client.query(
          'UPDATE community_clubs SET name=$2,description=$3,version=version+1 WHERE id=$1',
          [id, input.name, input.description],
        );
      } else {
        if (input.version !== undefined)
          throw new NotFoundException({ code: 'CLUB_UNAVAILABLE' });
        if (
          !(
            await client.query(
              "SELECT 1 FROM catalog_universes WHERE id=$1 AND status='active'",
              [input.universeID],
            )
          ).rowCount
        )
          throw new BadRequestException({ code: 'INVALID_POST_CATALOG' });
        if (
          (
            await client.query(
              'SELECT count(*)::int AS count FROM community_clubs WHERE owner_uid=$1',
              [uid],
            )
          ).rows[0].count >= 20
        )
          throw new HttpException({ code: 'CLUB_LIMIT' }, 429);
        await client.query(
          'INSERT INTO community_clubs(id,owner_uid,universe_id,name,description) VALUES($1,$2,$3,$4,$5)',
          [id, uid, input.universeID, input.name, input.description],
        );
        await client.query(
          'INSERT INTO club_members(club_id,firebase_uid) VALUES($1,$2)',
          [id, uid],
        );
      }
      return { id, saved: true };
    });
  }
  async membership(uid: string, id: string, joined: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const club = await this.club(client, uid, id);
      if (!joined && club.owner_uid === uid)
        throw new ConflictException({ code: 'CLUB_OWNER_CANNOT_LEAVE' });
      if (joined) {
        const existing = (
          await client.query(
            'SELECT 1 FROM club_members WHERE club_id=$1 AND firebase_uid=$2',
            [id, uid],
          )
        ).rowCount;
        if (
          !existing &&
          (
            await client.query(
              'SELECT count(*)::int AS count FROM club_members WHERE club_id=$1',
              [id],
            )
          ).rows[0].count >= 200
        )
          throw new ConflictException({ code: 'CLUB_FULL' });
        await client.query(
          'INSERT INTO club_members(club_id,firebase_uid) VALUES($1,$2) ON CONFLICT DO NOTHING',
          [id, uid],
        );
      } else {
        await client.query(
          'DELETE FROM club_members WHERE club_id=$1 AND firebase_uid=$2',
          [id, uid],
        );
        await client.query(
          'DELETE FROM club_progress p USING club_schedule s WHERE p.schedule_id=s.id AND s.club_id=$1 AND p.firebase_uid=$2',
          [id, uid],
        );
      }
      return { id, saved: true };
    });
  }
  async remove(uid: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      if (
        !(
          await client.query(
            'UPDATE community_clubs SET deleted_at=coalesce(deleted_at,now()) WHERE id=$1 AND owner_uid=$2 RETURNING id',
            [id, uid],
          )
        ).rowCount
      )
        throw new NotFoundException({ code: 'CLUB_UNAVAILABLE' });
      return { id, deleted: true };
    });
  }
  async schedule(
    uid: string,
    club: string,
    id: string,
    input: {
      itemID: string;
      startsOn: string;
      totalUnits: number;
      unitLabel: string;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const row = await this.club(client, uid, club, true);
      const old = (
        await client.query('SELECT * FROM club_schedule WHERE id=$1', [id])
      ).rows[0];
      if (old) {
        if (
          old.club_id !== club ||
          old.item_id !== input.itemID ||
          old.total_units !== input.totalUnits ||
          old.unit_label !== input.unitLabel ||
          old.starts_on.toISOString().slice(0, 10) !== input.startsOn
        )
          throw new ConflictException({ code: 'POST_CONFLICT' });
        return { id, saved: true };
      }
      if (
        !(
          await client.query(
            "SELECT 1 FROM catalog_items WHERE id=$1 AND universe_id=$2 AND status='published'",
            [input.itemID, row.universe_id],
          )
        ).rowCount
      )
        throw new BadRequestException({ code: 'INVALID_POST_CATALOG' });
      if (
        (
          await client.query(
            'SELECT count(*)::int AS count FROM club_schedule WHERE club_id=$1',
            [club],
          )
        ).rows[0].count >= 52
      )
        throw new ConflictException({ code: 'SCHEDULE_LIMIT' });
      if (
        (
          await client.query(
            'SELECT 1 FROM club_schedule WHERE club_id=$1 AND starts_on=$2',
            [club, input.startsOn],
          )
        ).rowCount
      )
        throw new ConflictException({ code: 'SCHEDULE_DATE_USED' });
      await client.query(
        'INSERT INTO club_schedule(id,club_id,item_id,starts_on,total_units,unit_label) VALUES($1,$2,$3,$4,$5,$6)',
        [
          id,
          club,
          input.itemID,
          input.startsOn,
          input.totalUnits,
          input.unitLabel,
        ],
      );
      return { id, saved: true };
    });
  }
  async removeSchedule(uid: string, club: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      await this.club(client, uid, club, true);
      await client.query(
        'DELETE FROM club_schedule WHERE id=$1 AND club_id=$2',
        [id, club],
      );
      return { id, deleted: true };
    });
  }
  async progress(uid: string, club: string, id: string, units: number) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      await this.club(client, uid, club, false, true);
      const row = (
        await client.query(
          'SELECT total_units FROM club_schedule WHERE id=$1 AND club_id=$2',
          [id, club],
        )
      ).rows[0];
      if (!row || units > row.total_units)
        throw new BadRequestException({ code: 'INVALID_PROGRESS' });
      await client.query(
        'INSERT INTO club_progress(schedule_id,firebase_uid,units) VALUES($1,$2,$3) ON CONFLICT(schedule_id,firebase_uid) DO UPDATE SET units=EXCLUDED.units',
        [id, uid, units],
      );
      return { id, saved: true };
    });
  }
  async members(uid: string, club: string, schedule?: string, after?: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      await this.club(client, uid, club, false, true);
      if (
        schedule &&
        !(
          await client.query(
            'SELECT 1 FROM club_schedule WHERE id=$1 AND club_id=$2',
            [schedule, club],
          )
        ).rowCount
      )
        throw new BadRequestException({ code: 'INVALID_PROGRESS' });
      const rows = (
        await client.query(
          `SELECT p.firebase_uid AS id,p.display_name AS name,'@'||p.username AS handle,p.avatar_color AS "avatarColor",p.avatar_id AS "avatarID",coalesce(pr.units,0) AS units
       FROM club_members m JOIN profiles p ON p.firebase_uid=m.firebase_uid LEFT JOIN club_progress pr ON pr.firebase_uid=m.firebase_uid AND pr.schedule_id=$3
       WHERE m.club_id=$2 AND p.deletion_requested_at IS NULL AND ${unblocked('$1', 'm.firebase_uid')} AND ($4::text IS NULL OR p.firebase_uid COLLATE "C">$4 COLLATE "C") ORDER BY p.firebase_uid COLLATE "C" LIMIT 31`,
          [uid, club, schedule ?? null, after ?? null],
        )
      ).rows;
      return {
        members: rows.slice(0, 30),
        nextCursor: rows.length > 30 ? rows[29].id : null,
      };
    });
  }
  async report(uid: string, id: string, reason: string, block: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const existing = await client.query(
        'SELECT 1 FROM club_reports WHERE reporter_uid=$1 AND club_id=$2',
        [uid, id],
      );
      const row = existing.rowCount
        ? (
            await client.query(
              'SELECT owner_uid FROM community_clubs WHERE id=$1',
              [id],
            )
          ).rows[0]
        : await this.club(client, uid, id);
      if (!row || row.owner_uid === uid)
        throw new BadRequestException({ code: 'INVALID_REPORT' });
      if (!existing.rowCount) {
        if ((await client.query(reportQuotaSQL, [uid])).rows[0].count >= 50)
          throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
        await client.query(
          'INSERT INTO club_reports(reporter_uid,club_id,reason) VALUES($1,$2,$3)',
          [uid, id, reason],
        );
      }
      if (block) await this.social.block(client, uid, row.owner_uid);
      return { id, saved: true };
    });
  }
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
