// Explicit editorial mappings: a title search cannot distinguish a film, event,
// series, issue, collected edition or character with the same name.
export interface MarvelMapping {
  itemId: string;
  entityId: string;
  type: 'HQ' | 'Personagem' | 'Evento' | 'Filme' | 'Série';
  expectedEnglishTitle: string;
}
export const marvelRegistry: readonly MarvelMapping[] = [
  {
    itemId: 'm-fenix',
    entityId: 'Q60349',
    type: 'HQ',
    expectedEnglishTitle: 'The Dark Phoenix Saga',
  },
  {
    itemId: 'm-secret',
    entityId: 'Q19363451',
    type: 'HQ',
    expectedEnglishTitle: 'Secret Wars',
  },
  {
    itemId: 'm-infinity-gauntlet',
    entityId: 'Q2762009',
    type: 'HQ',
    expectedEnglishTitle: 'The Infinity Gauntlet',
  },
  {
    itemId: 'm-house-of-m',
    entityId: 'Q1072636',
    type: 'HQ',
    expectedEnglishTitle: 'House of M',
  },
  {
    itemId: 'm-spider-man',
    entityId: 'Q79037',
    type: 'Personagem',
    expectedEnglishTitle: 'Spider-Man',
  },
];
