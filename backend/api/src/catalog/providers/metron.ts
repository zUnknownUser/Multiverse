import { metronDCRegistry } from './hero-expansion-registry.js';
import { providerCoverURL } from '../catalog-cover.js';
import { setTimeout } from 'node:timers/promises';
import {
  type CatalogCandidate,
  date,
  plainText,
  positiveInt,
  record,
  records,
} from './candidate.js';
import { fetchProviderJSON } from './provider-http.js';

// Publisher alone is insufficient: Marvel also publishes licensed universes.
// Keep this first batch aligned with the works already selected in our catalog.
export const metronMarvelSeries = [
  { name: 'Civil War', year: 2006 },
  { name: 'House of M', year: 2005 },
  { name: 'Secret Wars', year: 2015 },
  { name: 'The Infinity Gauntlet', year: 1991 },
] as const;

export function parseMetronIssue(
  payload: unknown,
  requestedID: number,
): CatalogCandidate {
  const data = record(payload);
  const series = record(data.series);
  const publisher = record(data.publisher);
  const dc = metronDCRegistry.find((m) => m.id === requestedID);
  if (
    !positiveInt(requestedID) ||
    data.id !== requestedID ||
    (dc
      ? publisher.id !== 2 || publisher.name !== 'DC Comics'
      : publisher.id !== 1 ||
        !['Marvel', 'Marvel Comics'].includes(String(publisher.name))) ||
    !positiveInt(series.id) ||
    !positiveInt(series.year_began) ||
    series.year_began < 1900 ||
    series.year_began > 2100 ||
    !plainText(series.name) ||
    !plainText(data.number, 30) ||
    series.language !== 'en'
  )
    throw new Error('METRON_NOT_MARVEL_ISSUE');
  if (
    dc
      ? series.id !== dc.seriesID ||
        series.name !== dc.series ||
        series.year_began !== dc.year ||
        data.number !== dc.number
      : !metronMarvelSeries.some(
          (s) => s.name === series.name && s.year === series.year_began,
        )
  )
    throw new Error('METRON_SERIES_OUTSIDE_SCOPE');
  const title = `${plainText(series.name, 260)} #${plainText(data.number, 30)}`;
  const releaseDate = date(data.store_date);
  const coverDate = date(data.cover_date);
  const posterURL = providerCoverURL('metron', data.image);
  return {
    provider: 'metron',
    externalId: `issue:${requestedID}`,
    suggestedItemId: dc?.itemId ?? `m-metron-issue-${requestedID}`,
    kind: 'issue',
    type: 'HQ',
    sourceUrl: `https://metron.cloud/issue/${requestedID}/`,
    fetchedAt: new Date().toISOString(),
    attribution: {
      name: 'Metron contributors',
      url: 'https://metron.cloud',
      termsUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
    },
    metadata: {
      titles: { 'pt-BR': title, en: title },
      descriptions: { 'pt-BR': '', en: plainText(data.desc) },
      year: (releaseDate || coverDate).slice(0, 4),
      releaseDate,
      coverDate,
      originalLanguage: String(series.language),
      publisher: { id: Number(publisher.id), name: String(publisher.name) },
      format: plainText(record(series.series_type).name, 80),
      ...(plainText(data.isbn, 30) ? { isbn: plainText(data.isbn, 30) } : {}),
      ...(plainText(data.upc, 40) ? { upc: plainText(data.upc, 40) } : {}),
      ...(dc?.artworkOnly ? { artworkOnly: true } : {}),
      ...(posterURL ? { posterURL } : {}),
      ...(positiveInt(data.page) && data.page <= 10_000
        ? { pageCount: data.page }
        : {}),
      series: {
        id: series.id,
        title: plainText(series.name, 300),
        year: series.year_began,
        number: plainText(data.number, 30),
      },
      creators: records(data.credits)
        .filter((c) => positiveInt(c.id) && plainText(c.creator))
        .slice(0, 100)
        .map((c) => ({
          id: Number(c.id),
          name: plainText(c.creator, 300),
          roles: records(c.role)
            .map((r) => plainText(r.name, 80))
            .filter(Boolean),
        })),
      characters: records(data.characters)
        .filter((c) => positiveInt(c.id) && plainText(c.name))
        .slice(0, 100)
        .map((c) => ({ id: Number(c.id), name: plainText(c.name, 300) })),
    },
  };
}

export async function fetchMetronMarvelIssues(
  ids: readonly number[],
  token: string | undefined,
  transport: typeof fetch = fetch,
  wait: (ms: number) => Promise<unknown> = setTimeout,
): Promise<CatalogCandidate[]> {
  if (
    ids.length < 1 ||
    ids.length > 10 ||
    ids.some((id) => !positiveInt(id)) ||
    new Set(ids).size !== ids.length
  )
    throw new Error('METRON_INVALID_ISSUE_IDS');
  const result: CatalogCandidate[] = [];
  for (const id of ids) {
    // Below the documented 20/minute default; no retries on quota/auth failures.
    if (result.length) await wait(3100);
    result.push(
      parseMetronIssue(
        await fetchProviderJSON('metron', `/issue/${id}/`, token, transport),
        id,
      ),
    );
  }
  return result;
}
