import type { PoolClient } from 'pg';

export async function operationsReport(
  client: Pick<PoolClient, 'query'>,
  expected: { environment: string; project: string },
) {
  await client.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  try {
    const identity = await client.query<{
      environment: string;
      firebase_project_id: string;
    }>(
      'SELECT environment, firebase_project_id FROM deployment_identity WHERE singleton=true',
    );
    if (
      identity.rows.length !== 1 ||
      identity.rows[0].environment !== expected.environment ||
      identity.rows[0].firebase_project_id !== expected.project
    )
      throw new Error('OPERATIONS_ENVIRONMENT_MISMATCH');

    const deletions = (
      await client.query<{
        pending: number;
        attempted: number;
        olderThan15Minutes: number;
        oldestPendingAgeSeconds: number | null;
      }>(`SELECT count(*)::int AS pending,
        count(*) FILTER (WHERE last_attempt_at IS NOT NULL)::int AS attempted,
        count(*) FILTER (WHERE requested_at<now()-interval '15 minutes')::int AS "olderThan15Minutes",
        CASE WHEN count(*)>0 THEN greatest(0, floor(extract(epoch FROM now()-min(requested_at))))::int END AS "oldestPendingAgeSeconds"
        FROM account_deletions WHERE completed_at IS NULL`)
    ).rows[0];
    const push = (
      await client.query<{
        pending: number;
        due: number;
        retried: number;
        dueOver15Minutes: number;
        oldestDueAgeSeconds: number | null;
      }>(`SELECT count(*)::int AS pending,
        count(*) FILTER (WHERE push_after<=now())::int AS due,
        count(*) FILTER (WHERE push_attempts>0)::int AS retried,
        count(*) FILTER (WHERE push_after<now()-interval '15 minutes')::int AS "dueOver15Minutes",
        CASE WHEN count(*) FILTER (WHERE push_after<=now())>0 THEN greatest(0, floor(extract(epoch FROM now()-min(push_after) FILTER (WHERE push_after<=now()))))::int END AS "oldestDueAgeSeconds"
        FROM notifications WHERE push_state='pending'`)
    ).rows[0];
    const voice = (
      await client.query<{
        expiredOrRevoked: number;
        staleOver5Minutes: number;
      }>(`SELECT count(*)::int AS "expiredOrRevoked",
        count(*) FILTER (WHERE least(expires_at,revoked_at)<now()-interval '5 minutes')::int AS "staleOver5Minutes"
        FROM room_voice_sessions WHERE expires_at<=now() OR revoked_at IS NOT NULL`)
    ).rows[0];
    const { checkedAt } = (
      await client.query<{ checkedAt: Date }>('SELECT now() AS "checkedAt"')
    ).rows[0];
    await client.query('COMMIT');
    return {
      environment: expected.environment,
      checkedAt: checkedAt.toISOString(),
      attentionRequired:
        deletions.olderThan15Minutes > 0 ||
        push.dueOver15Minutes > 0 ||
        voice.staleOver5Minutes > 0,
      deletions,
      push,
      voice,
    };
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}
