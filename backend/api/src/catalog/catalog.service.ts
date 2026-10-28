import {
  publishedItemRelations,
  itemFields,
  normalizedTitle,
} from './catalog-sql.js';
import {
  browseCatalog,
  catalogSeriesPage,
  resolveCatalog,
} from './catalog-navigation.js';
import { Inject, Injectable } from '@nestjs/common';
import type { QueryResultRow } from 'pg';
import { DatabaseService } from '../database/database.service.js';

export function catalogLanguage(header = ''): 'pt-BR' | 'en' {
  const languages = header
    .split(',')
    .map((entry) => {
      const [tag, ...parameters] = entry.trim().toLowerCase().split(';');
      const quality = parameters.find((p) => p.trim().startsWith('q='));
      return { tag, q: quality ? Number(quality.trim().slice(2)) : 1 };
    })
    .filter(({ q }) => q > 0 && q <= 1)
    .sort((a, b) => b.q - a.q);
  for (const { tag } of languages) {
    if (/^en(?:-|$)/.test(tag)) return 'en';
    if (/^pt(?:-|$)/.test(tag)) return 'pt-BR';
  }
  return 'pt-BR';
}

export interface CatalogItemRow extends QueryResultRow {
  id: string;
  uni: string;
  type: string;
  title: string;
  year: string;
  avg: number;
  logCount: number;
  reviewCount: number;
  ratingHistogram: number[];
  canon: string;
  desc: string;
}

