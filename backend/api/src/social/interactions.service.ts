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
import { reactionSummaries } from './interaction-summary.js';

@Injectable()
export class InteractionsService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}

  private async review(client: PoolClient, uid: string, id: string) {
    await this.social.member(client, uid);
    const result = await client.query(
      `SELECT r.firebase_uid,p.comment_permission FROM ${reviewRelations}
      WHERE r.id=$2 AND ${reviewVisible} FOR SHARE OF p,r`,
      [uid, id],
    );
    if (!result.rowCount)
      throw new NotFoundException({ code: 'REVIEW_UNAVAILABLE' });
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
      `SELECT c.* FROM review_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid
      JOIN reviews r ON r.id=c.review_id WHERE c.id=$3 AND c.review_id=$2 AND ${commentVisible} FOR SHARE OF c,cp`,
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
        FROM review_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid JOIN reviews r ON r.id=c.review_id
        WHERE c.review_id=$2 AND ${commentVisible}
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
        'SELECT * FROM review_comments WHERE id=$1',
        [id],
      );
      if (existing.rowCount) {
        const row = existing.rows[0];
        if (
          row.firebase_uid !== uid ||
          row.review_id !== reviewID ||
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
        "SELECT count(*)::int AS count FROM review_comments WHERE firebase_uid=$1 AND created_at>now()-interval '1 hour'",
        [uid],
      );
      if (count.rows[0].count >= 30)
        throw new HttpException({ code: 'COMMENT_LIMIT' }, 429);
      try {
        await client.query(
          'INSERT INTO review_comments(id,review_id,firebase_uid,text,spoiler) VALUES($1,$2,$3,$4,$5)',
          [id, reviewID, uid, text, spoiler],
        );
      } catch (error) {
        if ((error as { code?: string }).code === '23505')
          throw new ConflictException({ code: 'COMMENT_CONFLICT' });
        throw error;
      }
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
      await this.review(client, uid, reviewID);
      if (commentID) await this.comment(client, uid, reviewID, commentID);
      const target = commentID ?? reviewID;
      const existing = await client.query(
        'SELECT reaction,liked FROM social_reactions WHERE target_id=$1 AND firebase_uid=$2',
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
          `INSERT INTO social_reactions(target_id,review_id,comment_id,firebase_uid,reaction,liked) VALUES($1,$2,$3,$4,$5,$6)
          ON CONFLICT(target_id,firebase_uid) DO UPDATE SET reaction=EXCLUDED.reaction,liked=EXCLUDED.liked,updated_at=now()`,
          [target, reviewID, commentID ?? null, uid, reaction, liked],
        );
      }
      return (await reactionSummaries(client, uid, [target]))[0];
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
        'SELECT 1 FROM comment_reports WHERE reporter_uid=$1 AND comment_id=$2',
        [uid, id],
      );
      let comment;
      if (existing.rowCount) {
        comment = (
          await client.query(
            'SELECT firebase_uid FROM review_comments WHERE id=$1 AND review_id=$2',
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
        const count = await client.query(
          `SELECT (SELECT count(*) FROM comment_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours')+
          (SELECT count(*) FROM review_reports WHERE reporter_uid=$1 AND created_at>now()-interval '24 hours') AS count`,
          [uid],
        );
        if (Number(count.rows[0].count) >= 50)
          throw new HttpException({ code: 'REPORT_LIMIT' }, 429);
        await client.query(
          'INSERT INTO comment_reports(reporter_uid,comment_id,reason) VALUES($1,$2,$3)',
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
