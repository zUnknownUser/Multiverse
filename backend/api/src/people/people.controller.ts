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
  ValidationPipe,
} from '@nestjs/common';
import { IsBoolean } from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { PeopleService } from './people.service.js';

class FollowDTO {
  @IsBoolean() following!: boolean;
}

@Controller()
export class PeopleController {
  constructor(@Inject(PeopleService) private readonly people: PeopleService) {}

  private query(query: Record<string, unknown>, suggestions: boolean) {
    if (
      Object.keys(query).some((k) => !['q', 'after', 'limit'].includes(k)) ||
      Object.values(query).some((v) => typeof v !== 'string')
    )
      throw new BadRequestException({ code: 'INVALID_PEOPLE_QUERY' });
    const { q = '', after, limit = '20' } = query as Record<string, string>;
    if (
      q.length > 80 ||
      !/^[1-9]\d?$/.test(limit) ||
      Number(limit) > 50 ||
      (after && !/^[a-z0-9_.]{3,24}$/.test(after))
    )
      throw new BadRequestException({ code: 'INVALID_PEOPLE_QUERY' });
    return {
      search: q.trim(),
      after: after || undefined,
      limit: Number(limit),
      suggestions,
    };
  }
  private id(id: string) {
    if (
      !id ||
      id.length > 128 ||
      id.split('').some((char) => char.charCodeAt(0) < 32)
    )
      throw new BadRequestException({ code: 'INVALID_PERSON' });
    return id;
  }
  @Get('people') search(
    @Req() req: AuthenticatedRequest,
    @Query() query: Record<string, unknown>,
  ) {
    return this.people.list(req.identity.uid, this.query(query, false));
  }
  @Get('people/suggestions') suggestions(
    @Req() req: AuthenticatedRequest,
    @Query() query: Record<string, unknown>,
  ) {
    return this.people.list(req.identity.uid, this.query(query, true));
  }
  @Get('people/:id') detail(
    @Req() req: AuthenticatedRequest,
    @Param('id') id: string,
  ) {
    return this.people.detail(req.identity.uid, this.id(id));
  }
  @Put('me/follows/:id') follow(
    @Req() req: AuthenticatedRequest,
    @Param('id') id: string,
    @Body(
      new ValidationPipe({
        expectedType: FollowDTO,
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
        exceptionFactory: () =>
          new BadRequestException({ code: 'INVALID_FOLLOW' }),
      }),
    )
    body: FollowDTO,
  ) {
    return this.people.follow(req.identity.uid, this.id(id), body.following);
  }
}
