import type { Response } from 'express';
import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  Put,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import { IsOptional, IsInt, Min, Max } from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { bodyPipe } from '../social/interactions.controller.js';
import { RoomsService } from './rooms.service.js';
import { spaceQuery } from './space-query.js';
class VisitDTO {
  @IsOptional() @IsInt() @Min(0) @Max(100) progress?: number;
}
@Controller('community')
export class RoomsController {
  constructor(@Inject(RoomsService) private readonly service: RoomsService) {}
  @Get('rooms') rooms(
    @Req() r: AuthenticatedRequest,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = spaceQuery(raw, ['q', 'after', 'universe']);
    return this.service.rooms(r.identity.uid, q.q ?? '', q.after, q.universe);
  }
  @Get('rooms/:item/changes') async changes(
    @Req() r: AuthenticatedRequest,
    @Res({ passthrough: true }) response: Response,
    @Param('item') item: string,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = spaceQuery(raw, ['after']);
    if (
      !/^[\w-]{1,120}$/.test(item) ||
      (q.after !== undefined && !/^(0|[1-9][0-9]{0,19})$/.test(q.after))
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    const abort = new AbortController();
    const close = () => abort.abort();
    response.once('close', close);
    try {
      return await this.service.changes(
        r.identity.uid,
        item,
        q.after,
        abort.signal,
      );
    } finally {
      response.removeListener('close', close);
    }
  }
  @Put('rooms/:item/visit') visit(
    @Req() r: AuthenticatedRequest,
    @Param('item') item: string,
    @Body(bodyPipe(VisitDTO)) b: VisitDTO,
  ) {
    return this.service.visit(r.identity.uid, item, b.progress);
  }
}
