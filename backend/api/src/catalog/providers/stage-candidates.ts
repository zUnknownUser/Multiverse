import type { PoolClient } from 'pg';
import type { CatalogCandidate } from './candidate.js';

// Caller owns the transaction. This cannot publish or modify any user-visible item.
export async function stageCandidates(
  client: PoolClient,
  batch: readonly CatalogCandidate[],
) {
  if (
    !batch.length ||
    batch.length > 10 ||
    new Set(batch.map((c) => `${c.provider}:${c.externalId}`)).size !==
      batch.length
  )
    throw new Error('CATALOG_INVALID_CANDIDATE_BATCH');
  await client.query('SELECT pg_advisory_xact_lock(72451902)');
  for (const candidate of batch) {
    const {
      provider,
      externalId,
      suggestedItemId,
      kind,
      sourceUrl,
      attribution,
      metadata,
      fetchedAt,
    } = candidate;
    if (!/^m-[a-z0-9-]{1,78}$/.test(suggestedItemId))
      throw new Error('CATALOG_INVALID_CANDIDATE');
    await client.query(
      `INSERT INTO catalog_import_candidates(provider,external_id,universe_id,suggested_item_id,kind,source_url,attribution,metadata,fetched_at)
       VALUES($1,$2,'marvel',$3,$4,$5,$6,$7,$8)
       ON CONFLICT(provider,external_id) DO UPDATE SET
       source_url=EXCLUDED.source_url,attribution=EXCLUDED.attribution,metadata=EXCLUDED.metadata,fetched_at=EXCLUDED.fetched_at
       WHERE catalog_import_candidates.suggested_item_id=EXCLUDED.suggested_item_id
       AND catalog_import_candidates.kind=EXCLUDED.kind
       AND catalog_import_candidates.fetched_at < EXCLUDED.fetched_at`,
      [
        provider,
        externalId,
        suggestedItemId,
        kind,
        sourceUrl,
        attribution,
        metadata,
        fetchedAt,
      ],
    );
    const stored = await client.query(
      'SELECT suggested_item_id,kind FROM catalog_import_candidates WHERE provider=$1 AND external_id=$2',
      [provider, externalId],
    );
    if (
      stored.rows[0]?.suggested_item_id !== suggestedItemId ||
      stored.rows[0]?.kind !== kind
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
  }
}
