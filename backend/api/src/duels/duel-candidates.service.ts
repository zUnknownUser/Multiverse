import {
  ConflictException,
  Inject,
  Injectable,
  NotFoundException,
  HttpException,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { AccountLifecycleService } from '../accounts/account-lifecycle.service.js';
import { SocialService } from '../social/social.service.js';
import { sourceEligible } from './duel-curation.js';

@Injectable()
export class DuelCandidatesService {
  constructor(
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
    @Inject(SocialService) private readonly social: SocialService,
  ) {}
  private async rows(c: PoolClient, uid: string, post?: string) {
    await c.query(
      `UPDATE duel_candidates q SET status='rejected',reason_code='source_changed',updated_at=now()
      WHERE q.submitter_uid=$1 AND q.status IN ('pending','approved') AND NOT EXISTS(
      SELECT 1 FROM community_posts r JOIN profiles p ON p.firebase_uid=r.firebase_uid JOIN onboarding o ON o.firebase_uid=p.firebase_uid
      WHERE r.id=q.source_post_id AND r.firebase_uid=q.submitter_uid AND r.version=q.source_version AND ${sourceEligible})`,
      [uid],
    );
    return (
      await c.query(
        `SELECT id,source_post_id AS "postID",snapshot->>'title' AS title,status,scheduled_on::text AS "scheduledOn",
      published_post_id AS "publishedPostID",reason_code AS "reasonCode" FROM duel_candidates WHERE submitter_uid=$1
      AND ($2::uuid IS NULL OR source_post_id=$2) ORDER BY created_at DESC,id DESC LIMIT 100`,
        [uid, post ?? null],
      )
    ).rows;
  }
  async mine(uid: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      return { items: await this.rows(c, uid) };
    });
  }
  async status(uid: string, post: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      return { candidate: (await this.rows(c, uid, post))[0] ?? null };
    });
  }
  async submit(uid: string, post: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await c.query('SELECT pg_advisory_xact_lock(1297502532,1)');
      const existing = (await this.rows(c, uid, post))[0];
      if (existing) return { candidate: existing };
      const r = (
        await c.query(
          `SELECT r.* FROM community_posts r JOIN profiles p ON p.firebase_uid=r.firebase_uid
        JOIN onboarding o ON o.firebase_uid=p.firebase_uid WHERE r.id=$1 AND r.firebase_uid=$2 AND ${sourceEligible} FOR SHARE OF r`,
          [post, uid],
        )
      ).rows[0];
      if (!r) throw new ConflictException({ code: 'DUEL_NOT_ELIGIBLE' });
      const quota = (
        await c.query(
          `SELECT count(*) FILTER(WHERE status IN ('pending','approved'))::int AS pending,
        count(*) FILTER(WHERE created_at>now()-interval '24 hours')::int AS recent FROM duel_candidates WHERE submitter_uid=$1`,
          [uid],
        )
      ).rows[0];
      if (quota.pending >= 3 || quota.recent >= 3)
        throw new HttpException({ code: 'DUEL_SUBMISSION_LIMIT' }, 429);
      await c.query(
        `INSERT INTO duel_candidates(origin,source_post_id,submitter_uid,source_version,snapshot,universe_id)
        VALUES('community',$1,$2,$3,$4,$5)`,
        [
          post,
          uid,
          r.version,
          {
            title: r.title,
            text: r.text,
            optionA: r.option_a,
            optionB: r.option_b,
          },
          r.universe_id,
        ],
      );
      return { candidate: (await this.rows(c, uid, post))[0] };
    });
  }
  async withdraw(uid: string, post: string) {
    return this.lifecycle.withActiveAccount(uid, async (c) => {
      await this.social.member(c, uid);
      await c.query('SELECT pg_advisory_xact_lock(1297502532,1)');
      const result = await c.query(
        `UPDATE duel_candidates SET status='withdrawn',scheduled_on=NULL,updated_at=now()
        WHERE submitter_uid=$1 AND source_post_id=$2 AND status IN ('pending','approved','withdrawn') RETURNING id`,
        [uid, post],
      );
      if (!result.rowCount)
        throw new NotFoundException({ code: 'CANDIDATE_UNAVAILABLE' });
      return { candidate: (await this.rows(c, uid, post))[0] };
    });
  }
}
