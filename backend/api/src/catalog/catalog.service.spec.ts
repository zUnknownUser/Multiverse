import { catalogLanguage } from './catalog.service.js';

describe('Catalog language negotiation', () => {
  it.each([
    [undefined, 'pt-BR'],
    ['en-US,en;q=0.9', 'en'],
    ['pt-PT,en;q=0.5', 'pt-BR'],
    ['fr-FR,en;q=0.8', 'en'],
    ['en;q=0,pt-BR;q=0.5', 'pt-BR'],
    ['pt;q=0.2,en;q=0.9', 'en'],
    ['de-DE', 'pt-BR'],
    ['en;q=garbage', 'pt-BR'],
  ])('resolves %s as %s', (header, expected) => {
    expect(catalogLanguage(header)).toBe(expected);
  });
});
