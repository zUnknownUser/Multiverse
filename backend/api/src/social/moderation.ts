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
    ) queue ORDER BY "oldestReport","targetType","targetID" LIMIT 50`);
  return result.rows;
}

export interface ModerationDecision {
  id: string;
  targetType: 'review' | 'comment';
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
    !['review', 'comment'].includes(input.targetType) ||
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
  const table = input.targetType === 'review' ? 'reviews' : 'review_comments';
  const reports =
    input.targetType === 'review' ? 'review_reports' : 'comment_reports';
  const key = input.targetType === 'review' ? 'review_id' : 'comment_id';
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
