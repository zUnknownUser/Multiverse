import {
  type CatalogCandidate,
  date,
  plainText,
  positiveInt,
  record,
  records,
} from './candidate.js';
import { fetchProviderJSON } from './provider-http.js';

// Reviewed links to existing Marvel items. No discovery by vague title/company search.
export const tmdbMarvelRegistry = [
  {
    itemId: 'm-ultimato',
    kind: 'movie',
    id: 299534,
    title: 'Avengers: Endgame',
    year: '2019',
  },
  {
    itemId: 'm-aranha',
    kind: 'movie',
    id: 569094,
    title: 'Spider-Man: Across the Spider-Verse',
    year: '2023',
  },
  { itemId: 'm-loki', kind: 'tv', id: 84958, title: 'Loki', year: '2021' },
] as const;
export type TMDBMapping = (typeof tmdbMarvelRegistry)[number];

export function parseTMDB(
  payload: unknown,
  mapping: TMDBMapping,
): CatalogCandidate {
  const data = record(payload);
  const title = plainText(
    mapping.kind === 'movie' ? data.title : data.name,
    300,
  );
  const releaseDate = date(
    mapping.kind === 'movie' ? data.release_date : data.first_air_date,
  );
  if (
    !tmdbMarvelRegistry.some(
      (m) =>
        m.itemId === mapping.itemId &&
        m.id === mapping.id &&
        m.kind === mapping.kind &&
        m.title === mapping.title &&
        m.year === mapping.year,
    ) ||
    data.id !== mapping.id ||
    data.adult === true ||
    title !== mapping.title ||
    releaseDate.slice(0, 4) !== mapping.year
  )
    throw new Error('TMDB_MAPPING_MISMATCH');
  const portuguese = record(
    records(record(data.translations).translations).find(
      (t) => t.iso_639_1 === 'pt' && t.iso_3166_1 === 'BR',
    )?.data,
  );
  const creators = records(record(data.credits).crew)
    .filter(
      (c) =>
        ['Director', 'Writer', 'Screenplay', 'Story'].includes(String(c.job)) &&
        positiveInt(c.id) &&
        plainText(c.name),
    )
    .slice(0, 30)
    .map((c) => ({
      id: Number(c.id),
      name: plainText(c.name, 300),
      roles: [String(c.job)],
    }));
  const poster =
    typeof data.poster_path === 'string' &&
    /^\/[a-zA-Z0-9]+\.(jpg|png)$/.test(data.poster_path)
      ? `https://image.tmdb.org/t/p/w500${data.poster_path}`
      : undefined;
  return {
    provider: 'tmdb',
    externalId: `${mapping.kind}:${mapping.id}`,
    suggestedItemId: mapping.itemId,
    kind: mapping.kind,
    type: mapping.kind === 'movie' ? 'Filme' : 'Série',
    sourceUrl: `https://www.themoviedb.org/${mapping.kind}/${mapping.id}`,
    fetchedAt: new Date().toISOString(),
    attribution: {
      name: 'TMDB',
      url: 'https://www.themoviedb.org',
      termsUrl: 'https://developer.themoviedb.org/docs/faq',
    },
    metadata: {
      titles: {
        en: title,
        'pt-BR':
          plainText(
            mapping.kind === 'movie' ? portuguese.title : portuguese.name,
            300,
          ) || title,
      },
      descriptions: {
        en: plainText(data.overview),
        'pt-BR': plainText(portuguese.overview),
      },
      year: releaseDate.slice(0, 4),
      releaseDate,
      ...(mapping.kind === 'movie' &&
      positiveInt(data.runtime) &&
      data.runtime < 1440
        ? { runtimeMinutes: data.runtime }
        : {}),
      ...(poster ? { posterURL: poster } : {}),
      creators,
      characters: [],
    },
  };
}

export async function fetchTMDBMarvel(
  token: string | undefined,
  transport: typeof fetch = fetch,
): Promise<CatalogCandidate[]> {
  const result: CatalogCandidate[] = [];
  for (const mapping of tmdbMarvelRegistry) {
    const payload = await fetchProviderJSON(
      'tmdb',
      `/${mapping.kind}/${mapping.id}`,
      token,
      transport,
    );
    result.push(parseTMDB(payload, mapping));
  }
  return result;
}
