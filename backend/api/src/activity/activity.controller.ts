import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  Inject,
  Param,
  Patch,
  ParseUUIDPipe,
  Put,
  Req,
  Query,
  ValidationPipe,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { catalogLanguage } from '../catalog/catalog.service.js';
import { ActivityService } from './activity.service.js';
import { activityQuery } from './activity-query.js';
import { SaveLogDTO } from './activity.dto.js';

@Controller('me')
export class ActivityController {
  constructor(
    @Inject(ActivityService) private readonly activity: ActivityService,
  ) {}
  @Get('activity') read(
    @Req() req: AuthenticatedRequest,
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.read(
      req.identity.uid,
      catalogLanguage(language),
      activityQuery(query),
    );
  }
  @Put('diary/:id') save(
    @Req() req: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body(
      new ValidationPipe({
        expectedType: SaveLogDTO,
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
        exceptionFactory: () =>
          new BadRequestException({ code: 'INVALID_LOG' }),
      }),
    )
    body: SaveLogDTO,
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.save(
      req.identity.uid,
      id,
      body,
      catalogLanguage(language),
      false,
      activityQuery(query),
    );
  }

  @Patch('diary/:id') update(
    @Req() req: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body(
      new ValidationPipe({
        expectedType: SaveLogDTO,
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
        exceptionFactory: () =>
          new BadRequestException({ code: 'INVALID_LOG' }),
      }),
    )
    body: SaveLogDTO,
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.save(
      req.identity.uid,
      id,
      body,
      catalogLanguage(language),
      true,
      activityQuery(query),
    );
  }

  @Delete('diary/:id') remove(
    @Req() req: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.remove(
      req.identity.uid,
      id,
      catalogLanguage(language),
      activityQuery(query),
    );
  }
}
