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
import { SocialService, type FeedCursor } from './social.service.js';
import {
  reviewRelations,
  reviewVisible,
  commentVisible,
} from './social-policy.js';
import {
  postRelations,
  postVisible,
  postCommentVisible,
  reportQuotaSQL,
} from '../community/community-policy.js';
import { recordNotification } from '../notifications/notification-events.js';
import { reactionSummaries } from './interaction-summary.js';

@Injectable()
export class InteractionsService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}

  private domain: 'review' | 'post' = 'review';
  forPosts() {
    const service = new InteractionsService(this.lifecycle, this.social);
    service.domain = 'post';
    return service;
  }
  private get tables() {
    return this.domain === 'post'
      ? {
          parents: 'community_posts',
          comments: 'post_comments',
          reactions: 'post_reactions',
          reports: 'post_comment_reports',
          key: 'post_id',
          relations: postRelations,
          visible: postVisible,
          commentVisible: postCommentVisible,
        }
      : {
          parents: 'reviews',
          comments: 'review_comments',
          reactions: 'social_reactions',
          reports: 'comment_reports',
          key: 'review_id',
          relations: reviewRelations,
          visible: reviewVisible,
          commentVisible,
        };
  }
  private async review(client: PoolClient, uid: string, id: string) {
    await this.social.member(client, uid);
    const result = await client.query(
      `SELECT r.firebase_uid,p.comment_permission FROM ${this.tables.relations}
      WHERE r.id=$2 AND ${this.tables.visible} FOR SHARE OF p,r`,
      [uid, id],
    );
    if (!result.rowCount)
      throw new NotFoundException({
        code:
          this.domain === 'post' ? 'POST_UNAVAILABLE' : 'REVIEW_UNAVAILABLE',
      });
    return result.rows[0] as {
      firebase_uid: string;
      comment_permission: string;
    };
  }
  private async canComment(
    client: PoolClient,
    uid: string,
    review: { firebase_uid: string; comment_permission: string },
  ) {
    if (uid === review.firebase_uid) return true;
    if (review.comment_permission === 'everyone') return true;
    if (review.comment_permission === 'nobody') return false;
    return !!(
      await client.query(
        'SELECT 1 FROM visible_follows WHERE follower_uid=$1 AND followed_uid=$2',
        [review.firebase_uid, uid],
      )
    ).rowCount;
  }
  private async comment(
    client: PoolClient,
    uid: string,
    reviewID: string,
    id: string,
  ) {
    const result = await client.query(
      `SELECT c.* FROM ${this.tables.comments} c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid
      JOIN ${this.tables.parents} r ON r.id=c.${this.tables.key} WHERE c.id=$3 AND c.${this.tables.key}=$2 AND ${this.tables.commentVisible} FOR SHARE OF c,cp`,
      [uid, reviewID, id],
    );
    if (!result.rowCount)
      throw new NotFoundException({ code: 'COMMENT_UNAVAILABLE' });
    return result.rows[0];
  }
  async permission(uid: string, permission: string) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      const member = await this.social.member(client, uid);
      await client.query(
        'UPDATE profiles SET comment_permission=$2 WHERE firebase_uid=$1',
        [uid, permission],
      );
      return {
        publicDiary: member.public_diary,
        commentPermission: permission,
      };
    });
  }
  async comments(uid: string, reviewID: string, cursor?: FeedCursor) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      const review = await this.review(client, uid, reviewID);
      const result = await client.query(
        `SELECT c.id,c.firebase_uid AS "user",c.text,c.spoiler,c.created_at AS "createdAt",
        to_char(c.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime",
        cp.display_name AS name,cp.username,cp.avatar_color AS "avatarColor"
        FROM ${this.tables.comments} c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid JOIN ${this.tables.parents} r ON r.id=c.${this.tables.key}
        WHERE c.${this.tables.key}=$2 AND ${this.tables.commentVisible}
        AND ($3::timestamptz IS NULL OR (c.created_at,c.id)>($3::timestamptz,$4::uuid))
        ORDER BY c.created_at,c.id LIMIT 31`,
        [uid, reviewID, cursor?.time ?? null, cursor?.id ?? null],
      );
      const rows = result.rows.slice(0, 30),
        last = rows.at(-1);
      const summaries = await reactionSummaries(
        client,
        uid,
        rows.map((row) => row.id),
        this.domain,
      );
      return {
        reviewID,
        canComment: await this.canComment(client, uid, review),
        comments: rows.map((row) => ({
          id: row.id,
          user: row.user,
          text: row.text,
          spoiler: row.spoiler,
          createdAt: row.createdAt,
          interaction: summaries.find((s) => s.id === row.id),
        })),
        users: [
          ...new Map(
            rows.map((row) => [
              row.user,
              {
                id: row.user,
                name: row.name,
                handle: '@' + row.username,
                avatarColor: row.avatarColor,
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
  async post(
    uid: string,
    reviewID: string,
    id: string,
    text: string,
    spoiler: boolean,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      const review = await this.review(client, uid, reviewID);
      const existing = await client.query(
        `SELECT * FROM ${this.tables.comments} WHERE id=$1`,
        [id],
      );
      if (existing.rowCount) {
        const row = existing.rows[0];
        if (
          row.firebase_uid !== uid ||
          row[this.tables.key] !== reviewID ||
          row.text !== text ||
          row.spoiler !== spoiler
        )
          throw new ConflictException({ code: 'COMMENT_CONFLICT' });
        // A retry acknowledges the saved comment, never republishes hidden content.
        return { reviewID, commentID: id, saved: true };
      }
      if (!(await this.canComment(client, uid, review)))
        throw new ForbiddenException({ code: 'COMMENTS_RESTRICTED' });
      const count = await client.query(
        `SELECT ((SELECT count(*) FROM review_comments WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour')+
        (SELECT count(*) FROM post_comments WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour'))::int AS count`,
        [uid],
      );
      if (count.rows[0].count >= 30)
        throw new HttpException({ code: 'COMMENT_LIMIT' }, 429);
      try {
        await client.query(
          `INSERT INTO ${this.tables.comments}(id,${this.tables.key},firebase_uid,text,spoiler) VALUES($1,$2,$3,$4,$5)`,
          [id, reviewID, uid, text, spoiler],
        );
      } catch (error) {
        if ((error as { code?: string }).code === '23505')
          throw new ConflictException({ code: 'COMMENT_CONFLICT' });
        throw error;
      }
      await recordNotification(
        client,
        review.firebase_uid,
        uid,
        'comment',
        this.domain,
        reviewID,
        id,
      );
      return { reviewID, commentID: id, saved: true };
    });
  }
  async react(
    uid: string,
    reviewID: string,
    commentID: string | undefined,
    reaction: string | null,
    liked: boolean,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      const owner = await this.review(client, uid, reviewID);
      const comment = commentID
        ? await this.comment(client, uid, reviewID, commentID)
        : undefined;
      const target = commentID ?? reviewID;
      const existing = await client.query(
        `SELECT reaction,liked FROM ${this.tables.reactions} WHERE target_id=$1 AND firebase_uid=$2`,
        [target, uid],
      );
      if (
        !existing.rowCount ||
        existing.rows[0].reaction !== reaction ||
        existing.rows[0].liked !== liked
      ) {
        const quota = await client.query(
          `INSERT INTO social_reaction_limits(firebase_uid,window_start,requests)
          VALUES($1,date_trunc('minute',now()),1) ON CONFLICT(firebase_uid) DO UPDATE SET
          window_start=date_trunc('minute',now()),
          requests=CASE WHEN social_reaction_limits.window_start<date_trunc('minute',now()) THEN 1 ELSE social_reaction_limits.requests+1 END
          WHERE social_reaction_limits.window_start<date_trunc('minute',now()) OR social_reaction_limits.requests<120
          RETURNING requests`,
          [uid],
        );
        if (!quota.rowCount)
          throw new HttpException({ code: 'REACTION_LIMIT' }, 429);
        await client.query(
          `INSERT INTO ${this.tables.reactions}(target_id,${this.tables.key},comment_id,firebase_uid,reaction,liked) VALUES($1,$2,$3,$4,$5,$6)
          ON CONFLICT(target_id,firebase_uid) DO UPDATE SET reaction=EXCLUDED.reaction,liked=EXCLUDED.liked,updated_at=now()`,
          [target, reviewID, commentID ?? null, uid, reaction, liked],
        );
      }
      if (reaction || liked)
        await recordNotification(
          client,
          comment?.firebase_uid ?? owner.firebase_uid,
          uid,
          'reaction',
          this.domain,
          reviewID,
          commentID,
        );
      return (await reactionSummaries(client, uid, [target], this.domain))[0];
    });
  }
  async reportComment(
    uid: string,
    reviewID: string,
    id: string,
    reason: string,
    alsoBlock: boolean,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const existing = await client.query(
        `SELECT 1 FROM ${this.tables.reports} WHERE reporter_uid=$1 AND comment_id=$2`,
        [uid, id],
      );
      let comment;
      if (existing.rowCount) {
        comment = (
          await client.query(
            `SELECT firebase_uid FROM ${this.tables.comments} WHERE id=$1 AND ${this.tables.key}=$2`,
            [id, reviewID],
          )
        ).rows[0];
        if (!comment)
          throw new NotFoundException({ code: 'COMMENT_UNAVAILABLE' });
      } else {
        await this.review(client, uid, reviewID);
        comment = await this.comment(client, uid, reviewID, id);
      }
      if (comment.firebase_uid === uid)
        throw new BadRequestException({ code: 'INVALID_REPORT' });
      if (!existing.rowCount) {
        const count = await client.query(reportQuotaSQL, [uid]);
        if (Number(count.rows[0].count) >= 50)
          throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
        await client.query(
          `INSERT INTO ${this.tables.reports}(reporter_uid,comment_id,reason) VALUES($1,$2,$3)`,
          [uid, id, reason],
        );
      }
      if (alsoBlock) await this.social.block(client, uid, comment.firebase_uid);
      return {
        reported: true,
        reviewID,
        commentID: id,
        blockedUserID: alsoBlock ? comment.firebase_uid : null,
      };
    });
  }
}
