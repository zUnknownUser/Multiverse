import { BadRequestException } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { unblocked } from '../social/social-policy.js';
import { recordNotification } from '../notifications/notification-events.js';

export async function saveMentions(
  client: PoolClient,
  uid: string,
  post: string,
  text: string,
  comment?: string,
) {
  const handles = [
    ...new Set(
      [...text.matchAll(/(?:^|[^\w@])@([a-zA-Z0-9_.]{3,24})\b/g)].map((m) =>
        m[1].toLowerCase(),
      ),
    ),
  ];
  if (handles.length > 10)
    throw new BadRequestException({ code: 'MENTION_LIMIT' });
  const users = await client.query(
    `SELECT p.firebase_uid FROM profiles p JOIN onboarding o USING(firebase_uid)
    WHERE lower(p.username)=ANY($2::text[]) AND o.completed AND p.deletion_requested_at IS NULL
    AND ${unblocked('$1', 'p.firebase_uid')}`,
    [uid, handles],
  );
  await client.query(
    'DELETE FROM community_mentions WHERE post_id=$1 AND comment_id IS NOT DISTINCT FROM $2::uuid',
    [post, comment ?? null],
  );
  for (const user of users.rows) {
    await client.query(
      'INSERT INTO community_mentions(post_id,comment_id,recipient_uid) VALUES($1,$2,$3)',
      [post, comment ?? null, user.firebase_uid],
    );
    await recordNotification(
      client,
      user.firebase_uid,
      uid,
      'mention',
      'post',
      post,
      comment,
    );
  }
}
export function mentionsField(comment = false) {
  return `coalesce((SELECT json_agg(json_build_object('id',mp.firebase_uid,'handle','@'||mp.username) ORDER BY mp.username)
    FROM community_mentions m JOIN profiles mp ON mp.firebase_uid=m.recipient_uid
    WHERE m.post_id=r.id AND ${comment ? 'm.comment_id=c.id' : 'm.comment_id IS NULL'}
    AND mp.deletion_requested_at IS NULL AND ${unblocked('$1', 'mp.firebase_uid')}),'[]'::json) AS mentions`;
}
