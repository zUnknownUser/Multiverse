import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';

export const sourceEligible = `r.kind='duel' AND r.deleted_at IS NULL AND r.moderation_status='visible'
 AND NOT r.spoiler AND r.club_id IS NULL AND r.segment=0
 AND p.deletion_requested_at IS NULL AND o.completed
 AND NOT EXISTS(SELECT 1 FROM daily_duels d WHERE d.post_id=r.id)
 AND (r.item_id IS NULL OR EXISTS(SELECT 1 FROM catalog_items i WHERE i.id=r.item_id AND i.status='published'))`;

export async function validSource(
  c: PoolClient,
  candidate: Record<string, unknown>,
) {
  if (candidate.origin === 'editorial') return true;
  const result = await c.query(
    `SELECT 1 FROM community_posts r JOIN profiles p ON p.firebase_uid=r.firebase_uid
    JOIN onboarding o ON o.firebase_uid=p.firebase_uid WHERE r.id=$1 AND r.firebase_uid=$2 AND r.version=$3 AND ${sourceEligible}`,
    [
      candidate.source_post_id,
      candidate.submitter_uid,
      candidate.source_version,
    ],
  );
  return !!result.rowCount;
}
export interface DuelTranslation {
  title: string;
  text: string;
  optionA: string;
  optionB: string;
}
export interface CurationDecision {
  id: string;
  candidateID: string;
  action: 'approve' | 'reject' | 'create';
  operator: string;
  reason: string;
  universe?: string;
  category?: string;
  scheduledOn?: string | null;
  translations?: Record<'pt-BR' | 'en', DuelTranslation>;
}
const uuid =
  /^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i;
export function validateDecision(input: CurationDecision) {
  const text = (v: unknown, max: number) =>
    typeof v === 'string' && v.trim().length > 0 && Array.from(v).length <= max;
  if (
    !uuid.test(input.id) ||
    !uuid.test(input.candidateID) ||
    !['create', 'approve', 'reject'].includes(input.action) ||
    !text(input.operator, 128) ||
    !text(input.reason, 1000)
  )
    throw new Error('INVALID_CURATION');
  if (input.action === 'reject') return;
  if (
    !['marvel', 'dc'].includes(input.universe ?? '') ||
    !['debate', 'stories', 'characters', 'worlds', 'adaptations'].includes(
      input.category ?? '',
    )
  )
    throw new Error('INVALID_CURATION');
  if (
    input.scheduledOn != null &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(input.scheduledOn) ||
      !Number.isFinite(Date.parse(input.scheduledOn)) ||
      new Date(input.scheduledOn).toISOString().slice(0, 10) !==
        input.scheduledOn)
  )
    throw new Error('INVALID_CURATION');
  for (const language of ['pt-BR', 'en'] as const) {
    const t = input.translations?.[language];
    if (
      !t ||
      !text(t.title, 140) ||
      !text(t.text, 2000) ||
      !text(t.optionA, 120) ||
      !text(t.optionB, 120) ||
      t.optionA.trim().toLowerCase() === t.optionB.trim().toLowerCase()
    )
      throw new Error('INVALID_CURATION');
  }
}
// Private administrative capability, never exposed through a member HTTP route.
// Caller owns the transaction. Global queue lock also serializes daily publication and withdrawals.
export async function curateDuel(c: PoolClient, input: CurationDecision) {
  validateDecision(input);
  await c.query('SELECT pg_advisory_xact_lock(1297502532,1)');
  const hash = createHash('sha256')
    .update(
      JSON.stringify([
        input.candidateID,
        input.action,
        input.operator,
        input.reason,
        input.universe ?? null,
        input.category ?? null,
        input.scheduledOn ?? null,
        ...(['pt-BR', 'en'] as const).map((l) => {
          const t = input.translations?.[l];
          return t ? [t.title, t.text, t.optionA, t.optionB] : null;
        }),
      ]),
    )
    .digest('hex');
  const previous = (
    await c.query(
      'SELECT payload_hash FROM duel_curation_decisions WHERE id=$1',
      [input.id],
    )
  ).rows[0];
  if (previous) {
    if (previous.payload_hash !== hash) throw new Error('DECISION_CONFLICT');
    return { id: input.candidateID, applied: true };
  }
  let candidate = (
    await c.query('SELECT * FROM duel_candidates WHERE id=$1 FOR UPDATE', [
      input.candidateID,
    ])
  ).rows[0];
  if (input.action === 'create') {
    if (candidate) throw new Error('CANDIDATE_CONFLICT');
    candidate = (
      await c.query(
        `INSERT INTO duel_candidates(id,origin,universe_id) VALUES($1,'editorial',$2) RETURNING *`,
        [input.candidateID, input.universe],
      )
    ).rows[0];
  }
  if (!candidate || !['pending', 'approved'].includes(candidate.status))
    throw new Error('CANDIDATE_UNAVAILABLE');
  if (input.action !== 'reject') {
    if (
      candidate.origin === 'community' &&
      candidate.universe_id !== input.universe
    )
      throw new Error('INVALID_CURATION');
    if (!(await validSource(c, candidate))) throw new Error('SOURCE_CHANGED');
    if (
      input.scheduledOn &&
      (
        await c.query(
          `SELECT 1 WHERE $1::date<(clock_timestamp() AT TIME ZONE 'UTC')::date
      OR EXISTS(SELECT 1 FROM daily_duels WHERE day=$1) OR EXISTS(SELECT 1 FROM duel_candidates WHERE scheduled_on=$1 AND status='approved' AND id<>$2)`,
          [input.scheduledOn, input.candidateID],
        )
      ).rowCount
    )
      throw new Error('DATE_UNAVAILABLE');
    const duplicate = await c.query(
      `SELECT 1 FROM jsonb_each($1::jsonb) t WHERE
      EXISTS(SELECT 1 FROM duel_published_content h WHERE h.fingerprint=duel_fingerprint(t.value)) OR
      EXISTS(SELECT 1 FROM duel_candidates q CROSS JOIN LATERAL jsonb_each(q.translations) qt WHERE q.id<>$2 AND q.status='approved' AND duel_fingerprint(qt.value)=duel_fingerprint(t.value))`,
      [input.translations, input.candidateID],
    );
    if (duplicate.rowCount) throw new Error('DUPLICATE_DUEL');
  }
  await c.query(
    `UPDATE duel_candidates SET status=$2, translations=CASE WHEN $2='approved' THEN $3::jsonb ELSE translations END,
    universe_id=coalesce($4,universe_id),category=coalesce($5,category),scheduled_on=$6,reason_code=$7,updated_at=now() WHERE id=$1`,
    [
      input.candidateID,
      input.action === 'reject' ? 'rejected' : 'approved',
      input.translations ?? null,
      input.action === 'reject' ? null : (input.universe ?? null),
      input.action === 'reject' ? null : (input.category ?? null),
      input.action === 'reject' ? null : (input.scheduledOn ?? null),
      input.action === 'reject' ? 'editorial_decision' : null,
    ],
  );
  await c.query(
    'INSERT INTO duel_curation_decisions(id,candidate_id,payload_hash,operator,action,reason) VALUES($1,$2,$3,$4,$5,$6)',
    [
      input.id,
      input.candidateID,
      hash,
      input.operator,
      input.action,
      input.reason,
    ],
  );
  return { id: input.candidateID, applied: true };
}

