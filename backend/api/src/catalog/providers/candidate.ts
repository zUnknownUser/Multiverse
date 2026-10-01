// Private review data, never a replacement for editorial copy or user ratings.
export interface CatalogCandidate {
  provider: 'tmdb' | 'metron';
  externalId: string;
  suggestedItemId: string;
  type: 'HQ' | 'Filme' | 'Série';
  kind: 'issue' | 'movie' | 'tv';
  sourceUrl: string;
  fetchedAt: string;
  attribution: { name: string; url: string; termsUrl: string };
  metadata: {
    titles: Record<'pt-BR' | 'en', string>;
    descriptions: Record<'pt-BR' | 'en', string>;
    year: string;
    releaseDate: string;
    coverDate?: string;
    runtimeMinutes?: number;
    pageCount?: number;
    posterURL?: string;
    series?: { id: number; title: string; year: number; number: string };
    creators: { id: number; name: string; roles: string[] }[];
    characters: { id: number; name: string }[];
  };
}

export function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
export function records(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value) ? value.slice(0, 500).map(record) : [];
}
export function plainText(value: unknown, max = 4000): string {
  if (typeof value !== 'string') return '';
  // Stored only as plain text. No provider HTML is rendered in a web view.
  return (
    value
      .slice(0, 20_000)
      .replace(/<[^>]*>/g, ' ')
      // oxlint-disable-next-line no-control-regex -- Deliberately remove provider control characters.
      .replace(/[\u0000-\u001f\u007f]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, max)
  );
}
export function positiveInt(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}
export function date(value: unknown): string {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value))
    return '';
  const parsed = new Date(value);
  return Number.isFinite(parsed.valueOf()) &&
    parsed.toISOString().slice(0, 10) === value
    ? value
    : '';
}
