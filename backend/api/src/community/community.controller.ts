import { catalogLanguage } from '../catalog/catalog.service.js';
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
  Patch,
  Header,
  Headers,
  Query,
  Req,
} from '@nestjs/common';
import {
  IsBoolean,
  IsOptional,
  IsArray,
  ArrayMaxSize,
  ArrayUnique,
  IsUUID,
  IsIn,
  IsInt,
  Min,
  Max,
  IsISO8601,
  IsString,
  Length,
  Matches,
  ValidateIf,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { ImagesService } from './images.service.js';
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
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(4)
  @ArrayUnique()
  @IsUUID('4', { each: true })
  imageIDs?: string[];
  @IsOptional() @IsIn(['discussion', 'theory', 'duel', 'room']) kind?:
    'discussion' | 'theory' | 'duel' | 'room';
  @IsOptional() @IsUUID('4') clubID?: string;
  @IsOptional() @IsUUID('4') scheduleID?: string;
  @IsOptional() @IsString() @Length(1, 120) @Matches(/\S/u) optionA?: string;
  @IsOptional() @IsString() @Length(1, 120) @Matches(/\S/u) optionB?: string;
  @IsOptional() @IsISO8601() closesAt?: string;
  @IsOptional() @IsInt() @Min(0) @Max(2) segment?: number;
}
class EditPostDTO {
  @IsString() @Length(1, 140) @Matches(/\S/u) title!: string;
  @IsString() @Length(1, 5000) @Matches(/\S/u) text!: string;
  @IsBoolean() spoiler!: boolean;
  @IsArray()
  @ArrayMaxSize(4)
  @ArrayUnique()
  @IsUUID('4', { each: true })
  imageIDs!: string[];
  @IsInt() @Min(1) version!: number;
  @IsUUID('4') mutationID!: string;
}
class ReplyDTO extends CommentDTO {
  @IsOptional() @IsUUID('4') parentID?: string;
}
class ImageDTO {
  @IsString() @Length(4, 2800000) base64!: string;
}
class VoteDTO {
  @IsInt() @Min(0) @Max(1) choice!: number;
}
class ResolveDTO {
  @IsIn(['open', 'confirmed', 'refuted']) status!: string;
  @IsString() @Length(1, 1000) @Matches(/\S/u) note!: string;
  @IsInt() @Min(1) version!: number;
}
const uuid = new ParseUUIDPipe({ version: '4' });
@Controller('posts')
export class CommunityController {
  private readonly interactions: InteractionsService;
  constructor(
    @Inject(CommunityService) private readonly service: CommunityService,
    @Inject(ImagesService) private readonly images: ImagesService,
    @Inject(InteractionsService) interactions: InteractionsService,
  ) {
    this.interactions = interactions.forPosts();
  }
  @Get() list(
    @Req() req: AuthenticatedRequest,
    @Query() q: Record<string, unknown>,
    @Headers('accept-language') language?: string,
  ) {
    if (
      Object.keys(q).some(
        (k) =>
          ![
            'universe',
            'item',
            'after',
            'q',
            'feed',
            'kind',
            'club',
            'schedule',
            'segment',
          ].includes(k),
      ) ||
      ['universe', 'item'].some(
        (k) =>
          q[k] !== undefined &&
          (typeof q[k] !== 'string' || !/^[\w-]{1,120}$/.test(q[k])),
      )
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    if (
      (q.q !== undefined && (typeof q.q !== 'string' || q.q.length > 120)) ||
      (q.feed !== undefined &&
        !['recent', 'following', 'active', 'unanswered'].includes(
          q.feed as string,
        )) ||
      (q.kind !== undefined &&
        !['discussion', 'theory', 'duel', 'room'].includes(q.kind as string)) ||
      ['club', 'schedule'].some(
        (k) =>
          q[k] !== undefined &&
          (typeof q[k] !== 'string' ||
            !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
              q[k],
            )),
      )
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    if (
      q.segment !== undefined &&
      (typeof q.segment !== 'string' || !/^[012]$/.test(q.segment))
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.service.list(req.identity.uid, {
      language: catalogLanguage(language),
      segment: q.segment === undefined ? undefined : Number(q.segment),
      search: q.q as string | undefined,
      feed: q.feed as string | undefined,
      kind: q.kind as string | undefined,
      club: q.club as string | undefined,
      schedule: q.schedule as string | undefined,
      universe: q.universe as string | undefined,
      item: q.item as string | undefined,
      cursor: cursor(q.after === undefined ? {} : { after: q.after }),
    });
  }
  @Get(':id') detail(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.service.list(req.identity.uid, {
      id,
      language: catalogLanguage(req.headers['accept-language']),
    });
  }
  @Put(':id') publish(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(PostDTO)) body: PostDTO,
  ) {
    return this.service.publish(req.identity.uid, id, body);
  }
  @Patch(':id') edit(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(EditPostDTO)) body: EditPostDTO,
  ) {
    return this.service.edit(req.identity.uid, id, body);
  }
  @Put(':id/images/:imageID') upload(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('imageID', uuid) image: string,
    @Body(bodyPipe(ImageDTO)) body: ImageDTO,
  ) {
    return this.images.upload(req.identity.uid, id, image, body.base64);
  }
  @Get(':id/images/:imageID')
  @Header('Cache-Control', 'private, no-store')
  image(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('imageID', uuid) image: string,
  ) {
    return this.images.image(req.identity.uid, id, image);
  }
  @Put(':id/vote') vote(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(VoteDTO)) body: VoteDTO,
  ) {
    return this.service.vote(req.identity.uid, id, body.choice);
  }
  @Put(':id/resolution') resolve(
    @Req() req: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ResolveDTO)) body: ResolveDTO,
  ) {
    return this.service.resolve(
      req.identity.uid,
      id,
      body.status,
      body.note,
      body.version,
    );
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
    @Body(bodyPipe(ReplyDTO)) body: ReplyDTO,
  ) {
    return this.interactions.post(
      req.identity.uid,
      id,
      comment,
      body.text,
      body.spoiler,
      body.parentID,
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
