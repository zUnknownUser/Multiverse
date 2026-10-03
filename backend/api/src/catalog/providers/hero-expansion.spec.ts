import type { PoolClient } from 'pg';
import {
  normalizeDCIssue,
  expansionMapping,
  publishHeroExpansion,
} from './hero-expansion.js';
import {
  metronDCRegistry,
  tmdbExpansionRegistry,
} from './hero-expansion-registry.js';
import { parseTMDB } from './tmdb.js';
const mapping = metronDCRegistry.find((m) => m.id === 4743)!;
function issue() {
  return {
    id: mapping.id,
    publisher: { id: 2, name: 'DC Comics' },
    series: {
      id: mapping.seriesID,
      name: mapping.series,
      year_began: mapping.year,
      language: 'en',
    },
    number: mapping.number,
    cover_date: '1986-09-01',
    desc: 'The Comedian dies.',
    image: 'https://static.metron.cloud/media/issue/watchmen-1.jpg',
    credits: [],
    characters: [],
  };
}
describe('Reviewed hero expansion', () => {
  it('binds DC editions to reviewed identities and Portuguese adaptations', () => {
    const c = normalizeDCIssue(issue(), 4743);
    expect(c.suggestedItemId).toBe('d-metron-issue-4743');
    expect(c.metadata.descriptions['pt-BR']).toContain('Comediante');
    expect(expansionMapping(c)).toMatchObject({
      universe: 'dc',
      artworkOnly: false,
      existing: false,
    });
  });
  it('rejects a wrong publisher, series or issue number', () => {
    for (const change of [
      { publisher: { id: 1, name: 'Marvel' } },
      { series: { ...issue().series, id: 999 } },
      { number: '2' },
    ])
      expect(() => normalizeDCIssue({ ...issue(), ...change }, 4743)).toThrow();
  });
  it('rejects reassignment and missing localization', () => {
    const c = normalizeDCIssue(issue(), 4743);
    expect(() =>
      expansionMapping({ ...c, suggestedItemId: 'd-watchmen' }),
    ).toThrow('CATALOG_MAPPING_CONFLICT');
    c.metadata.descriptions['pt-BR'] = '';
    expect(() => expansionMapping(c)).toThrow('CATALOG_TRANSLATION_REQUIRED');
  });
  it('recognizes existing DC films without changing identity', () => {
    const m = tmdbExpansionRegistry.find((m) => m.itemId === 'd-tdk')!;
    const c = parseTMDB(
      {
        id: m.id,
        title: m.title,
        release_date: '2008-07-16',
        overview: 'Batman confronts the Joker.',
        translations: {
          translations: [
            {
              iso_639_1: 'pt',
              iso_3166_1: 'BR',
              data: {
                title: 'O Cavaleiro das Trevas',
                overview: 'Batman enfrenta o Coringa.',
              },
            },
          ],
        },
      },
      m,
    );
    expect(expansionMapping(c)).toMatchObject({
      universe: 'dc',
      existing: true,
    });
  });
  it('rejects incomplete publication before touching the database', async () => {
    const query = vi.fn();
    await expect(
      publishHeroExpansion({ query } as unknown as PoolClient, []),
    ).rejects.toThrow('CATALOG_INCOMPLETE_HERO_BATCH');
    expect(query).not.toHaveBeenCalled();
  });
});
