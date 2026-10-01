import { Controller, Get, Header, Headers, Inject } from '@nestjs/common';
import { Public } from '../auth/firebase-auth.guard.js';
import { CatalogService, catalogLanguage } from './catalog.service.js';

@Controller('catalog')
export class CatalogController {
  constructor(
    @Inject(CatalogService) private readonly catalog: CatalogService,
  ) {}

  @Public()
  @Get()
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  snapshot(@Headers('accept-language') language?: string) {
    return this.catalog.snapshot(catalogLanguage(language));
  }
}
