import { BadRequestException, NotFoundException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { PoolClient } from 'pg';
import { itemFields, publishedItemRelations } from './catalog-sql.js';
import type { CatalogItemRow } from './catalog.service.js';

const invalid = () =>
  new BadRequestException({ code: 'INVALID_CATALOG_QUERY' });
const validID = (id: string) => /^[a-z0-9][a-z0-9_-]{0,79}$/.test(id);
function parameters(raw: Record<string, unknown>, allowed: string[]) {
  if (
    Object.keys(raw).some((k) => !allowed.includes(k)) ||
    Object.values(raw).some((v) => typeof v !== 'string')
  )
    throw invalid();
  return raw as Record<string, string | undefined>;
}
function pageSize(value: string | undefined, fallback: number, max: number) {
  const size = value === undefined ? fallback : Number(value);
  if (!Number.isInteger(size) || size < 1 || size > max) throw invalid();
  return size;
}
function scopeOf(values: unknown[]) {
  return createHash('sha256').update(JSON.stringify(values)).digest('hex');
}
function decode(
  after: string | undefined,
  scope: string,
): { id: string; position: number } | undefined {
  if (!after) return undefined;
  try {
    if (after.length > 1000) throw invalid();
    const value = JSON.parse(Buffer.from(after, 'base64url').toString());
    if (
      value.scope !== scope ||
      typeof value.id !== 'string' ||
      !validID(value.id) ||
      !Number.isSafeInteger(value.position) ||
      value.position < 0
    )
      throw invalid();
    return value;
  } catch {
    throw invalid();
  }
}
function encode(scope: string, id: string, position = 0) {
  return Buffer.from(JSON.stringify({ scope, id, position })).toString(
    'base64url',
  );
}
const normalize = (value: string) =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();

export async function browseCatalog(
  client: PoolClient,
  locale: string,
  raw: Record<string, unknown>,
) {
  const q = parameters(raw, [
    'q',
    'category',
    'universe',
    'series',
    'limit',
    'after',
  ]);
  const limit = pageSize(q.limit, 30, 50),
    category = q.category ?? 'all',
    search = q.q?.trim() ?? '';
  if (
    !['all', 'works', 'characters', 'events', 'consumable'].includes(
      category,
    ) ||
    search.length > 200 ||
    (q.universe !== undefined && !validID(q.universe)) ||
    (q.series !== undefined && !validID(q.series))
  )
    throw invalid();
  const scope = scopeOf([
    'items',
    locale,
    category,
    search,
    q.universe,
    q.series,
  ]);
  const cursor = decode(q.after, scope);
  await client.query(
    'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
  );
  const conditions = `i.status='published' AND ($2::text IS NULL OR i.universe_id=$2) AND ($3::text IS NULL OR cs.id=$3)
    AND ($4='all' OR ($4='works' AND i.type NOT IN ('Personagem','Evento')) OR ($4='characters' AND i.type='Personagem')
      OR ($4='events' AND i.type='Evento') OR ($4='consumable' AND i.type<>'Personagem'))
    AND NOT EXISTS(SELECT 1 FROM unnest($5::text[]) word WHERE strpos(lower(regexp_replace(normalize(
      coalesce(t.title,p.title)||' '||coalesce(ut.name,up.name),NFD),'[\u0300-\u036f]','','g')),word)=0)`;
  const relations = `${publishedItemRelations} LEFT JOIN catalog_universe_translations ut ON ut.universe_id=u.id AND ut.locale=$1`;
  const params = [
    locale,
    q.universe ?? null,
    q.series ?? null,
    category,
    normalize(search).split(/\s+/).filter(Boolean),
  ];
  const count = await client.query<{ total: number }>(
    `SELECT count(*)::int AS total FROM ${relations} WHERE ${conditions}`,
    params,
  );
  const position = `CASE WHEN $3::text IS NULL THEN 0 ELSE csi.position END`;
  const result = await client.query<CatalogItemRow & { position: number }>(
    `WITH selected AS MATERIALIZED (
      SELECT i.id,${position} AS position FROM ${relations} WHERE ${conditions}
      AND ($6::text IS NULL OR (${position},i.id COLLATE "C")>($7::int,$6 COLLATE "C"))
      ORDER BY position,i.id COLLATE "C" LIMIT $8)
    SELECT ${itemFields},selected.position FROM ${publishedItemRelations}
    JOIN selected ON selected.id=i.id JOIN catalog_item_statistics s ON s.item_id=i.id
    ORDER BY selected.position,i.id COLLATE "C"`,
    [...params, cursor?.id ?? null, cursor?.position ?? 0, limit + 1],
  );
  const rows = result.rows.slice(0, limit),
    last = rows.at(-1);
  return {
    locale,
    total: count.rows[0].total,
    items: rows.map(({ position: _position, ...item }) => item),
    nextCursor:
      result.rows.length > limit && last
        ? encode(scope, last.id, last.position)
        : null,
  };
}

export async function resolveCatalog(
  client: PoolClient,
  locale: string,
  raw: Record<string, unknown>,
) {
  const query = parameters(raw, ['ids']);
  const ids = query.ids?.split(',') ?? [];
  if (
    !ids.length ||
    ids.length > 50 ||
    ids.some((id) => !validID(id)) ||
    new Set(ids).size !== ids.length
  )
    throw invalid();
  const result = await client.query<CatalogItemRow>(
    `SELECT ${itemFields} FROM ${publishedItemRelations}
    JOIN catalog_item_statistics s ON s.item_id=i.id WHERE i.status='published' AND i.id=ANY($2::text[]) ORDER BY i.id`,
    [locale, ids],
  );
  const found = new Set(result.rows.map((i) => i.id));
  return {
    locale,
    items: result.rows,
    missingIDs: ids.filter((id) => !found.has(id)),
  };
}

export async function catalogSeriesPage(
  client: PoolClient,
  locale: string,
  raw: Record<string, unknown>,
  id?: string,
) {
  const q = parameters(raw, ['universe', 'limit', 'after']);
  const limit = pageSize(q.limit, 20, 30);
  if (
    (q.universe !== undefined && !validID(q.universe)) ||
    (id !== undefined && !validID(id))
  )
    throw invalid();
  const scope = scopeOf(['series', locale, q.universe]);
  const cursor = decode(q.after, scope);
  await client.query(
    'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
  );
  const common = `FROM catalog_series cs JOIN catalog_universes u ON u.id=cs.universe_id AND u.status='active'
    JOIN catalog_series_translations p ON p.series_id=cs.id AND p.locale='pt-BR'
    LEFT JOIN catalog_series_translations t ON t.series_id=cs.id AND t.locale=$1
    JOIN catalog_series_items csi ON csi.series_id=cs.id
    JOIN catalog_items i ON i.id=csi.item_id AND i.universe_id=cs.universe_id AND i.status='published'
    JOIN catalog_item_translations ip ON ip.item_id=i.id AND ip.locale='pt-BR'
    WHERE ($2::text IS NULL OR cs.universe_id=$2) AND ($3::text IS NULL OR cs.id=$3)`;
  const total = await client.query<{ total: number }>(
    `SELECT count(DISTINCT cs.id)::int AS total ${common}`,
    [locale, q.universe ?? null, id ?? null],
  );
  const result = await client.query(
    `SELECT cs.id,coalesce(t.title,p.title) AS title,cs.year,cs.universe_id AS universe,count(*)::int AS total
    ${common} AND ($4::text IS NULL OR cs.id COLLATE "C">$4 COLLATE "C")
    GROUP BY cs.id,t.title,p.title ORDER BY cs.id COLLATE "C" LIMIT $5`,
    [locale, q.universe ?? null, id ?? null, cursor?.id ?? null, limit + 1],
  );
  if (id) {
    if (!result.rowCount)
      throw new NotFoundException({ code: 'CATALOG_SERIES_NOT_FOUND' });
    return result.rows[0];
  }
  const series = result.rows.slice(0, limit);
  return {
    locale,
    total: total.rows[0].total,
    series,
    nextCursor:
      result.rows.length > limit ? encode(scope, series.at(-1)!.id) : null,
  };
}
