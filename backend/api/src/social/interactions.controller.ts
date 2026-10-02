import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import {
  IsBoolean,
  IsIn,
  IsString,
  Length,
  Matches,
  ValidateIf,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { InteractionsService } from './interactions.service.js';
import type { FeedCursor } from './social.service.js';

export class CommentDTO {
  @IsString() @Length(1, 2000) @Matches(/\S/u) text!: string;
  @IsBoolean() spoiler!: boolean;
}
export class ReactionDTO {
  @ValidateIf((_o: unknown, value: unknown) => value !== null)
  @IsIn(['POW!', 'ZAP!', 'KRAK!', 'HEH'])
  reaction!: string | null;
  @IsBoolean() liked!: boolean;
}
class PermissionDTO {
  @IsIn(['everyone', 'following', 'nobody']) commentPermission!: string;
}
export class ReportDTO {
  @IsIn(['spoiler', 'offensive', 'spam', 'wrong_canon', 'other'])
  reason!: string;
  @IsBoolean() alsoBlock!: boolean;
}
export const bodyPipe = (expectedType: new () => object) =>
  new ValidationPipe({
    expectedType,
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
    exceptionFactory: () =>
      new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' }),
  });
const uuid = new ParseUUIDPipe({ version: '4' });
export function cursor(query: Record<string, unknown>): FeedCursor | undefined {
  if (Object.keys(query).some((k) => k !== 'after'))
    throw new BadRequestException({ code: 'INVALID_FEED_CURSOR' });
  if (query.after === undefined) return undefined;
  try {
    if (
      typeof query.after !== 'string' ||
      query.after.length > 300 ||
      !/^[\w-]+$/.test(query.after)
    )
      throw new Error();
    const value = JSON.parse(
      Buffer.from(query.after, 'base64url').toString(),
    ) as FeedCursor;
    if (
      !value ||
      typeof value.time !== 'string' ||
      typeof value.id !== 'string' ||
      !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/.test(value.time) ||
      !Number.isFinite(Date.parse(value.time)) ||
      !/^[\da-f]{8}-[\da-f]{4}-4[\da-f]{3}-[89ab][\da-f]{3}-[\da-f]{12}$/i.test(
        value.id,
      )
    )
      throw new Error();
    return value;
  } catch {
    throw new BadRequestException({ code: 'INVALID_FEED_CURSOR' });
  }
}
@Controller()
export class InteractionsController {
  constructor(
    @Inject(InteractionsService) private readonly service: InteractionsService,
  ) {}
  @Put('me/comment-permission') permission(
    @Req() req: AuthenticatedRequest,
    @Body(bodyPipe(PermissionDTO)) input: PermissionDTO,
  ) {
    return this.service.permission(req.identity.uid, input.commentPermission);
  }
  @Get('reviews/:id/comments') comments(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Query() query: Record<string, unknown>,
  ) {
    return this.service.comments(req.identity.uid, id, cursor(query));
  }
  @Put('reviews/:id/comments/:commentID') post(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) commentID: string,
    @Body(bodyPipe(CommentDTO)) input: CommentDTO,
  ) {
    return this.service.post(
      req.identity.uid,
      id,
      commentID,
      input.text,
      input.spoiler,
    );
  }
  @Put('reviews/:id/reaction') react(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ReactionDTO)) input: ReactionDTO,
  ) {
    return this.service.react(
      req.identity.uid,
      id,
      undefined,
      input.reaction,
      input.liked,
    );
  }
  @Put('reviews/:id/comments/:commentID/reaction') reactComment(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) commentID: string,
    @Body(bodyPipe(ReactionDTO)) input: ReactionDTO,
  ) {
    return this.service.react(
      req.identity.uid,
      id,
      commentID,
      input.reaction,
      input.liked,
    );
  }
  @Put('reviews/:id/comments/:commentID/report') report(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) commentID: string,
    @Body(bodyPipe(ReportDTO)) input: ReportDTO,
  ) {
    return this.service.reportComment(
      req.identity.uid,
      id,
      commentID,
      input.reason,
      input.alsoBlock,
    );
  }
}
