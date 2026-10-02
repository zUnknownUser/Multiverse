import type { PoolClient } from 'pg';
import { unblocked } from './social-policy.js';

export async function reactionSummaries(
  client: PoolClient,
  uid: string,
  targets: string[],
  domain: 'review' | 'post' = 'review',
) {
  const result = await client.query(
    `SELECT sr.target_id AS id,
    count(*) FILTER(WHERE sr.liked)::int AS likes,
    coalesce(bool_or(sr.liked) FILTER(WHERE sr.firebase_uid=$1),false) AS liked,
    max(sr.reaction) FILTER(WHERE sr.firebase_uid=$1) AS "myReaction",
    count(*) FILTER(WHERE sr.reaction='POW!')::int AS "POW!",
    count(*) FILTER(WHERE sr.reaction='ZAP!')::int AS "ZAP!",
    count(*) FILTER(WHERE sr.reaction='KRAK!')::int AS "KRAK!",
    count(*) FILTER(WHERE sr.reaction='HEH')::int AS "HEH"
    FROM ${domain === 'post' ? 'post_reactions' : 'social_reactions'} sr JOIN profiles rp ON rp.firebase_uid=sr.firebase_uid
    JOIN ${domain === 'post' ? 'community_posts' : 'reviews'} r ON r.id=sr.${domain === 'post' ? 'post_id' : 'review_id'}
    LEFT JOIN ${domain === 'post' ? 'post_comments' : 'review_comments'} c ON c.id=sr.comment_id
    WHERE sr.target_id=ANY($2::uuid[]) AND rp.deletion_requested_at IS NULL
    AND ${unblocked('$1', 'sr.firebase_uid')} AND ${unblocked('r.firebase_uid', 'sr.firebase_uid')}
    AND (c.id IS NULL OR ${unblocked('c.firebase_uid', 'sr.firebase_uid')})
    GROUP BY sr.target_id`,
    [uid, targets],
  );
  return targets.map((id) => {
    const row = result.rows.find((r) => r.id === id);
    return {
      id,
      likes: row?.likes ?? 0,
      liked: row?.liked ?? false,
      myReaction: row?.myReaction ?? null,
      reactions: Object.fromEntries(
        ['POW!', 'ZAP!', 'KRAK!', 'HEH'].map((type) => [
          type,
          row?.[type] ?? 0,
        ]),
      ),
    };
  });
}
