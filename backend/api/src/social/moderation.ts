import type { PoolClient } from 'pg';

export async function moderationQueue(client: PoolClient) {
  const result = await client.query(`SELECT * FROM (
    SELECT 'review' AS "targetType",r.id AS "targetID",r.text,r.spoiler,r.moderation_status AS visibility,
      count(*)::int AS reports,array_agg(DISTINCT rr.reason) AS reasons,min(rr.created_at) AS "oldestReport"
      FROM review_reports rr JOIN reviews r ON r.id=rr.review_id WHERE rr.status='pending' GROUP BY r.id
    UNION ALL
    SELECT 'comment',c.id,c.text,c.spoiler,c.moderation_status,
      count(*)::int,array_agg(DISTINCT cr.reason),min(cr.created_at)
      FROM comment_reports cr JOIN review_comments c ON c.id=cr.comment_id WHERE cr.status='pending' GROUP BY c.id
    UNION ALL
    SELECT 'post',r.id,r.text,r.spoiler,r.moderation_status,count(*)::int,array_agg(DISTINCT pr.reason),min(pr.created_at)
    FROM post_reports pr JOIN community_posts r ON r.id=pr.post_id WHERE pr.status='pending' GROUP BY r.id
    UNION ALL
    SELECT 'post_comment',c.id,c.text,c.spoiler,c.moderation_status,count(*)::int,array_agg(DISTINCT cr.reason),min(cr.created_at)
    FROM post_comment_reports cr JOIN post_comments c ON c.id=cr.comment_id WHERE cr.status='pending' GROUP BY c.id
    UNION ALL
    SELECT 'club',cl.id,cl.name || E'\\n' || cl.description,false,cl.moderation_status,count(*)::int,array_agg(DISTINCT cr.reason),min(cr.created_at) FROM club_reports cr JOIN community_clubs cl ON cl.id=cr.club_id WHERE cr.status='pending' GROUP BY cl.id
    UNION ALL
    SELECT 'message',m.id,m.text,m.spoiler,m.moderation_status,count(*)::int,array_agg(DISTINCT dr.reason),min(dr.created_at)
    FROM dm_reports dr JOIN dm_messages m ON m.id=dr.message_id WHERE dr.status='pending' GROUP BY m.id
    ) queue ORDER BY "oldestReport","targetType","targetID" LIMIT 50`);
  return result.rows;
}

export interface ModerationDecision {
  id: string;
  targetType:
    'review' | 'comment' | 'post' | 'post_comment' | 'club' | 'message';
  targetID: string;
  action: 'hide' | 'dismiss' | 'restore';
  operator: string;
  reason: string;
}
// Call only inside a transaction using an administrative database connection.
// This capability is deliberately not registered as a public HTTP controller.
export async function moderate(client: PoolClient, input: ModerationDecision) {
  const uuid =
    /^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i;
  if (
    !uuid.test(input.id) ||
    !uuid.test(input.targetID) ||
    !['review', 'comment', 'post', 'post_comment', 'club', 'message'].includes(
      input.targetType,
    ) ||
    !['hide', 'dismiss', 'restore'].includes(input.action) ||
    !input.operator.trim() ||
    input.operator.length > 128 ||
    !input.reason.trim() ||
    input.reason.length > 1000
  )
    throw new Error('INVALID_MODERATION_DECISION');
  await client.query('SELECT pg_advisory_xact_lock(1297502532,hashtext($1))', [
    input.id,
  ]);
  const existing = await client.query(
    'SELECT * FROM moderation_decisions WHERE id=$1',
    [input.id],
  );
  if (existing.rowCount) {
    const row = existing.rows[0];
    if (
      row.target_type !== input.targetType ||
      row.target_id !== input.targetID ||
      row.action !== input.action ||
      row.operator !== input.operator ||
      row.reason !== input.reason
    )
      throw new Error('DECISION_CONFLICT');
    return { id: input.id, applied: true };
  }
  const [table, reports, key] = {
    review: ['reviews', 'review_reports', 'review_id'],
    comment: ['review_comments', 'comment_reports', 'comment_id'],
    post: ['community_posts', 'post_reports', 'post_id'],
    post_comment: ['post_comments', 'post_comment_reports', 'comment_id'],
    club: ['community_clubs', 'club_reports', 'club_id'],
    message: ['dm_messages', 'dm_reports', 'message_id'],
  }[input.targetType];
  const target = await client.query(
    `SELECT 1 FROM ${table} WHERE id=$1 FOR UPDATE`,
    [input.targetID],
  );
  if (!target.rowCount) throw new Error('TARGET_UNAVAILABLE');
  if (input.action !== 'dismiss')
    await client.query(`UPDATE ${table} SET moderation_status=$2 WHERE id=$1`, [
      input.targetID,
      input.action === 'hide' ? 'hidden' : 'visible',
    ]);
  await client.query(
    `UPDATE ${reports} SET status='reviewed' WHERE ${key}=$1 AND status='pending'`,
    [input.targetID],
  );
  await client.query(
    'INSERT INTO moderation_decisions(id,target_type,target_id,action,operator,reason) VALUES($1,$2,$3,$4,$5,$6)',
    [
      input.id,
      input.targetType,
      input.targetID,
      input.action,
      input.operator,
      input.reason,
    ],
  );
  return { id: input.id, applied: true };
}
