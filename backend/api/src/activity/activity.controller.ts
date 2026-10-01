import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Inject,
  Param,
  ParseUUIDPipe,
  Put,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { catalogLanguage } from '../catalog/catalog.service.js';
import { ActivityService } from './activity.service.js';
import { SaveLogDTO } from './activity.dto.js';

@Controller('me')
export class ActivityController {
  constructor(
    @Inject(ActivityService) private readonly activity: ActivityService,
  ) {}
  @Get('activity') read(
    @Req() req: AuthenticatedRequest,
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.read(req.identity.uid, catalogLanguage(language));
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
    @Headers('accept-language') language?: string,
  ) {
    return this.activity.save(
      req.identity.uid,
      id,
      body,
      catalogLanguage(language),
    );
  }
}
