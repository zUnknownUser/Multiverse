import {
  Controller,
  Get,
  Header,
  Headers,
  Inject,
  Param,
  ParseUUIDPipe,
  Req,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { catalogLanguage } from '../catalog/catalog.service.js';
import { DailyDuelsService } from './daily-duels.service.js';
@Controller('community/daily-duels')
export class DailyDuelsController {
  constructor(
    @Inject(DailyDuelsService) private readonly service: DailyDuelsService,
  ) {}
  @Get()
  @Header('Cache-Control', 'no-store')
  current(
    @Req() r: AuthenticatedRequest,
    @Headers('accept-language') language?: string,
  ) {
    return this.service.current(r.identity.uid, catalogLanguage(language));
  }
  @Get('leaderboard')
  @Header('Cache-Control', 'no-store')
  leaderboard(@Req() r: AuthenticatedRequest) {
    return this.service.leaderboard(r.identity.uid);
  }
  @Get(':id')
  @Header('Cache-Control', 'no-store')
  detail(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Headers('accept-language') language?: string,
  ) {
    return this.service.detail(r.identity.uid, id, catalogLanguage(language));
  }
}
