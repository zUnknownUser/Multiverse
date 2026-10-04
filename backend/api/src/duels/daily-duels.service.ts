import { randomUUID } from 'node:crypto';
import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
import {
  postRelations,
  postVisible,
  postCommentVisible,
} from '../community/community-policy.js';
import { voteField } from '../community/community-content.js';
import { unblocked } from '../social/social-policy.js';
import { dailyContent, EDITORIAL_UID } from './daily-duel-content.js';

@Injectable()
export class DailyDuelsService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}

  private async ensure(c: PoolClient) {
    const { day } = (
      await c.query(
        "SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD') AS day",
      )
    ).rows[0];
    if (
      (await c.query('SELECT 1 FROM daily_duels WHERE day=$1', [day])).rowCount
    )
      return;
    await c.query('SELECT pg_advisory_xact_lock(1297502532, 1)');
    if (
      (await c.query('SELECT 1 FROM daily_duels WHERE day=$1', [day])).rowCount
    )
      return;
    const content = dailyContent(day),
      pt = content.translations['pt-BR'];
    await c.query(
      `INSERT INTO profiles(firebase_uid,username,display_name,avatar_color,bio,comment_permission)
      VALUES($1,CASE WHEN EXISTS(SELECT 1 FROM profiles WHERE username='multiverse.editorial') THEN 'mv.'||left(replace(gen_random_uuid()::text,'-',''),20) ELSE 'multiverse.editorial' END,'Multiverse · Editorial','#F4A814','Curadoria editorial · Editorial team','everyone') ON CONFLICT(firebase_uid) DO NOTHING`,
      [EDITORIAL_UID],
    );
    await c.query(
      `INSERT INTO onboarding(firebase_uid,completed,universe_ids,step) VALUES($1,true,'{marvel,dc}',3) ON CONFLICT(firebase_uid) DO NOTHING`,
      [EDITORIAL_UID],
    );
    const id = randomUUID();
    await c.query(
      `INSERT INTO community_posts(id,firebase_uid,universe_id,title,text,kind,option_a,option_b,closes_at)
      VALUES($1,$2,$3,$4,$5,'duel',$6,$7,($8::date+1)::timestamp AT TIME ZONE 'UTC')`,
      [
        id,
        EDITORIAL_UID,
        content.universe,
        pt.title,
        pt.text,
        pt.optionA,
        pt.optionB,
        day,
      ],
    );
    await c.query(
      `INSERT INTO daily_duels(day,post_id,translations,opens_at) VALUES($1,$2,$3,$1::date::timestamp AT TIME ZONE 'UTC')`,
      [day, id, content.translations],
    );
  }

  private async round(
    c: PoolClient,
    uid: string,
    language: string,
    id?: string,
    previous = false,
  ) {
    const rows = (
      await c.query(
        `SELECT r.id, d.day::text, d.opens_at AS "opensAt",r.closes_at AS "closesAt",r.universe_id AS "universeID",
      d.translations->$2 AS content, ${voteField},
      (SELECT count(*)::int FROM post_comments c JOIN profiles cp ON cp.firebase_uid=c.firebase_uid WHERE c.post_id=r.id AND ${postCommentVisible}) AS "commentCount"
      FROM ${postRelations} JOIN daily_duels d ON d.post_id=r.id WHERE ${postVisible}
      AND ($3::uuid IS NULL OR r.id=$3)
      AND ($3::uuid IS NOT NULL OR d.day ${previous ? '<' : '='} (clock_timestamp() AT TIME ZONE 'UTC')::date)
      ORDER BY d.day DESC LIMIT 1`,
        [uid, language, id ?? null],
      )
    ).rows;
    const r = rows[0];
    return r
      ? {
          id: r.id,
          day: r.day,
          opensAt: r.opensAt,
          closesAt: r.closesAt,
          universeID: r.universeID,
          ...r.content,
          votes: r.votes,
          commentCount: r.commentCount,
        }
      : null;
  }

  private async progress(c: PoolClient, uid: string) {
    const result = (
      await c.query(
        `WITH days AS (
      SELECT d.day, row_number() OVER(ORDER BY d.day DESC)::int AS n
      FROM daily_duels d JOIN community_votes v ON v.post_id=d.post_id
      JOIN community_posts r ON r.id=d.post_id WHERE v.firebase_uid=$1 AND r.deleted_at IS NULL AND r.moderation_status='visible'
      AND v.created_at>=d.opens_at AND v.created_at<r.closes_at
    ), summary AS (SELECT count(*)::int AS total,
      (count(*) FILTER(WHERE day>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC')::date))::int AS month,
      max(day) AS latest FROM days)
    SELECT total,month*10 AS points,
      CASE WHEN latest>=(clock_timestamp() AT TIME ZONE 'UTC')::date-1
      THEN (SELECT count(*)::int FROM days WHERE day=summary.latest-(n-1)) ELSE 0 END AS streak FROM summary`,
        [uid],
      )
    ).rows[0];
    return {
      rounds: result.total,
      monthlyPoints: result.points,
      streak: result.streak,
    };
  }

  async current(uid: string, language: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await this.ensure(c);
      return {
        serverTime: new Date(),
        today: await this.round(c, uid, language),
        previous: await this.round(c, uid, language, undefined, true),
        progress: await this.progress(c, uid),
      };
    });
  }
  async detail(uid: string, id: string, language: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      const round = await this.round(c, uid, language, id);
      if (!round) throw new NotFoundException({ code: 'POST_UNAVAILABLE' });
      return {
        serverTime: new Date(),
        round,
        progress: await this.progress(c, uid),
      };
    });
  }
  async leaderboard(uid: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      const result = await c.query(
        `WITH scores AS (
        SELECT v.firebase_uid,count(*)::int*10 AS points FROM daily_duels d JOIN community_votes v ON v.post_id=d.post_id
        JOIN community_posts r ON r.id=d.post_id JOIN profiles p ON p.firebase_uid=v.firebase_uid
        JOIN onboarding o ON o.firebase_uid=p.firebase_uid AND o.completed
        WHERE d.day>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC')::date
        AND d.day<=(clock_timestamp() AT TIME ZONE 'UTC')::date AND v.created_at>=d.opens_at AND v.created_at<r.closes_at
        AND r.deleted_at IS NULL AND r.moderation_status='visible' AND p.deletion_requested_at IS NULL
        GROUP BY v.firebase_uid
      ), ranked AS (SELECT *,dense_rank() OVER(ORDER BY points DESC)::int AS rank FROM scores), people AS (
        SELECT rank,points,p.firebase_uid AS id,p.display_name AS name,'@'||p.username AS handle,p.avatar_color AS "avatarColor",p.avatar_id AS "avatarID"
        FROM ranked JOIN profiles p USING(firebase_uid) WHERE ${unblocked('$1', 'p.firebase_uid')})
      SELECT coalesce((SELECT json_agg(t) FROM (SELECT * FROM people ORDER BY rank,id LIMIT 30) t),'[]') AS leaders,
        (SELECT row_to_json(t) FROM (SELECT * FROM people WHERE id=$1) t) AS me,
        to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM') AS month`,
        [uid],
      );
      return result.rows[0];
    });
  }
}
