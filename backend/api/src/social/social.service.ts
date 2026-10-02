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
import {
  catalogDescription,
  descriptionSourceJoin,
} from '../catalog/catalog-description.js';
import {
  reviewRelations as relations,
  reviewVisible as visible,
  commentVisible,
} from './social-policy.js';
import { reactionSummaries } from './interaction-summary.js';

export interface FeedCursor {
  time: string;
  id: string;
}
const fields = `r.id,r.firebase_uid AS "user",d.item_id AS item,d.rating,r.text,r.spoiler,r.created_at AS "createdAt",
 to_char(r.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime"`;

@Injectable()
export class SocialService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}
  async member(client: PoolClient, uid: string) {
    const r = await client.query(
      `SELECT p.public_diary,p.comment_permission FROM profiles p JOIN onboarding o USING(firebase_uid)
   WHERE p.firebase_uid=$1 AND p.deletion_requested_at IS NULL AND o.completed=true FOR SHARE OF p`,
      [uid],
    );
    if (!r.rowCount)
      throw new ConflictException({ code: 'ONBOARDING_REQUIRED' });
    return r.rows[0];
  }
  async privacy(uid: string, publicDiary?: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      const member = await this.member(client, uid);
      if (publicDiary !== undefined)
        await client.query(
          'UPDATE profiles SET public_diary=$2 WHERE firebase_uid=$1',
          [uid, publicDiary],
        );
      return {
        publicDiary: publicDiary ?? member.public_diary,
        commentPermission: member.comment_permission,
      };
    });
  }
  async feed(
    uid: string,
    locale: string,
    limit: number,
    cursor?: FeedCursor,
    id?: string,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.member(client, uid);
      const result = await client.query(
        `SELECT ${fields} FROM ${relations} WHERE ${visible}
    AND ($2::uuid IS NULL OR r.id=$2)
    AND ($2::uuid IS NOT NULL OR p.firebase_uid=$1 OR EXISTS(SELECT 1 FROM visible_follows f WHERE f.follower_uid=$1 AND f.followed_uid=p.firebase_uid))
    AND ($3::timestamptz IS NULL OR (r.created_at,r.id)<($3::timestamptz,$4::uuid))
    ORDER BY r.created_at DESC,r.id DESC LIMIT $5`,
        [uid, id ?? null, cursor?.time ?? null, cursor?.id ?? null, limit + 1],
      );
      if (id && !result.rowCount)
        throw new NotFoundException({ code: 'REVIEW_UNAVAILABLE' });
      const rows = result.rows.slice(0, limit);
      const last = rows.at(-1);
      const nextCursor =
        result.rows.length > rows.length
          ? Buffer.from(
              JSON.stringify({ time: last!.cursorTime, id: last!.id }),
            ).toString('base64url')
          : null;
      const summaries = await reactionSummaries(
        client,
        uid,
        rows.map((row) => row.id),
      );
      const counts = await client.query(
        `SELECT c.review_id,count(*)::int AS count FROM review_comments c
        JOIN profiles cp ON cp.firebase_uid=c.firebase_uid JOIN reviews r ON r.id=c.review_id
        WHERE c.review_id=ANY($2::uuid[]) AND ${commentVisible} GROUP BY c.review_id`,
        [uid, rows.map((row) => row.id)],
      );
      const reviews = rows.map((row) => ({
        id: row.id,
        user: row.user,
        item: row.item,
        rating: row.rating,
        text: row.text,
        spoiler: row.spoiler,
        createdAt: row.createdAt,
        interaction: summaries.find((summary) => summary.id === row.id),
        commentCount:
          counts.rows.find((count) => count.review_id === row.id)?.count ?? 0,
      }));
      const itemIDs = [...new Set(rows.map((r) => r.item))];
      const authors = [...new Set(rows.map((r) => r.user))];
      const users = await client.query(
        `SELECT firebase_uid AS id,display_name AS name,'@'||username AS handle,
    avatar_color AS "avatarColor",bio,NULL AS followers,'' AS "badgeUniverse" FROM profiles WHERE firebase_uid=ANY($1::text[])`,
        [authors],
      );
      const items = await client.query(
        `SELECT i.id,i.universe_id AS uni,i.type,coalesce(t.title,p.title) AS title,
    coalesce(t.year,p.year) AS year,s.average AS avg,s.log_count AS "logCount",s.review_count AS "reviewCount",
    s.rating_histogram AS "ratingHistogram",coalesce(t.canon,p.canon) AS canon,${catalogDescription('$2')} AS "desc"
    FROM catalog_items i JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
    LEFT JOIN catalog_item_translations t ON t.item_id=i.id AND t.locale=$2 ${descriptionSourceJoin}
    JOIN catalog_item_statistics s ON s.item_id=i.id WHERE i.id=ANY($1::text[])`,
        [itemIDs, locale],
      );
      const universes = await client.query(
        `SELECT u.id,coalesce(t.name,p.name) AS name,u.color AS c,u.dark_color AS c2,
    u.ink_color AS ink,u.track,coalesce(t.canon,p.canon) AS canon,coalesce(t.tagline,p.tagline) AS tagline,
    0 AS base,0 AS total,0 AS members,0 AS live FROM catalog_universes u
    JOIN catalog_universe_translations p ON p.universe_id=u.id AND p.locale='pt-BR'
    LEFT JOIN catalog_universe_translations t ON t.universe_id=u.id AND t.locale=$2
    WHERE u.id IN (SELECT universe_id FROM catalog_items WHERE id=ANY($1::text[]))`,
        [itemIDs, locale],
      );
      return {
        reviews,
        users: users.rows,
        items: items.rows,
        universes: universes.rows,
        nextCursor,
      };
    });
  }
  async block(client: PoolClient, uid: string, target: string) {
    if (uid === target)
      throw new BadRequestException({ code: 'INVALID_BLOCK' });
    const person = await client.query(
      'SELECT 1 FROM profiles WHERE firebase_uid=$1 AND deletion_requested_at IS NULL FOR SHARE',
      [target],
    );
    if (!person.rowCount)
      throw new NotFoundException({ code: 'PERSON_UNAVAILABLE' });
    await client.query(
      'INSERT INTO user_blocks(blocker_uid,blocked_uid) VALUES($1,$2) ON CONFLICT DO NOTHING',
      [uid, target],
    );
  }
  async blocks(uid: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.member(client, uid);
      const r = await client.query(
        `SELECT p.firebase_uid AS id,'@'||p.username AS handle,b.created_at AS "createdAt"
    FROM user_blocks b JOIN profiles p ON p.firebase_uid=b.blocked_uid
    WHERE b.blocker_uid=$1 AND p.deletion_requested_at IS NULL ORDER BY b.created_at DESC,p.firebase_uid`,
        [uid],
      );
      return { users: r.rows };
    });
  }
  async setBlock(uid: string, target: string, blocked: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.member(client, uid);
      if (uid === target)
        throw new BadRequestException({ code: 'INVALID_BLOCK' });
      if (blocked) await this.block(client, uid, target);
      else
        await client.query(
          'DELETE FROM user_blocks WHERE blocker_uid=$1 AND blocked_uid=$2',
          [uid, target],
        );
      return { userID: target, blocked };
    });
  }
  async report(uid: string, id: string, reason: string, alsoBlock: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.member(client, uid);
      const existing = await client.query(
        'SELECT 1 FROM review_reports WHERE reporter_uid=$1 AND review_id=$2',
        [uid, id],
      );
      // Retried acknowledgements remain valid after the report hides the review or blocks its author.
      const review = existing.rowCount
        ? await client.query('SELECT firebase_uid FROM reviews WHERE id=$1', [
            id,
          ])
        : await client.query(
            `SELECT r.firebase_uid FROM ${relations} WHERE r.id=$2 AND ${visible}`,
            [uid, id],
          );
      if (!review.rowCount)
        throw new NotFoundException({ code: 'REVIEW_UNAVAILABLE' });
      const author = review.rows[0].firebase_uid;
      if (author === uid)
        throw new BadRequestException({ code: 'INVALID_REPORT' });
      if (!existing.rowCount) {
        const count = await client.query(
          "SELECT ((SELECT count(*) FROM review_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours') + (SELECT count(*) FROM comment_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours'))::int AS count",
          [uid],
        );
        if (count.rows[0].count >= 50)
          throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
        await client.query(
          'INSERT INTO review_reports(reporter_uid,review_id,reason) VALUES($1,$2,$3)',
          [uid, id, reason],
        );
      }
      if (alsoBlock) await this.block(client, uid, author);
      return {
        reported: true,
        reviewID: id,
        blockedUserID: alsoBlock ? author : null,
      };
    });
  }
}
