import type { PoolClient } from 'pg';
import type { CatalogCandidate } from './candidate.js';
import { metronMarvelRegistry } from './metron-registry.js';

// Caller owns the transaction. Publication is operational, never part of login.
export async function publishMetron(
  client: PoolClient,
  batch: readonly CatalogCandidate[],
) {
  if (
    batch.length !== metronMarvelRegistry.length ||
    new Set(batch.map((c) => c.externalId)).size !== batch.length
  )
    throw new Error('CATALOG_INCOMPLETE_METRON_BATCH');
  await client.query('SELECT pg_advisory_xact_lock(72451902)');
  for (const candidate of batch) {
    const mapping = metronMarvelRegistry.find(
      (m) => candidate.externalId === `issue:${m.id}`,
    );
    const series = candidate.metadata.series;
    if (
      !mapping ||
      candidate.provider !== 'metron' ||
      candidate.kind !== 'issue' ||
      candidate.type !== 'HQ' ||
      candidate.suggestedItemId !== `m-metron-issue-${mapping.id}` ||
      candidate.sourceUrl !== `https://metron.cloud/issue/${mapping.id}/` ||
      series?.id !== mapping.seriesID ||
      series.title !== mapping.series ||
      series.year !== mapping.year ||
      series.number !== mapping.number ||
      !Number.isFinite(Date.parse(candidate.fetchedAt))
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    const itemID = candidate.suggestedItemId;
    const inserted = await client.query(
      `INSERT INTO catalog_items(id,universe_id,type,sort_order) VALUES($1,'marvel','HQ',110)
       ON CONFLICT(id) DO NOTHING RETURNING id`,
      [itemID],
    );
    if (!inserted.rowCount) {
      const existing = await client.query(
        `SELECT 1 FROM catalog_items i JOIN catalog_sources s ON s.item_id=i.id
         WHERE i.id=$1 AND i.universe_id='marvel' AND i.type='HQ' AND s.provider='metron' AND s.external_id=$2 FOR UPDATE OF i`,
        [itemID, candidate.externalId],
      );
      if (!existing.rowCount) throw new Error('CATALOG_MAPPING_CONFLICT');
    }
    const seriesID = `metron-${mapping.seriesID}`;
    await client.query(
      `INSERT INTO catalog_series(id,universe_id,year) VALUES($1,'marvel',$2) ON CONFLICT(id) DO NOTHING`,
      [seriesID, mapping.year],
    );
    const storedSeries = await client.query(
      'SELECT universe_id,year FROM catalog_series WHERE id=$1 FOR UPDATE',
      [seriesID],
    );
    if (
      storedSeries.rows[0]?.universe_id !== 'marvel' ||
      storedSeries.rows[0]?.year !== mapping.year
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    await client.query(
      `INSERT INTO catalog_series_items(item_id,series_id,issue_number,position) VALUES($1,$2,$3,$4) ON CONFLICT(item_id) DO NOTHING`,
      [itemID, seriesID, mapping.number, Number(mapping.number)],
    );
    const membership = await client.query(
      'SELECT series_id,issue_number,position FROM catalog_series_items WHERE item_id=$1',
      [itemID],
    );
    if (
      membership.rows[0]?.series_id !== seriesID ||
      membership.rows[0]?.issue_number !== mapping.number ||
      membership.rows[0]?.position !== Number(mapping.number)
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    for (const locale of ['pt-BR', 'en'] as const) {
      await client.query(
        `INSERT INTO catalog_series_translations(series_id,locale,title) VALUES($1,$2,$3) ON CONFLICT(series_id,locale) DO NOTHING`,
        [
          seriesID,
          locale,
          locale === 'pt-BR' ? mapping.seriesPT : mapping.series,
        ],
      );
      await client.query(
        `INSERT INTO catalog_item_translations(item_id,locale,title,year,description,canon)
         VALUES($1,$2,$3,$4,$5,'—') ON CONFLICT(item_id,locale) DO NOTHING`,
        [
          itemID,
          locale,
          locale === 'pt-BR'
            ? mapping.titlePT
            : `${mapping.series} #${mapping.number}`,
          candidate.metadata.year,
          locale === 'pt-BR'
            ? mapping.descriptionPT
            : candidate.metadata.descriptions.en ||
              'Description not available yet.',
        ],
      );
    }
    await client.query(
      `INSERT INTO catalog_sources(provider,external_id,item_id,source_url,revision,metadata,fetched_at)
       VALUES('metron',$1,$2,$3,$4,$5,$6)
       ON CONFLICT(provider,external_id) DO UPDATE SET source_url=EXCLUDED.source_url,revision=EXCLUDED.revision,
       metadata=EXCLUDED.metadata,fetched_at=EXCLUDED.fetched_at
       WHERE catalog_sources.item_id=EXCLUDED.item_id AND catalog_sources.fetched_at < EXCLUDED.fetched_at`,
      [
        candidate.externalId,
        itemID,
        candidate.sourceUrl,
        Date.parse(candidate.fetchedAt),
        {
          ...candidate.metadata,
          attribution: candidate.attribution,
          adaptation:
            'Normalized metadata; PT-BR titles and synopses adapted by Multiverse from Metron, licensed under CC BY-SA 4.0.',
        },
        candidate.fetchedAt,
      ],
    );
    const source = await client.query(
      "SELECT item_id FROM catalog_sources WHERE provider='metron' AND external_id=$1",
      [candidate.externalId],
    );
    if (source.rows[0]?.item_id !== itemID)
      throw new Error('CATALOG_MAPPING_CONFLICT');
  }
}