export async function nextDuel(c: PoolClient, day: string) {
  // Freeze source edits/moderation until publication commits, including account deletion's cascading posts.
  await c.query(
    `SELECT r.id FROM community_posts r JOIN duel_candidates q ON q.source_post_id=r.id
    WHERE q.status='approved' AND q.origin='community' AND (q.scheduled_on IS NULL OR q.scheduled_on<=$1) FOR SHARE OF r`,
    [day],
  );
  // Invalidate unavailable sources in one pass; bounded selection does not poll or loop through the queue.
  await c.query(`UPDATE duel_candidates q SET status='rejected',reason_code='source_changed',updated_at=now()
    WHERE q.origin='community' AND q.status IN ('pending','approved') AND NOT EXISTS(
    SELECT 1 FROM community_posts r JOIN profiles p ON p.firebase_uid=r.firebase_uid JOIN onboarding o ON o.firebase_uid=p.firebase_uid
    WHERE r.id=q.source_post_id AND r.firebase_uid=q.submitter_uid AND r.version=q.source_version AND ${sourceEligible})`);
  await c.query(`UPDATE duel_candidates q SET status='rejected',reason_code='duplicate',updated_at=now()
    WHERE q.status='approved' AND EXISTS(SELECT 1 FROM jsonb_each(q.translations) t JOIN duel_published_content h ON h.fingerprint=duel_fingerprint(t.value))`);
  return (
    await c.query(
      `SELECT * FROM duel_candidates WHERE status='approved' AND (scheduled_on IS NULL OR scheduled_on<=$1)
    ORDER BY (scheduled_on=$1) DESC NULLS LAST, scheduled_on ASC NULLS LAST, (origin='community') DESC, created_at,id LIMIT 1 FOR UPDATE`,
      [day],
    )
  ).rows[0];
}
