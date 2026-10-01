import type { PoolClient } from 'pg';
import type { CatalogCandidate } from './candidate.js';
import { tmdbMarvelRegistry } from './tmdb.js';

// Explicit operational publication after license/attribution review. Never runs
// at startup or on a user request; does not edit editorial rows or user activity.
export async function publishTMDB(
  client: PoolClient,
  batch: readonly CatalogCandidate[],
) {
  if (
    batch.length !== tmdbMarvelRegistry.length ||
    new Set(batch.map((c) => c.externalId)).size !== batch.length
  )
    throw new Error('CATALOG_INCOMPLETE_TMDB_BATCH');
  await client.query('SELECT pg_advisory_xact_lock(72451902)');
  for (const candidate of batch) {
    const mapping = tmdbMarvelRegistry.find(
      (m) => m.itemId === candidate.suggestedItemId,
    );
    if (
      !mapping ||
      candidate.provider !== 'tmdb' ||
      candidate.externalId !== `${mapping.kind}:${mapping.id}` ||
      candidate.kind !== mapping.kind ||
      candidate.metadata.titles.en !== mapping.title ||
      candidate.metadata.year !== mapping.year ||
      !Number.isFinite(Date.parse(candidate.fetchedAt))
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    const expectedType = mapping.kind === 'movie' ? 'Filme' : 'Série';
    const item = await client.query(
      'SELECT universe_id,type FROM catalog_items WHERE id=$1 FOR SHARE',
      [mapping.itemId],
    );
    if (
      item.rows[0]?.universe_id !== 'marvel' ||
      item.rows[0]?.type !== expectedType ||
      candidate.type !== expectedType
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    await client.query(
      `INSERT INTO catalog_sources(provider,external_id,item_id,source_url,revision,metadata,fetched_at)
       VALUES('tmdb',$1,$2,$3,$4,$5,$6)
       ON CONFLICT(provider,external_id) DO UPDATE SET source_url=EXCLUDED.source_url,
       revision=EXCLUDED.revision,metadata=EXCLUDED.metadata,fetched_at=EXCLUDED.fetched_at
       WHERE catalog_sources.item_id=EXCLUDED.item_id AND catalog_sources.fetched_at < EXCLUDED.fetched_at`,
      [
        candidate.externalId,
        mapping.itemId,
        candidate.sourceUrl,
        Date.parse(candidate.fetchedAt),
        { ...candidate.metadata, attribution: candidate.attribution },
        candidate.fetchedAt,
      ],
    );
    const stored = await client.query(
      "SELECT item_id FROM catalog_sources WHERE provider='tmdb' AND external_id=$1",
      [candidate.externalId],
    );
    if (stored.rows[0]?.item_id !== mapping.itemId)
      throw new Error('CATALOG_MAPPING_CONFLICT');
  }
}
