import { fetchProviderJSON } from './provider-http.js';
import { parseTMDB, fetchTMDBMarvel, tmdbMarvelRegistry } from './tmdb.js';
import { parseMetronIssue, fetchMetronMarvelIssues } from './metron.js';

const mapping = tmdbMarvelRegistry[0];
function movie() {
  return {
    id: mapping.id,
    title: mapping.title,
    release_date: '2019-04-24',
    adult: false,
    overview: 'English synopsis',
    runtime: 181,
    vote_average: 9,
    vote_count: 1000,
    popularity: 123,
    poster_path: '/abc123.jpg',
    daily_message: 'Do not import',
    translations: {
      translations: [
        {
          iso_639_1: 'pt',
          iso_3166_1: 'BR',
          data: {
            title: 'Vingadores: Ultimato',
            overview: 'Sinopse brasileira',
          },
        },
      ],
    },
    credits: { crew: [{ id: 1, name: 'Director name', job: 'Director' }] },
  };
}
function issue(id = 123) {
  return {
    id,
    publisher: { id: 1, name: 'Marvel Comics' },
    series: { id: 100, name: 'Civil War', language: 'en', year_began: 2006 },
    number: '1',
    store_date: '2006-05-03',
    cover_date: '2006-07-01',
    page: 32,
    desc: '<p>Issue synopsis</p>',
    average_rating: 5,
    price: '3.99',
    credits: [
      { id: 2, creator: 'Writer name', role: [{ id: 1, name: 'Writer' }] },
    ],
    characters: [{ id: 3, name: 'Spider-Man' }],
  };
}

describe('Marvel provider scope and normalization', () => {
  it('keeps TMDB translations, runtime and authors without importing votes or unrelated fields', () => {
    const result = parseTMDB(movie(), mapping);
    expect(result.metadata).toMatchObject({
      titles: { 'pt-BR': 'Vingadores: Ultimato', en: mapping.title },
      descriptions: { 'pt-BR': 'Sinopse brasileira', en: 'English synopsis' },
      runtimeMinutes: 181,
      year: '2019',
      posterURL: 'https://image.tmdb.org/t/p/w500/abc123.jpg',
      creators: [{ id: 1, name: 'Director name', roles: ['Director'] }],
    });
    for (const key of [
      'vote_average',
      'vote_count',
      'popularity',
      'daily_message',
    ])
      expect(JSON.stringify(result)).not.toContain(key);
  });
  it.each([
    { id: 1 },
    { title: 'Another film' },
    { release_date: '2020-01-01' },
    { release_date: '2019-02-30' },
    { adult: true },
  ])('rejects wrong TMDB identity or invalid content: %j', (change) => {
    expect(() => parseTMDB({ ...movie(), ...change }, mapping)).toThrow(
      'MAPPING_MISMATCH',
    );
  });
  it('keeps missing Portuguese descriptions empty and rejects arbitrary image hosts', () => {
    const result = parseTMDB(
      {
        ...movie(),
        translations: {},
        poster_path: 'https://attacker.test/image.jpg',
      },
      mapping,
    );
    expect(result.metadata.descriptions['pt-BR']).toBe('');
    expect(result.metadata.posterURL).toBeUndefined();
    expect(result.metadata.titles['pt-BR']).toBe(mapping.title);
  });
  it('distinguishes series from movies, without treating runtime as episode duration', () => {
    const tv = tmdbMarvelRegistry[2];
    const result = parseTMDB(
      { id: tv.id, name: tv.title, first_air_date: '2021-06-09', runtime: 50 },
      tv,
    );
    expect(result.type).toBe('Série');
    expect(result.externalId).toBe('tv:84958');
    expect(result.metadata.runtimeMinutes).toBeUndefined();
  });
  it('keeps an issue distinct from a full arc and does not fabricate translated text or release dates', () => {
    const result = parseMetronIssue({ ...issue(), store_date: null }, 123);
    expect(result.suggestedItemId).toBe('m-metron-issue-123');
    expect(result.kind).toBe('issue');
    expect(result.metadata).toMatchObject({
      releaseDate: '',
      coverDate: '2006-07-01',
      year: '2006',
      descriptions: { en: 'Issue synopsis', 'pt-BR': '' },
      creators: [{ id: 2, name: 'Writer name', roles: ['Writer'] }],
      characters: [{ id: 3, name: 'Spider-Man' }],
    });
    expect(JSON.stringify(result)).not.toContain('average_rating');
    expect(JSON.stringify(result)).not.toContain('price');
  });
  it('rejects non-Marvel publishers and licensed universes even when Marvel publishes them', () => {
    expect(() =>
      parseMetronIssue({ ...issue(), publisher: { name: 'DC Comics' } }, 123),
    ).toThrow('NOT_MARVEL');
    expect(() =>
      parseMetronIssue(
        { ...issue(), series: { ...issue().series, name: 'Star Wars' } },
        123,
      ),
    ).toThrow('OUTSIDE_SCOPE');
    expect(() => parseMetronIssue({ ...issue(), id: 124 }, 123)).toThrow(
      'NOT_MARVEL',
    );
    expect(() =>
      parseMetronIssue(
        { ...issue(), series: { ...issue().series, year_began: 2015 } },
        123,
      ),
    ).toThrow('OUTSIDE_SCOPE');
  });
});

