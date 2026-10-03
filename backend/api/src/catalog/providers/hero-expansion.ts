import type { PoolClient } from 'pg';
import { setTimeout } from 'node:timers/promises';
import type { CatalogCandidate } from './candidate.js';
import {
  tmdbExpansionRegistry,
  metronDCRegistry,
} from './hero-expansion-registry.js';
import { metronDCDescriptions } from './metron-dc-descriptions.js';
import { parseTMDB } from './tmdb.js';
import { parseMetronIssue } from './metron.js';
import { fetchProviderJSON } from './provider-http.js';

export function normalizeDCIssue(
  payload: unknown,
  id: number,
): CatalogCandidate {
  const mapping = metronDCRegistry.find((m) => m.id === id);
  if (!mapping) throw new Error('CATALOG_MAPPING_CONFLICT');
  const candidate = parseMetronIssue(payload, id);
  candidate.metadata.titles['pt-BR'] = `${mapping.seriesPT} #${mapping.number}`;
  candidate.metadata.descriptions['pt-BR'] = metronDCDescriptions[id] ?? '';
  if (!mapping.artworkOnly && !candidate.metadata.descriptions['pt-BR'])
    throw new Error('CATALOG_TRANSLATION_REQUIRED');
  return candidate;
}

// Operational only: fixed reviewed IDs, paced requests, no provider calls on app navigation.
export async function fetchHeroExpansion(
  tokens: { tmdb?: string; metron?: string },
  transport: typeof fetch = fetch,
  wait: (ms: number) => Promise<unknown> = setTimeout,
) {
  const result: CatalogCandidate[] = [];
  for (const mapping of tmdbExpansionRegistry) {
    if (result.length) await wait(300);
    result.push(
      parseTMDB(
        await fetchProviderJSON(
          'tmdb',
          `/${mapping.kind}/${mapping.id}`,
          tokens.tmdb,
          transport,
        ),
        mapping,
      ),
    );
  }
  for (const mapping of metronDCRegistry) {
    await wait(3300);
    result.push(
      normalizeDCIssue(
        await fetchProviderJSON(
          'metron',
          `/issue/${mapping.id}/`,
          tokens.metron,
          transport,
        ),
        mapping.id,
      ),
    );
  }
  return result;
}

export function expansionMapping(candidate: CatalogCandidate) {
  const movie =
    candidate.provider === 'tmdb'
      ? tmdbExpansionRegistry.find(
          (m) => `${m.kind}:${m.id}` === candidate.externalId,
        )
      : undefined;
  const issue =
    candidate.provider === 'metron'
      ? metronDCRegistry.find((m) => `issue:${m.id}` === candidate.externalId)
      : undefined;
  const mapping = movie ?? issue;
  if (
    !mapping ||
    candidate.suggestedItemId !== mapping.itemId ||
    !Number.isFinite(Date.parse(candidate.fetchedAt))
  )
    throw new Error('CATALOG_MAPPING_CONFLICT');
  if (
    movie &&
    (candidate.kind !== movie.kind ||
      candidate.type !== (movie.kind === 'movie' ? 'Filme' : 'Série') ||
      candidate.metadata.titles.en !== movie.title ||
      candidate.metadata.year !== movie.year ||
      candidate.sourceUrl !==
        `https://www.themoviedb.org/${movie.kind}/${movie.id}`)
  )
    throw new Error('CATALOG_MAPPING_CONFLICT');
  if (
    issue &&
    (candidate.kind !== 'issue' ||
      candidate.type !== 'HQ' ||
      candidate.sourceUrl !== `https://metron.cloud/issue/${issue.id}/` ||
      candidate.metadata.series?.id !== issue.seriesID ||
      candidate.metadata.series.title !== issue.series ||
      candidate.metadata.series.year !== issue.year ||
      candidate.metadata.series.number !== issue.number ||
      Boolean(candidate.metadata.artworkOnly) !== issue.artworkOnly)
  )
    throw new Error('CATALOG_MAPPING_CONFLICT');
  const artworkOnly = issue?.artworkOnly ?? false;
  if (
    !artworkOnly &&
    (!candidate.metadata.titles['pt-BR'] ||
      !candidate.metadata.descriptions['pt-BR'] ||
      !candidate.metadata.descriptions.en)
  )
    throw new Error('CATALOG_TRANSLATION_REQUIRED');
  return {
    universe: mapping.universe,
    artworkOnly,
    issue,
    existing: artworkOnly || candidate.suggestedItemId === 'd-tdk',
  };
}

