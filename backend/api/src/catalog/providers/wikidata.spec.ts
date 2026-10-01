import { fetchMarvelMetadata, parseWikidata } from './wikidata.js';
import { marvelRegistry } from './marvel-registry.js';

const mapping = marvelRegistry[0];
function entity() {
  return {
    entities: {
      [mapping.entityId]: {
        id: mapping.entityId,
        lastrevid: 123,
        labels: {
          en: { value: mapping.expectedEnglishTitle },
          pt: { value: 'Título PT' },
          'pt-br': { value: 'Título BR' },
        },
        descriptions: { en: { value: 'English description' } },
        claims: {
          P580: [
            {
              mainsnak: {
                datavalue: {
                  value: { time: '+1980-00-00T00:00:00Z', precision: 9 },
                },
              },
            },
          ],
          P50: [
            { mainsnak: { datavalue: { value: { id: 'Q1' } } } },
            {
              rank: 'deprecated',
              mainsnak: { datavalue: { value: { id: 'Q2' } } },
            },
          ],
        },
      },
    },
  };
}
describe('Wikidata Marvel connector', () => {
  it('uses Brazilian labels and preserves missing translations and date precision', () => {
    const parsed = parseWikidata(entity(), mapping);
    expect(parsed.metadata).toEqual({
      titles: { 'pt-BR': 'Título BR', en: mapping.expectedEnglishTitle },
      descriptions: { 'pt-BR': '', en: 'English description' },
      year: '1980',
      creatorIds: ['Q1'],
      publisherIds: [],
    });
    expect(parsed.sourceUrl).toBe(
      'https://www.wikidata.org/wiki/' + mapping.entityId,
    );
  });
  it('rejects missing, mismatched and redirected entities before importing', () => {
    expect(() => parseWikidata({}, mapping)).toThrow('WIKIDATA_INVALID_ENTITY');
    const data = entity();
    data.entities[mapping.entityId].labels.en.value = 'Different adaptation';
    expect(() => parseWikidata(data, mapping)).toThrow(
      'WIKIDATA_INVALID_ENTITY',
    );
  });
  it('fetches only fixed provider URLs, with timeout and identification', async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockResolvedValue(new Response(JSON.stringify(entity())));
    expect(await fetchMarvelMetadata([mapping], transport)).toHaveLength(1);
    expect(transport).toHaveBeenCalledWith(
      'https://www.wikidata.org/wiki/Special:EntityData/' +
        mapping.entityId +
        '.json',
      expect.objectContaining({
        signal: expect.any(AbortSignal),
        redirect: 'error',
      }),
    );
    await expect(
      fetchMarvelMetadata([{ ...mapping, entityId: '../private' }], transport),
    ).rejects.toThrow('INVALID_ENTITY_ID');
    expect(transport).toHaveBeenCalledTimes(1);
  });
  it('stops on rate limit without retry storms or a partial successful batch', async () => {
    const transport = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify(entity())))
      .mockResolvedValueOnce(new Response('', { status: 429 }));
    await expect(
      fetchMarvelMetadata(marvelRegistry, transport),
    ).rejects.toThrow('HTTP 429');
    expect(transport).toHaveBeenCalledTimes(2);
  });
  it('rejects oversized and malformed responses', async () => {
    await expect(
      fetchMarvelMetadata(
        [mapping],
        vi
          .fn<typeof fetch>()
          .mockResolvedValue(
            new Response('{}', { headers: { 'content-length': '3000000' } }),
          ),
      ),
    ).rejects.toThrow('TOO_LARGE');
    await expect(
      fetchMarvelMetadata(
        [mapping],
        vi.fn<typeof fetch>().mockResolvedValue(new Response('{}')),
      ),
    ).rejects.toThrow('INVALID_ENTITY');
  });
});
