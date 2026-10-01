import { readProviderJSON } from './provider-http.js';
import type { MarvelMapping } from './marvel-registry.js';

type RecordValue = Record<string, unknown>;
function object(value: unknown): RecordValue {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as RecordValue)
    : {};
}
function text(value: unknown, max = 1000): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}
export interface ExternalMetadata {
  titles: Record<'pt-BR' | 'en', string>;
  descriptions: Record<'pt-BR' | 'en', string>;
  year: string;
  creatorIds: string[];
  publisherIds: string[];
}
export interface ImportedMarvelItem {
  mapping: MarvelMapping;
  sourceUrl: string;
  revision: number;
  metadata: ExternalMetadata;
}

export function parseWikidata(
  payload: unknown,
  mapping: MarvelMapping,
): ImportedMarvelItem {
  const entity = object(object(object(payload).entities)[mapping.entityId]);
  const labels = object(entity.labels);
  const descriptions = object(entity.descriptions);
  const englishTitle = text(object(labels.en).value, 300);
  if (
    entity.id !== mapping.entityId ||
    englishTitle !== mapping.expectedEnglishTitle ||
    !Number.isSafeInteger(entity.lastrevid) ||
    Number(entity.lastrevid) <= 0
  )
    throw new Error(`WIKIDATA_INVALID_ENTITY: ${mapping.entityId}`);
  const claims = object(entity.claims);
  const values = (property: string) =>
    (Array.isArray(claims[property]) ? (claims[property] as unknown[]) : [])
      .map(object)
      .filter((c) => c.rank !== 'deprecated')
      .map((c) => object(object(object(c.mainsnak).datavalue).value));
  const ids = (properties: string[]) => [
    ...new Set(
      properties.flatMap((p) =>
        values(p)
          .map((v) => text(v.id))
          .filter((id) => /^Q[1-9]\d*$/.test(id)),
      ),
    ),
  ];
  // A year-only date must never become a fabricated day/month.
  const dates = ['P577', 'P580', 'P571'].flatMap(values);
  const date = dates.find(
    (v) =>
      typeof v.precision === 'number' &&
      v.precision >= 9 &&
      /^\+\d{4}-/.test(text(v.time)),
  );
  const year = date ? text(date.time).slice(1, 5) : '';
  return {
    mapping,
    sourceUrl: `https://www.wikidata.org/wiki/${mapping.entityId}`,
    revision: Number(entity.lastrevid),
    metadata: {
      titles: {
        'pt-BR':
          text(object(labels['pt-br']).value, 300) ||
          text(object(labels.pt).value, 300) ||
          englishTitle,
        en: englishTitle,
      },
      // Missing Portuguese copy remains absent, rather than silently displaying English as Portuguese.
      descriptions: {
        'pt-BR':
          text(object(descriptions['pt-br']).value) ||
          text(object(descriptions.pt).value),
        en: text(object(descriptions.en).value),
      },
      year,
      creatorIds: ids(['P50', 'P58', 'P110', 'P170']),
      publisherIds: ids(['P123']),
    },
  };
}
export async function fetchMarvelMetadata(
  registry: readonly MarvelMapping[],
  transport: typeof fetch = fetch,
): Promise<ImportedMarvelItem[]> {
  const result: ImportedMarvelItem[] = [];
  for (const mapping of registry) {
    if (!/^Q[1-9]\d*$/.test(mapping.entityId))
      throw new Error('INVALID_ENTITY_ID');
    // Sequential, bounded calls. A failure aborts the batch before any database write.
    const response = await transport(
      `https://www.wikidata.org/wiki/Special:EntityData/${mapping.entityId}.json`,
      {
        headers: {
          'User-Agent':
            'Multiverse/0.1 (https://somosmultiverse.com.br; catalog integration)',
          Accept: 'application/json',
        },
        signal: AbortSignal.timeout(15_000),
        redirect: 'error',
      },
    );
    if (!response.ok) {
      await response.body?.cancel().catch(() => {});
      throw new Error(
        `WIKIDATA_UNAVAILABLE: HTTP ${response.status}; retry later`,
      );
    }
    result.push(
      parseWikidata(await readProviderJSON(response, 'WIKIDATA'), mapping),
    );
  }
  return result;
}