// Caller owns the transaction. New entries never borrow votes, reviews or diary progress.
export async function publishHeroExpansion(
  client: PoolClient,
  batch: readonly CatalogCandidate[],
) {
  if (
    batch.length !== tmdbExpansionRegistry.length + metronDCRegistry.length ||
    new Set(batch.map((c) => `${c.provider}:${c.externalId}`)).size !==
      batch.length
  )
    throw new Error('CATALOG_INCOMPLETE_HERO_BATCH');
  const mappings = batch.map(expansionMapping); // Validate the entire batch before writing.
  await client.query('SELECT pg_advisory_xact_lock(72451902)');
  for (const [index, candidate] of batch.entries()) {
    const { universe, artworkOnly, issue, existing } = mappings[index];
    const id = candidate.suggestedItemId;
    const inserted = existing
      ? { rowCount: 0 }
      : await client.query(
          'INSERT INTO catalog_items(id,universe_id,type,sort_order) VALUES($1,$2,$3,120) ON CONFLICT(id) DO NOTHING RETURNING id',
          [id, universe, candidate.type],
        );
    if (!inserted.rowCount) {
      const stored = await client.query(
        'SELECT universe_id,type FROM catalog_items WHERE id=$1 FOR UPDATE',
        [id],
      );
      if (
        stored.rows[0]?.universe_id !== universe ||
        stored.rows[0]?.type !== candidate.type
      )
        throw new Error('CATALOG_MAPPING_CONFLICT');
      if (!existing) {
        const source = await client.query(
          'SELECT 1 FROM catalog_sources WHERE item_id=$1 AND provider=$2 AND external_id=$3',
          [id, candidate.provider, candidate.externalId],
        );
        if (!source.rowCount) throw new Error('CATALOG_MAPPING_CONFLICT');
      }
    }
    if (!artworkOnly) {
      for (const locale of ['pt-BR', 'en'] as const)
        await client.query(
          `INSERT INTO catalog_item_translations(item_id,locale,title,year,description,canon) VALUES($1,$2,$3,$4,$5,'—') ON CONFLICT(item_id,locale) DO NOTHING`,
          [
            id,
            locale,
            candidate.metadata.titles[locale],
            candidate.metadata.year,
            candidate.metadata.descriptions[locale],
          ],
        );
    }
    if (issue && !artworkOnly) {
      const seriesID = `metron-${issue.seriesID}`;
      await client.query(
        'INSERT INTO catalog_series(id,universe_id,year) VALUES($1,$2,$3) ON CONFLICT(id) DO NOTHING',
        [seriesID, universe, issue.year],
      );
      const series = await client.query(
        'SELECT universe_id,year FROM catalog_series WHERE id=$1 FOR UPDATE',
        [seriesID],
      );
      if (
        series.rows[0]?.universe_id !== universe ||
        series.rows[0]?.year !== issue.year
      )
        throw new Error('CATALOG_MAPPING_CONFLICT');
      for (const locale of ['pt-BR', 'en'])
        await client.query(
          'INSERT INTO catalog_series_translations(series_id,locale,title) VALUES($1,$2,$3) ON CONFLICT(series_id,locale) DO NOTHING',
          [
            seriesID,
            locale,
            locale === 'pt-BR' ? issue.seriesPT : issue.series,
          ],
        );
      await client.query(
        'INSERT INTO catalog_series_items(item_id,series_id,issue_number,position) VALUES($1,$2,$3,$4) ON CONFLICT(item_id) DO NOTHING',
        [id, seriesID, issue.number, Number(issue.number)],
      );
      const membership = await client.query(
        'SELECT series_id,issue_number,position FROM catalog_series_items WHERE item_id=$1',
        [id],
      );
      if (
        membership.rows[0]?.series_id !== seriesID ||
        membership.rows[0]?.issue_number !== issue.number ||
        membership.rows[0]?.position !== Number(issue.number)
      )
        throw new Error('CATALOG_MAPPING_CONFLICT');
    }
    await client.query(
      `INSERT INTO catalog_sources(provider,external_id,item_id,source_url,revision,metadata,fetched_at) VALUES($1,$2,$3,$4,$5,$6,$7)
      ON CONFLICT(provider,external_id) DO UPDATE SET source_url=EXCLUDED.source_url,revision=EXCLUDED.revision,metadata=EXCLUDED.metadata,fetched_at=EXCLUDED.fetched_at
      WHERE catalog_sources.item_id=EXCLUDED.item_id AND catalog_sources.fetched_at<EXCLUDED.fetched_at`,
      [
        candidate.provider,
        candidate.externalId,
        id,
        candidate.sourceUrl,
        Date.parse(candidate.fetchedAt),
        { ...candidate.metadata, attribution: candidate.attribution },
        candidate.fetchedAt,
      ],
    );
    const source = await client.query(
      'SELECT item_id FROM catalog_sources WHERE provider=$1 AND external_id=$2',
      [candidate.provider, candidate.externalId],
    );
    if (source.rows[0]?.item_id !== id)
      throw new Error('CATALOG_MAPPING_CONFLICT');
  }
}
