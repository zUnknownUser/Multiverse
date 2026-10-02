import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  Req,
} from '@nestjs/common';
import {
  IsBoolean,
  IsString,
  Length,
  Matches,
  ValidateIf,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { CommunityService } from './community.service.js';
import { InteractionsService } from '../social/interactions.service.js';
import {
  bodyPipe,
  CommentDTO,
  ReactionDTO,
  ReportDTO,
  cursor,
} from '../social/interactions.controller.js';
class PostDTO {
  @IsString() @Length(1, 120) @Matches(/^[\w-]+$/) universeID!: string;
  @ValidateIf((_o: unknown, v: unknown) => v !== null)
  @IsString()
  @Length(1, 120)
  @Matches(/^[\w-]+$/)
  itemID!: string | null;
  @IsString() @Length(1, 140) @Matches(/\S/u) title!: string;
  @IsString() @Length(1, 5000) @Matches(/\S/u) text!: string;
  @IsBoolean() spoiler!: boolean;
}
const uuid = new ParseUUIDPipe({ version: '4' });
@Controller('posts')
export class CommunityController {
  private readonly interactions: InteractionsService;
  constructor(
    @Inject(CommunityService) private readonly service: CommunityService,
    @Inject(InteractionsService) interactions: InteractionsService,
  ) {
    this.interactions = interactions.forPosts();
  }
  @Get() list(
    @Req() req: AuthenticatedRequest,
    @Query() q: Record<string, unknown>,
  ) {
    if (
      Object.keys(q).some((k) => !['universe', 'item', 'after'].includes(k)) ||
      ['universe', 'item'].some(
        (k) =>
          q[k] !== undefined &&
          (typeof q[k] !== 'string' || !/^[\w-]{1,120}$/.test(q[k])),
      )
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.service.list(req.identity.uid, {
      universe: q.universe as string | undefined,
      item: q.item as string | undefined,
      cursor: cursor(q.after === undefined ? {} : { after: q.after }),
    });
  }
  @Get(':id') detail(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.service.list(req.identity.uid, { id });
  }
  @Put(':id') publish(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(PostDTO)) body: PostDTO,
  ) {
    return this.service.publish(req.identity.uid, id, body);
  }
  @Delete(':id') remove(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.service.remove(req.identity.uid, id);
  }
  @Put(':id/report') report(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ReportDTO)) body: ReportDTO,
  ) {
    return this.service.report(
      req.identity.uid,
      id,
      body.reason,
      body.alsoBlock,
    );
  }
  @Get(':id/comments') comments(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Query() q: Record<string, unknown>,
  ) {
    return this.interactions.comments(req.identity.uid, id, cursor(q));
  }
  @Put(':id/comments/:commentID') comment(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) comment: string,
    @Body(bodyPipe(CommentDTO)) body: CommentDTO,
  ) {
    return this.interactions.post(
      req.identity.uid,
      id,
      comment,
      body.text,
      body.spoiler,
    );
  }
  @Put(':id/reaction') react(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ReactionDTO)) body: ReactionDTO,
  ) {
    return this.interactions.react(
      req.identity.uid,
      id,
      undefined,
      body.reaction,
      body.liked,
    );
  }
  @Put(':id/comments/:commentID/reaction') reactComment(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) comment: string,
    @Body(bodyPipe(ReactionDTO)) body: ReactionDTO,
  ) {
    return this.interactions.react(
      req.identity.uid,
      id,
      comment,
      body.reaction,
      body.liked,
    );
  }
  @Put(':id/comments/:commentID/report') reportComment(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('commentID', uuid) comment: string,
    @Body(bodyPipe(ReportDTO)) body: ReportDTO,
  ) {
    return this.interactions.reportComment(
      req.identity.uid,
      id,
      comment,
      body.reason,
      body.alsoBlock,
    );
  }
}
