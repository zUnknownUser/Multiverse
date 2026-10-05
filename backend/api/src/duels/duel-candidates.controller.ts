import {
  Controller,
  Get,
  Put,
  Delete,
  Header,
  Inject,
  Param,
  ParseUUIDPipe,
  Req,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { DuelCandidatesService } from './duel-candidates.service.js';
@Controller('community/duel-candidates')
export class DuelCandidatesController {
  constructor(
    @Inject(DuelCandidatesService)
    private readonly service: DuelCandidatesService,
  ) {}
  @Get('mine')
  @Header('Cache-Control', 'no-store')
  mine(@Req() r: AuthenticatedRequest) {
    return this.service.mine(r.identity.uid);
  }
  @Get('posts/:id')
  @Header('Cache-Control', 'no-store')
  status(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.status(r.identity.uid, id);
  }
  @Put('posts/:id')
  @Header('Cache-Control', 'no-store')
  submit(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.submit(r.identity.uid, id);
  }
  @Delete('posts/:id')
  @Header('Cache-Control', 'no-store')
  withdraw(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.withdraw(r.identity.uid, id);
  }
}
