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
import { saveMentions, mentionsField } from './mentions.js';
import {
  attachImages,
  validateContext,
  imageField,
  voteField,
  requireEditable,
  stale,
  type PostInput,
} from './community-content.js';
export type { PostInput } from './community-content.js';
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
      segment?: number;
      search?: string;
      feed?: string;
      kind?: string;
      club?: string;
      schedule?: string;
      language?: string;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const result = await client.query(
        `SELECT r.id,r.firebase_uid AS "user",r.universe_id AS "universeID",r.item_id AS "itemID",r.title,r.text,r.spoiler,r.created_at AS "createdAt",r.kind,r.segment,r.club_id AS "clubID",r.schedule_id AS "scheduleID",r.version,r.edited_at AS "editedAt",r.option_a AS "optionA",r.option_b AS "optionB",r.closes_at AS "closesAt",r.resolution,r.resolution_note AS "resolutionNote",${imageField},${voteField},${mentionsField()},
   p.display_name AS name,p.username,p.avatar_color AS "avatarColor",
   (SELECT (d.translations->$13) || jsonb_build_object('day',d.day::text) FROM daily_duels d WHERE d.post_id=r.id) AS editorial,
   to_char(r.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "cursorTime",
   (SELECT count(*)::int FROM post_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.post_id=r.id AND ${postCommentVisible}) AS "commentCount"
   FROM ${postRelations} WHERE ${postVisible}
   AND ($2::text IS NULL OR r.universe_id=$2) AND ($3::text IS NULL OR r.item_id=$3)
   AND ($4::uuid IS NULL OR r.id=$4)
   AND ($5::timestamptz IS NULL OR (r.created_at,r.id)<($5::timestamptz,$6::uuid))
   AND ($7::text='' OR to_tsvector('simple',r.title || ' ' || r.text) @@ plainto_tsquery('simple',$7) OR strpos(lower(r.title || ' ' || r.text),lower($7))>0
   OR EXISTS(SELECT 1 FROM daily_duels dd WHERE dd.post_id=r.id AND strpos(lower((dd.translations->$13->>'title') || ' ' || (dd.translations->$13->>'text')),lower($7))>0))
   AND ($8::text<>'following' OR EXISTS(SELECT 1 FROM visible_follows f WHERE f.follower_uid=$1 AND f.followed_uid=r.firebase_uid))
   AND ($8::text<>'active' OR (r.created_at>now()-interval '7 days' AND EXISTS(SELECT 1 FROM post_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.post_id=r.id AND ${postCommentVisible})))
   AND ($8::text<>'unanswered' OR NOT EXISTS(SELECT 1 FROM post_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.post_id=r.id AND ${postCommentVisible}))
   AND ($9::text IS NULL OR r.kind=$9)
   AND ($10::uuid IS NULL OR r.club_id=$10) AND ($11::uuid IS NULL OR r.schedule_id=$11)
   AND ($4::uuid IS NOT NULL OR $10::uuid IS NOT NULL OR r.club_id IS NULL)
   AND ($4::uuid IS NOT NULL OR $9::text='room' OR r.kind<>'room')
   AND ($12::int IS NULL OR r.segment=$12)
   ORDER BY r.created_at DESC,r.id DESC LIMIT 31`,
        [
          uid,
          filter.universe ?? null,
          filter.item ?? null,
          filter.id ?? null,
          filter.cursor?.time ?? null,
          filter.cursor?.id ?? null,
          filter.search ?? '',
          filter.feed ?? 'recent',
          filter.kind ?? null,
          filter.club ?? null,
          filter.schedule ?? null,
          filter.segment ?? null,
          filter.language ?? 'pt-BR',
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
          title: r.editorial?.title ?? r.title,
          text: r.editorial?.text ?? r.text,
          spoiler: r.spoiler,
          createdAt: r.createdAt,
          kind: r.kind,
          dailyDay: r.editorial?.day,
          segment: r.segment,
          clubID: r.clubID,
          scheduleID: r.scheduleID,
          version: r.version,
          editedAt: r.editedAt,
          images: r.images,
          mentions: r.mentions,
          votes: r.votes,
          optionA: r.editorial?.optionA ?? r.optionA,
          optionB: r.editorial?.optionB ?? r.optionB,
          closesAt: r.closesAt,
          resolution: r.resolution,
          resolutionNote: r.resolutionNote,
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
          old.spoiler !== input.spoiler ||
          old.segment !== (input.segment ?? 0) ||
          old.kind !== (input.kind ?? 'discussion') ||
          old.club_id !== (input.clubID ?? null) ||
          old.schedule_id !== (input.scheduleID ?? null) ||
          old.option_a !== (input.optionA ?? null) ||
          old.option_b !== (input.optionB ?? null) ||
          (old.closes_at?.toISOString() ?? null) !==
            (input.closesAt ? new Date(input.closesAt).toISOString() : null) ||
          JSON.stringify(
            (
              await client.query(
                'SELECT image_id FROM post_images WHERE post_id=$1 ORDER BY position',
                [id],
              )
            ).rows.map((r) => r.image_id),
          ) !== JSON.stringify(input.imageIDs ?? [])
        )
          throw new ConflictException({ code: 'POST_CONFLICT' });
        return { id, saved: true };
      }
      await validateContext(client, uid, input);
      const quota = await client.query(
        "SELECT count(*)::int AS count FROM community_posts WHERE firebase_uid=$1 AND (kind='room')=$2 AND created_at>now()-interval '1 hour'",
        [uid, input.kind === 'room'],
      );
      if (quota.rows[0].count >= (input.kind === 'room' ? 60 : 10))
        throw new HttpException({ code: 'POST_LIMIT' }, 429);
      try {
        await client.query(
          'INSERT INTO community_posts(id,firebase_uid,universe_id,item_id,title,text,spoiler,kind,club_id,schedule_id,option_a,option_b,closes_at,segment) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)',
          [
            id,
            uid,
            input.universeID,
            input.itemID,
            input.title,
            input.text,
            input.spoiler,
            input.kind ?? 'discussion',
            input.clubID ?? null,
            input.scheduleID ?? null,
            input.optionA ?? null,
            input.optionB ?? null,
            input.closesAt ?? null,
            input.segment ?? 0,
          ],
        );
      } catch (error) {
        if ((error as { code?: string }).code === '23505')
          throw new ConflictException({ code: 'POST_CONFLICT' });
        throw error;
      }
      await attachImages(client, uid, id, input.imageIDs ?? []);
      await saveMentions(client, uid, id, input.title + ' ' + input.text);
      return { id, saved: true };
    });
  }
  async edit(
    uid: string,
    id: string,
    input: {
      title: string;
      text: string;
      spoiler: boolean;
      imageIDs: string[];
      version: number;
      mutationID: string;
    },
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const old = await requireEditable(client, uid, id);
      if (old.edit_id === input.mutationID) {
        const images = (
          await client.query(
            'SELECT image_id FROM post_images WHERE post_id=$1 ORDER BY position',
            [id],
          )
        ).rows.map((r) => r.image_id);
        if (
          old.title !== input.title ||
          old.text !== input.text ||
          old.spoiler !== input.spoiler ||
          JSON.stringify(images) !== JSON.stringify(input.imageIDs)
        )
          throw new ConflictException({ code: 'POST_CONFLICT' });
        return { id, saved: true };
      }
      if (old.version !== input.version) throw stale();
      await attachImages(client, uid, id, input.imageIDs);
      await client.query(
        'UPDATE community_posts SET title=$2,text=$3,spoiler=$4,version=version+1,edited_at=now(),edit_id=$5 WHERE id=$1',
        [id, input.title, input.text, input.spoiler, input.mutationID],
      );
      await saveMentions(client, uid, id, input.title + ' ' + input.text);
      return { id, saved: true };
    });
  }
  async vote(uid: string, id: string, choice: number) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const post = (
        await client.query(
          `SELECT r.kind,r.closes_at,r.resolution FROM ${postRelations} WHERE r.id=$2 AND ${postVisible} FOR UPDATE OF r`,
          [uid, id],
        )
      ).rows[0];
      if (!post || !['duel', 'theory'].includes(post.kind))
        throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      const old = (
        await client.query(
          'SELECT choice FROM community_votes WHERE post_id=$1 AND firebase_uid=$2',
          [id, uid],
        )
      ).rows[0];
      if (old?.choice === choice) return { id, saved: true };
      if (
        post.resolution !== 'open' ||
        (post.closes_at && post.closes_at.getTime() <= Date.now())
      )
        throw new ConflictException({ code: 'VOTE_CLOSED' });
      await client.query(
        'INSERT INTO community_votes(post_id,firebase_uid,choice) VALUES($1,$2,$3) ON CONFLICT(post_id,firebase_uid) DO UPDATE SET choice=EXCLUDED.choice',
        [id, uid, choice],
      );
      return { id, saved: true };
    });
  }
  async resolve(
    uid: string,
    id: string,
    status: string,
    note: string,
    version: number,
  ) {
    return this.lifecycle.withActiveAccount(uid, async (client) => {
      await this.social.member(client, uid);
      const row = await requireEditable(client, uid, id);
      if (row.kind !== 'theory')
        throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
      if (row.resolution === status && row.resolution_note === note)
        return { id, saved: true };
      if (row.version !== version) throw stale();
      await client.query(
        'UPDATE community_posts SET resolution=$2,resolution_note=$3,version=version+1,edited_at=now() WHERE id=$1',
        [id, status, note],
      );
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