@Injectable()
export class CatalogService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async page(
    locale: 'pt-BR' | 'en',
    universeID: string,
    query: {
      type?: string;
      search: string;
      after?: string;
      limit: number;
    },
  ) {
    const search = query.search
      .trim()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase();
    const params = [locale, universeID, query.type ?? null, search];
    const conditions = `i.status='published' AND i.universe_id=$2
      AND ($3::text IS NULL OR i.type=$3) AND strpos(${normalizedTitle},$4)>0`;
    return this.db.transaction(async (client) => {
      await client.query(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
      );
      const count = await client.query<{ total: number }>(
        `SELECT count(*)::int AS total FROM ${publishedItemRelations} WHERE ${conditions}`,
        params,
      );
      const page = await client.query<CatalogItemRow>(
        `WITH selected AS MATERIALIZED (
          SELECT i.id FROM ${publishedItemRelations} WHERE ${conditions}
          AND ($5::text IS NULL OR i.id COLLATE "C">$5 COLLATE "C")
          ORDER BY i.id COLLATE "C" LIMIT $6
        ) SELECT ${itemFields} FROM ${publishedItemRelations}
          JOIN selected ON selected.id=i.id
          JOIN catalog_item_statistics s ON s.item_id=i.id
          ORDER BY i.id COLLATE "C"`,
        [...params, query.after ?? null, query.limit + 1],
      );
      const items = page.rows.slice(0, query.limit);
      return {
        locale,
        total: count.rows[0].total,
        items,
        nextCursor: page.rows.length > items.length ? items.at(-1)!.id : null,
      };
    });
  }

  async item(locale: 'pt-BR' | 'en', universeID: string, id: string) {
    const result = await this.db.query<CatalogItemRow>(
      `SELECT ${itemFields} FROM ${publishedItemRelations}
       JOIN catalog_item_statistics s ON s.item_id=i.id
       WHERE i.status='published' AND i.universe_id=$2 AND i.id=$3`,
      [locale, universeID, id],
    );
    return result.rows[0];
  }

  browse(locale: 'pt-BR' | 'en', query: Record<string, unknown>) {
    return this.db.transaction((client) =>
      browseCatalog(client, locale, query),
    );
  }
  series(locale: 'pt-BR' | 'en', query: Record<string, unknown>, id?: string) {
    return this.db.transaction((client) =>
      catalogSeriesPage(client, locale, query, id),
    );
  }
  resolve(locale: 'pt-BR' | 'en', query: Record<string, unknown>) {
    return this.db.transaction((client) =>
      resolveCatalog(client, locale, query),
    );
  }

  async snapshot(locale: 'pt-BR' | 'en', bounded = false) {
    return this.db.transaction(async (client) => {
      // Universes, totals and items must describe the same published snapshot.
      await client.query(
        'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
      );
      const universes = await client.query(
        `SELECT u.id, u.status, coalesce(t.name,p.name) AS name,
          u.color AS c,u.dark_color AS c2,u.ink_color AS ink,u.track,
          coalesce(t.canon,p.canon) AS canon,coalesce(t.tagline,p.tagline) AS tagline,
          0 AS base,
          (SELECT count(*)::int FROM catalog_items i JOIN catalog_item_translations ip ON ip.item_id=i.id AND ip.locale='pt-BR'
           WHERE i.universe_id=u.id AND i.status='published') AS total,
          (SELECT count(*)::int FROM onboarding o JOIN profiles profile USING(firebase_uid)
           WHERE o.completed AND u.id=ANY(o.universe_ids) AND profile.deletion_requested_at IS NULL) AS members,
          0 AS live
         FROM catalog_universes u
         JOIN catalog_universe_translations p ON p.universe_id=u.id AND p.locale='pt-BR'
         LEFT JOIN catalog_universe_translations t ON t.universe_id=u.id AND t.locale=$1
         WHERE u.status IN ('active','coming_soon') ORDER BY u.sort_order,u.id`,
        [locale],
      );
      const items = await client.query<CatalogItemRow>(
        `SELECT ${itemFields} FROM ${publishedItemRelations}
         JOIN catalog_item_statistics s ON s.item_id=i.id
         WHERE i.status='published' AND (NOT $2::boolean OR i.id IN (
           SELECT id FROM (
             SELECT i.id,i.type,
               row_number() OVER(PARTITION BY i.universe_id,(i.type='Personagem') ORDER BY i.sort_order,i.id) AS editorial,
               row_number() OVER(PARTITION BY i.universe_id,(i.type IN ('Personagem','Evento')) ORDER BY i.sort_order,i.id) AS discovery,
               row_number() OVER(PARTITION BY i.universe_id,(i.type='Personagem') ORDER BY s.average DESC,i.id) AS rated
             FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id AND u.status='active'
             JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
             JOIN catalog_item_statistics s ON s.item_id=i.id WHERE i.status='published'
           ) choices WHERE type<>'Personagem' AND (editorial<=15 OR rated<=8 OR (type<>'Evento' AND discovery<=8))
         )) ORDER BY i.sort_order,i.id`,
        [locale, bounded],
      );
      const average = bounded
        ? await client.query(`SELECT coalesce(avg(s.average),0)::float8 AS average
        FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id AND u.status='active'
        JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
        JOIN catalog_item_statistics s ON s.item_id=i.id WHERE i.status='published'`)
        : null;
      return {
        ...(bounded
          ? {
              discoveryIDs: items.rows
                .filter((i) => !['Personagem', 'Evento'].includes(i.type))
                .slice(0, 8)
                .map((i) => i.id),
              onboardingIDs: universes.rows.flatMap((u) =>
                items.rows
                  .filter((i) => i.uni === u.id && i.type !== 'Personagem')
                  .slice(0, 15)
                  .map((i) => i.id),
              ),
              topRatedIDs: universes.rows.flatMap((u) =>
                items.rows
                  .filter((i) => i.uni === u.id && i.type !== 'Personagem')
                  .sort(
                    (a, b) => b.avg - a.avg || a.id.localeCompare(b.id, 'en'),
                  )
                  .slice(0, 8)
                  .map((i) => i.id),
              ),
              aggregateAverage: average!.rows[0].average,
            }
          : {}),
        version: 1,
        locale,
        universes: universes.rows
          .filter((u) => u.status === 'active')
          .map(({ status: _status, ...u }) => u),
        comingSoon: universes.rows
          .filter((u) => u.status === 'coming_soon')
          .map((u) => ({ id: u.id, name: u.name })),
        items: items.rows,
      };
    });
  }
}
