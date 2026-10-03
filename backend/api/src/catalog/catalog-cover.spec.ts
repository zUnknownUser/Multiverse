import { providerCoverURL } from './catalog-cover.js';

describe('Catalog artwork URLs', () => {
  it('accepts only provider CDN artwork paths', () => {
    expect(
      providerCoverURL('tmdb', 'https://image.tmdb.org/t/p/w500/abc123.jpg'),
    ).toBeDefined();
    expect(
      providerCoverURL(
        'metron',
        'https://static.metron.cloud/media/issue/2019/07/14/civil-war-v1-1.jpg',
      ),
    ).toBeDefined();
  });
  it.each([
    null,
    'http://static.metron.cloud/media/issue/a.jpg',
    'https://static.metron.cloud.evil.test/media/issue/a.jpg',
    'https://static.metron.cloud@evil.test/media/issue/a.jpg',
    'https://static.metron.cloud/media/issue/../a.jpg',
    'https://static.metron.cloud/media/issue/a.jpg?token=secret',
    'https://static.metron.cloud/media/issue/a.svg',
    'https://image.tmdb.org/t/p/w500/abc.jpg',
  ])('rejects an unsafe or mismatched Metron image %s', (value) => {
    expect(providerCoverURL('metron', value)).toBeUndefined();
  });
});
