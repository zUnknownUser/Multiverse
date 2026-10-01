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
    return this.catalog.page(catalogLanguage(language), 'marvel', {
      type: type || undefined,
      search: q,
      after: after || undefined,
      limit: Number(limit),
    });
  }

  async detail(id: string, language?: string) {
    const locale = catalogLanguage(language);
    if (!/^[a-z0-9-]{1,80}$/.test(id))
      throw new NotFoundException({ code: 'CATALOG_ITEM_NOT_FOUND' });
    const item = await this.catalog.item(locale, 'marvel', id);
    if (!item) throw new NotFoundException({ code: 'CATALOG_ITEM_NOT_FOUND' });
    const sources = await this.db.query(
      `SELECT provider,external_id AS "externalId",source_url AS url,
      revision::text,metadata,fetched_at AS "fetchedAt" FROM catalog_sources WHERE item_id=$1 ORDER BY provider`,
      [id],
    );
    return { locale, item, sources: sources.rows };
  }
}
