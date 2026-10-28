import { BadRequestException } from '@nestjs/common';

export interface ActivityQuery {
  limit: number;
  after?: string;
  search: string;
  selection: string;
  year?: number;
  timeZone: string;
  itemId?: string;
  universeId?: string;
}

export function activityQuery(
  raw: Record<string, unknown>,
): ActivityQuery | undefined {
  if (!Object.keys(raw).length) return undefined; // Published clients retain the full snapshot.
  const fail = () => {
    throw new BadRequestException({ code: 'INVALID_ACTIVITY_QUERY' });
  };
  if (
    Object.keys(raw).some(
      (k) =>
        ![
          'limit',
          'after',
          'search',
          'selection',
          'year',
          'timeZone',
          'itemId',
          'universeId',
        ].includes(k),
    ) ||
    Object.values(raw).some((v) => typeof v !== 'string')
  )
    fail();
  const values = raw as Record<string, string | undefined>;
  const limit = Number(values.limit ?? 30);
  const year = values.year === undefined ? undefined : Number(values.year);
  const timeZone = String(values.timeZone ?? 'UTC');
  if (
    !Number.isInteger(limit) ||
    limit < 1 ||
    limit > 100 ||
    (year !== undefined &&
      (!Number.isInteger(year) || year < 1 || year > 9999)) ||
    String(values.search ?? '').length > 200 ||
    String(values.after ?? '').length > 1000 ||
    timeZone.length > 100 ||
    (values.itemId !== undefined &&
      !/^[a-z0-9][a-z0-9_-]{0,79}$/.test(values.itemId)) ||
    (values.universeId !== undefined &&
      !['marvel', 'dc'].includes(values.universeId)) ||
    !['all', 'liked', 'rated', 'rewatched', 'reviewed'].includes(
      String(values.selection ?? 'all'),
    )
  )
    fail();
  try {
    new Intl.DateTimeFormat('en', { timeZone }).format();
  } catch {
    fail();
  }
  return {
    limit,
    itemId: values.itemId,
    universeId: values.universeId,
    year,
    timeZone,
    search: String(values.search ?? '').trim(),
    selection: String(values.selection ?? 'all'),
    after: values.after as string | undefined,
  };
}
