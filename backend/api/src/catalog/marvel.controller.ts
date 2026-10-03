import {
  Controller,
  Get,
  Header,
  Headers,
  Inject,
  Param,
  Query,
} from '@nestjs/common';
import { Public } from '../auth/firebase-auth.guard.js';
import { MarvelService } from './marvel.service.js';

@Controller('catalog/:universe')
export class MarvelController {
  constructor(@Inject(MarvelService) private readonly marvel: MarvelService) {}
  @Public()
  @Get()
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  list(
    @Headers('accept-language') language: string | undefined,
    @Query() query: Record<string, unknown>,
    @Param('universe') universe: string,
  ) {
    return this.marvel.list(language, query, universe);
  }
  @Public()
  @Get(':id')
  @Header('Vary', 'Accept-Language')
  @Header('Cache-Control', 'no-store')
  detail(
    @Param('id') id: string,
    @Param('universe') universe: string,
    @Headers('accept-language') language?: string,
  ) {
    return this.marvel.detail(id, language, universe);
  }
}
