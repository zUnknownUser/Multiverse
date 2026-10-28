import {
  Controller,
  Get,
  Header,
  Headers,
  Inject,
  Query,
  Param,
} from '@nestjs/common';
import { Public } from '../auth/firebase-auth.guard.js';
import { CatalogService, catalogLanguage } from './catalog.service.js';

@Controller('catalog')
export class CatalogController {
  constructor(
    @Inject(CatalogService) private readonly catalog: CatalogService,
  ) {}

  @Public()
  @Get('bootstrap')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  bootstrap(@Headers('accept-language') language?: string) {
    return this.catalog.snapshot(catalogLanguage(language), true);
  }

  @Public()
  @Get('items')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  items(
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.catalog.browse(catalogLanguage(language), query);
  }

  @Public()
  @Get('series')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  series(
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.catalog.series(catalogLanguage(language), query);
  }

  @Public()
  @Get('series/:id')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  seriesDetail(
    @Param('id') id: string,
    @Headers('accept-language') language?: string,
  ) {
    return this.catalog.series(catalogLanguage(language), {}, id);
  }

  @Public()
  @Get('resolve')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  resolve(
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.catalog.resolve(catalogLanguage(language), query);
  }

  @Public()
  @Get()
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  snapshot(@Headers('accept-language') language?: string) {
    return this.catalog.snapshot(catalogLanguage(language));
  }
}
