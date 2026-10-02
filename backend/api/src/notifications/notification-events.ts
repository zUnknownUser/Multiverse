import type { PoolClient } from 'pg';
// Called inside the source mutation transaction. A retry/toggle never creates another alert.
export async function recordNotification(
  client: PoolClient,
  recipient: string,
  actor: string,
  kind: 'follow' | 'comment' | 'reaction',
  type: 'person' | 'review' | 'post',
  target: string,
  comment?: string,
) {
  if (recipient === actor) return;
  await client.query(
    `INSERT INTO notifications(recipient_uid,actor_uid,kind,target_type,target_id,comment_id,push_state)
 SELECT $1::varchar,$2::varchar,$3::text,$4::text,$5::text,$6::uuid,CASE WHEN coalesce(np.push,false) THEN 'pending' ELSE 'skipped' END
 FROM profiles p LEFT JOIN notification_preferences np ON np.firebase_uid=p.firebase_uid
 WHERE p.firebase_uid=$1 AND p.deletion_requested_at IS NULL AND coalesce(np.activity,true)
 ON CONFLICT DO NOTHING`,
    [recipient, actor, kind, type, target, comment ?? null],
  );
}
