import type { PoolClient } from 'pg';
import type { ImportedMarvelItem } from './wikidata.js';

// Caller owns the transaction. Existing titles, canon, status and reviews remain editorial/user data.
export async function importMarvel(
  client: PoolClient,
  batch: ImportedMarvelItem[],
) {
  await client.query('SELECT pg_advisory_xact_lock(72451902)');
  for (const { mapping, sourceUrl, revision, metadata } of batch) {
    await client.query(
      `INSERT INTO catalog_items(id,universe_id,type,sort_order) VALUES($1,'marvel',$2,100)
      ON CONFLICT(id) DO NOTHING`,
      [mapping.itemId, mapping.type],
    );
    const item = await client.query(
      'SELECT universe_id,type FROM catalog_items WHERE id=$1 FOR UPDATE',
      [mapping.itemId],
    );
    if (
      item.rows[0]?.universe_id !== 'marvel' ||
      item.rows[0]?.type !== mapping.type
    )
      throw new Error('CATALOG_MAPPING_CONFLICT');
    for (const locale of ['pt-BR', 'en'] as const) {
      await client.query(
        `INSERT INTO catalog_item_translations(item_id,locale,title,year,description,canon)
        VALUES($1,$2,$3,$4,$5,'—') ON CONFLICT(item_id,locale) DO NOTHING`,
        [
          mapping.itemId,
          locale,
          metadata.titles[locale],
          metadata.year,
          metadata.descriptions[locale] ||
            (locale === 'pt-BR'
              ? 'Descrição ainda não disponível.'
              : 'Description not available yet.'),
        ],
      );
    }
    await client.query(
      `INSERT INTO catalog_sources(provider,external_id,item_id,source_url,revision,metadata)
      VALUES('wikidata',$1,$2,$3,$4,$5) ON CONFLICT(provider,external_id) DO UPDATE SET
      source_url=EXCLUDED.source_url,revision=EXCLUDED.revision,metadata=EXCLUDED.metadata,fetched_at=now()
      WHERE catalog_sources.item_id=EXCLUDED.item_id AND catalog_sources.revision <= EXCLUDED.revision`,
      [mapping.entityId, mapping.itemId, sourceUrl, revision, metadata],
    );
    const source = await client.query(
      "SELECT item_id FROM catalog_sources WHERE provider='wikidata' AND external_id=$1",
      [mapping.entityId],
    );
    if (source.rows[0]?.item_id !== mapping.itemId)
      throw new Error('CATALOG_MAPPING_CONFLICT');
  }
}
