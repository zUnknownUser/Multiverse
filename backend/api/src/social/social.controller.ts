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
  Query,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import { IsBoolean, IsIn } from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { catalogLanguage } from '../catalog/catalog.service.js';
import { SocialService, type FeedCursor } from './social.service.js';
class PrivacyDTO {
  @IsBoolean() publicDiary!: boolean;
}
class BlockDTO {
  @IsBoolean() blocked!: boolean;
}
class ReportDTO {
  @IsIn(['spoiler', 'offensive', 'spam', 'wrong_canon', 'other'])
  reason!: string;
  @IsBoolean() alsoBlock!: boolean;
}
const bodyPipe = (expectedType: new () => object) =>
  new ValidationPipe({
    expectedType,
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
    exceptionFactory: () =>
      new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' }),
  });
@Controller()
export class SocialController {
  constructor(@Inject(SocialService) private readonly social: SocialService) {}
  @Get('feed') feed(
    @Req() req: AuthenticatedRequest,
    @Query() query: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    if (
      Object.keys(query).some((k) => !['after', 'limit'].includes(k)) ||
      Object.values(query).some((v) => typeof v !== 'string')
    )
      throw new BadRequestException({ code: 'INVALID_FEED_CURSOR' });
    const limit = query.limit ?? '20';
    if (
      typeof limit !== 'string' ||
      !/^[1-9]\d?$/.test(limit) ||
      Number(limit) > 50
    )
      throw new BadRequestException({ code: 'INVALID_FEED_CURSOR' });
    let cursor: FeedCursor | undefined;
    if (query.after !== undefined) {
      try {
        if (
          typeof query.after !== 'string' ||
          query.after.length > 300 ||
          !/^[\w-]+$/.test(query.after)
        )
          throw new Error();
        const parsed: unknown = JSON.parse(
          Buffer.from(query.after, 'base64url').toString(),
        );
        if (
          !parsed ||
          typeof parsed !== 'object' ||
          !('time' in parsed) ||
          !('id' in parsed) ||
          typeof parsed.time !== 'string' ||
          typeof parsed.id !== 'string' ||
          !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(parsed.time) ||
          !Number.isFinite(Date.parse(parsed.time)) ||
          !/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i.test(
            parsed.id,
          )
        )
          throw new Error();
        cursor = { time: parsed.time, id: parsed.id };
      } catch {
        throw new BadRequestException({ code: 'INVALID_FEED_CURSOR' });
      }
    }
    return this.social.feed(
      req.identity.uid,
      catalogLanguage(language),
      Number(limit),
      cursor,
    );
  }
  @Get('reviews/:id') detail(
    @Req() req: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Headers('accept-language') language?: string,
  ) {
    return this.social.feed(
      req.identity.uid,
      catalogLanguage(language),
      1,
      undefined,
      id,
    );
  }
  @Get('me/privacy') privacy(@Req() req: AuthenticatedRequest) {
    return this.social.privacy(req.identity.uid);
  }
  @Put('me/privacy') savePrivacy(
    @Req() req: AuthenticatedRequest,
    @Body(bodyPipe(PrivacyDTO)) body: PrivacyDTO,
  ) {
    return this.social.privacy(req.identity.uid, body.publicDiary);
  }
  @Get('me/blocks') blocks(@Req() req: AuthenticatedRequest) {
    return this.social.blocks(req.identity.uid);
  }
  @Put('me/blocks/:id') block(
    @Req() req: AuthenticatedRequest,
    @Param('id') id: string,
    @Body(bodyPipe(BlockDTO)) body: BlockDTO,
  ) {
    if (!id || id.length > 128)
      throw new BadRequestException({ code: 'INVALID_BLOCK' });
    return this.social.setBlock(req.identity.uid, id, body.blocked);
  }
  @Put('reviews/:id/report') report(
    @Req() req: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body(bodyPipe(ReportDTO)) body: ReportDTO,
  ) {
    return this.social.report(
      req.identity.uid,
      id,
      body.reason,
      body.alsoBlock,
    );
  }
}
