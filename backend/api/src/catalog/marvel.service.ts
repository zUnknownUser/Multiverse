import {
  BadRequestException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';
import { CatalogService, catalogLanguage } from './catalog.service.js';

// All reads use our published PostgreSQL catalog; no provider requests on the user's path.
@Injectable()
export class MarvelService {
  constructor(
    @Inject(CatalogService) private readonly catalog: CatalogService,
    @Inject(DatabaseService) private readonly db: DatabaseService,
  ) {}

  async list(language: string | undefined, query: Record<string, unknown>) {
    if (
      Object.keys(query).some(
        (k) => !['type', 'q', 'limit', 'after'].includes(k),
      ) ||
      Object.values(query).some((v) => typeof v !== 'string')
    )
      throw new BadRequestException({ code: 'INVALID_CATALOG_QUERY' });
    const {
      type,
      q = '',
      limit = '20',
      after,
    } = query as Record<string, string>;
    if (
      (type &&
        !['HQ', 'Personagem', 'Evento', 'Filme', 'Série'].includes(type)) ||
      q.length > 120 ||
      !/^[1-9]\d?$/.test(limit) ||
      Number(limit) > 50 ||
      (after && !/^[a-z0-9-]{1,80}$/.test(after))
    )
      throw new BadRequestException({ code: 'INVALID_CATALOG_QUERY' });
    const locale = catalogLanguage(language);
    const snapshot = await this.catalog.snapshot(locale);
    const normalize = (value: string) =>
      value
        .normalize('NFD')
        .replace(/\p{Diacritic}/gu, '')
        .toLowerCase();
    const matches = snapshot.items
      .filter(
        (i) =>
          i.uni === 'marvel' &&
          (!type || i.type === type) &&
          normalize(i.title).includes(normalize(q.trim())),
      )
      .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    const remaining = matches.filter((i) => !after || i.id > after);
    const items = remaining.slice(0, Number(limit));
    return {
      locale,
      total: matches.length,
      items,
      nextCursor: remaining.length > items.length ? items.at(-1)?.id : null,
    };
  }

  async detail(id: string, language?: string) {
    const locale = catalogLanguage(language);
    const snapshot = await this.catalog.snapshot(locale);
    const item = snapshot.items.find((i) => i.uni === 'marvel' && i.id === id);
    if (!item) throw new NotFoundException({ code: 'CATALOG_ITEM_NOT_FOUND' });
    const sources = await this.db.query(
      `SELECT provider,external_id AS "externalId",source_url AS url,
      revision::text,metadata,fetched_at AS "fetchedAt" FROM catalog_sources WHERE item_id=$1 ORDER BY provider`,
      [id],
    );
    return { locale, item, sources: sources.rows };
  }
}
