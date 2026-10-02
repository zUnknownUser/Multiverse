import {
  BadRequestException,
  ConflictException,
  HttpException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService, type FeedCursor } from '../social/social.service.js';
import {
  postRelations,
  postVisible,
  postCommentVisible,
  reportQuotaSQL,
} from './community-policy.js';
import { reactionSummaries } from '../social/interaction-summary.js';
export interface PostInput {
  universeID: string;
  itemID: string | null;
  title: string;
  text: string;
  spoiler: boolean;
}
@Injectable()
export class CommunityService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  async list(
    uid: string,
    filter: {
      universe?: string;
      item?: string;
      id?: string;
      cursor?: FeedCursor;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const result = await client.query(
        `SELECT r.id,r.firebase_uid AS "user",r.universe_id AS "universeID",r.item_id AS "itemID",r.title,r.text,r.spoiler,r.created_at AS "createdAt",
   p.display_name AS name,p.username,p.avatar_color AS "avatarColor",
   to_char(r.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime",
   (SELECT count(*)::int FROM post_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.post_id=r.id AND ${postCommentVisible}) AS "commentCount"
   FROM ${postRelations} WHERE ${postVisible}
   AND ($2::text IS NULL OR r.universe_id=$2) AND ($3::text IS NULL OR r.item_id=$3)
   AND ($4::uuid IS NULL OR r.id=$4)
   AND ($5::timestamptz IS NULL OR (r.created_at,r.id)<($5::timestamptz,$6::uuid))
   ORDER BY r.created_at DESC,r.id DESC LIMIT 31`,
        [
          uid,
          filter.universe ?? null,
          filter.item ?? null,
          filter.id ?? null,
          filter.cursor?.time ?? null,
          filter.cursor?.id ?? null,
        ],
      );
      if (filter.id && !result.rowCount)
        throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      const rows = result.rows.slice(0, 30),
        last = rows.at(-1);
      const summaries = await reactionSummaries(
        client,
        uid,
        rows.map((r) => r.id),
        'post',
      );
      return {
        posts: rows.map((r) => ({
          id: r.id,
          user: r.user,
          universeID: r.universeID,
          itemID: r.itemID,
          title: r.title,
          text: r.text,
          spoiler: r.spoiler,
          createdAt: r.createdAt,
          commentCount: r.commentCount,
          interaction: summaries.find((s) => s.id === r.id),
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
                bio: '',
                followers: null,
                badgeUniverse: '',
              },
            ]),
          ).values(),
        ],
        nextCursor:
          result.rows.length > 30
            ? Buffer.from(
                JSON.stringify({ time: last!.cursorTime, id: last!.id }),
              ).toString('base64url')
            : null,
      };
    });
  }
  async publish(uid: string, id: string, input: PostInput) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const old = (
        await client.query('SELECT * FROM community_posts WHERE id=$1', [id])
      ).rows[0];
      if (old) {
        if (
          old.firebase_uid !== uid ||
          old.universe_id !== input.universeID ||
          old.item_id !== input.itemID ||
          old.title !== input.title ||
          old.text !== input.text ||
          old.spoiler !== input.spoiler
        )
          throw new ConflictException({ code: 'POST_CONFLICT' });
        return { id, saved: true };
      }
      const catalog = await client.query(
        `SELECT 1 FROM catalog_universes u WHERE u.id=$1 AND u.status='active'
   AND ($2::text IS NULL OR EXISTS(SELECT 1 FROM catalog_items i WHERE i.id=$2 AND i.universe_id=u.id AND i.status='published'))`,
        [input.universeID, input.itemID],
      );
      if (!catalog.rowCount)
        throw new BadRequestException({ code: 'INVALID_POST_CATALOG' });
      const quota = await client.query(
        "SELECT count(*)::int AS count FROM community_posts WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour'",
        [uid],
      );
      if (quota.rows[0].count >= 10)
        throw new HttpException({ code: 'POST_LIMIT' }, 429);
      try {
        await client.query(
          'INSERT INTO community_posts(id,firebase_uid,universe_id,item_id,title,text,spoiler) VALUES($1,$2,$3,$4,$5,$6,$7)',
          [
            id,
            uid,
            input.universeID,
            input.itemID,
            input.title,
            input.text,
            input.spoiler,
          ],
        );
      } catch (error) {
        if ((error as { code?: string }).code === '23505')
          throw new ConflictException({ code: 'POST_CONFLICT' });
        throw error;
      }
      return { id, saved: true };
    });
  }
  async remove(uid: string, id: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const result = await client.query(
        'UPDATE community_posts SET deleted_at=coalesce(deleted_at,now()) WHERE id=$1 AND firebase_uid=$2 RETURNING id',
        [id, uid],
      );
      if (!result.rowCount)
        throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      return { id, deleted: true };
    });
  }
  async report(uid: string, id: string, reason: string, alsoBlock: boolean) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const existing = await client.query(
        'SELECT 1 FROM post_reports WHERE reporter_uid=$1 AND post_id=$2',
        [uid, id],
      );
      const row = (
        existing.rowCount
          ? await client.query(
              'SELECT firebase_uid FROM community_posts WHERE id=$1',
              [id],
            )
          : await client.query(
              `SELECT r.firebase_uid FROM ${postRelations} WHERE r.id=$2 AND ${postVisible}`,
              [uid, id],
            )
      ).rows[0];
      if (!row) throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      if (row.firebase_uid === uid)
        throw new BadRequestException({ code: 'INVALID_REPORT' });
      if (!existing.rowCount) {
        if ((await client.query(reportQuotaSQL, [uid])).rows[0].count >= 50)
          throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
        await client.query(
          'INSERT INTO post_reports(reporter_uid,post_id,reason) VALUES($1,$2,$3)',
          [uid, id, reason],
        );
      }
      if (alsoBlock) await this.social.block(client, uid, row.firebase_uid);
      return {
        reported: true,
        reviewID: id,
        blockedUserID: alsoBlock ? row.firebase_uid : null,
      };
    });
  }
}