describe('Provider transport and quotas', () => {
  it('does not make requests without credentials or for arbitrary paths', async () => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(fetchTMDBMarvel('', fetcher)).rejects.toThrow(
      'TMDB_NOT_CONFIGURED',
    );
    await expect(
      fetchProviderJSON('tmdb', '/movie/1', 'bad\r\nkey', fetcher),
    ).rejects.toThrow('INVALID_TOKEN');
    for (const path of [
      'https://attacker.test',
      '/../private',
      '/movie/1?api_key=x',
    ])
      await expect(
        fetchProviderJSON('tmdb', path, 'test-token', fetcher),
      ).rejects.toThrow('INVALID_PATH');
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('uses fixed HTTPS hosts, headers, timeout and no redirects', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValue(Response.json(movie()));
    await fetchProviderJSON('tmdb', '/movie/299534', 'test-token', fetcher);
    const [url, init] = fetcher.mock.calls[0];
    expect(url).toBe(
      'https://api.themoviedb.org/3/movie/299534?language=en-US&append_to_response=translations%2Ccredits',
    );
    expect(init).toMatchObject({
      redirect: 'error',
      signal: expect.any(AbortSignal),
      headers: { Authorization: 'Bearer test-token' },
    });
    expect(url).not.toContain('test-token');
  });
  it.each([401, 403, 429, 503])(
    'stops on HTTP %s without retry or exposing response secrets',
    async (status) => {
      const fetcher = vi
        .fn<typeof fetch>()
        .mockResolvedValue(new Response('secret upstream details', { status }));
      await expect(fetchTMDBMarvel('test-token', fetcher)).rejects.toThrow(
        new Error(`TMDB_HTTP_${status}`),
      );
      expect(fetcher).toHaveBeenCalledOnce();
    },
  );
  it('sanitizes network/JSON errors and bounds streamed responses', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockRejectedValue(new Error('secret-token network failure'));
    await expect(
      fetchProviderJSON('metron', '/issue/1/', 'test-token', fetcher),
    ).rejects.toThrow(new Error('METRON_UNAVAILABLE'));
    fetcher.mockResolvedValueOnce(new Response('private invalid json'));
    await expect(
      fetchProviderJSON('metron', '/issue/1/', 'test-token', fetcher),
    ).rejects.toThrow(new Error('METRON_INVALID_JSON'));
    fetcher.mockResolvedValueOnce(new Response('x'.repeat(2_000_001)));
    await expect(
      fetchProviderJSON('metron', '/issue/1/', 'test-token', fetcher),
    ).rejects.toThrow('RESPONSE_TOO_LARGE');
  });
  it('throttles Metron sequentially and fails a batch instead of returning partial success', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(Response.json(issue()))
      .mockResolvedValueOnce(new Response('', { status: 429 }));
    const wait = vi.fn().mockResolvedValue(undefined);
    await expect(
      fetchMetronMarvelIssues([123, 124, 125], 'test-token', fetcher, wait),
    ).rejects.toThrow('METRON_HTTP_429');
    expect(fetcher).toHaveBeenCalledTimes(2);
    expect(wait).toHaveBeenCalledExactlyOnceWith(3100);
    expect(fetcher.mock.calls[0][0]).toBe(
      'https://metron.cloud/api/issue/123/',
    );
  });
  it.each(
    [[], [1, 1], [-1], [NaN], Array.from({ length: 11 }, (_, i) => i + 1)].map(
      (ids) => ({ ids }),
    ),
  )('rejects unsafe issue batches: $ids', async ({ ids }) => {
    const fetcher = vi.fn<typeof fetch>();
    await expect(
      fetchMetronMarvelIssues(ids, 'test-token', fetcher),
    ).rejects.toThrow('INVALID_ISSUE_IDS');
    expect(fetcher).not.toHaveBeenCalled();
  });
});
