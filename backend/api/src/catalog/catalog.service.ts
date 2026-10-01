import { Inject, Injectable } from '@nestjs/common';
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

@Injectable()
export class CatalogService {
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async snapshot(locale: 'pt-BR' | 'en') {
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
      const items = await client.query(
        `SELECT i.id,i.universe_id AS uni,i.type,coalesce(t.title,p.title) AS title,
          coalesce(t.year,p.year) AS year,s.average AS avg,s.log_count AS "logCount",s.review_count AS "reviewCount",
          coalesce(t.canon,p.canon) AS canon,coalesce(t.description,p.description) AS "desc"
         FROM catalog_items i JOIN catalog_universes u ON u.id=i.universe_id AND u.status='active'
         JOIN catalog_item_statistics s ON s.item_id=i.id
         JOIN catalog_universe_translations up ON up.universe_id=u.id AND up.locale='pt-BR'
         JOIN catalog_item_translations p ON p.item_id=i.id AND p.locale='pt-BR'
         LEFT JOIN catalog_item_translations t ON t.item_id=i.id AND t.locale=$1
         WHERE i.status='published' ORDER BY i.sort_order,i.id`,
        [locale],
      );
      return {
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
