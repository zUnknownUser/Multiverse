import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Header,
  Inject,
  Param,
  ParseUUIDPipe,
  Put,
  Query,
  Req,
  Res,
} from '@nestjs/common';
import {
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Length,
  Matches,
} from 'class-validator';
import type { Response } from 'express';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import {
  bodyPipe,
  cursor,
  ReportDTO,
} from '../social/interactions.controller.js';
import { MessagesService } from './messages.service.js';
class MessageDTO {
  @IsIn(['text', 'workCard']) kind!: 'text' | 'workCard';
  @IsString() @Length(0, 2000) text!: string;
  @IsOptional() @IsString() @Matches(/^[\w-]{1,120}$/) itemID?: string;
  @IsBoolean() spoiler!: boolean;
}
class DecisionDTO {
  @IsBoolean() accepted!: boolean;
}
class ReadDTO {
  @IsString() @Matches(/^(0|[1-9][0-9]{0,17})$/) through!: string;
}
function query(q: Record<string, unknown>, allowed: string[]) {
  if (
    Object.keys(q).some(
      (k) =>
        !allowed.includes(k) ||
        typeof q[k] !== 'string' ||
        (q[k] as string).length > 1000,
    )
  )
    throw new BadRequestException({ code: 'INVALID_MESSAGE' });
  return q as Record<string, string>;
}
function peer(id: string) {
  if (!/^[A-Za-z0-9_.:@-]{1,128}$/.test(id))
    throw new BadRequestException({ code: 'INVALID_MESSAGE' });
  return id;
}
const uuid = new ParseUUIDPipe({ version: '4' });
@Controller('me/messages')
export class MessagesController {
  constructor(
    @Inject(MessagesService) private readonly service: MessagesService,
  ) {}
  @Header('Cache-Control', 'no-store')
  @Get()
  inbox(@Req() r: AuthenticatedRequest, @Query() raw: Record<string, unknown>) {
    const q = query(raw, ['after']);
    return this.service.inbox(r.identity.uid, cursor(q));
  }
  @Header('Cache-Control', 'no-store')
  @Get('changes')
  async changes(
    @Req() r: AuthenticatedRequest,
    @Res({ passthrough: true }) response: Response,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = query(raw, ['after']);
    if (q.after !== undefined && !/^(0|[1-9][0-9]{0,17})$/.test(q.after))
      throw new BadRequestException({ code: 'INVALID_MESSAGE' });
    const abort = new AbortController();
    const close = () => abort.abort();
    response.once('close', close);
    try {
      return await this.service.changes(r.identity.uid, q.after, abort.signal);
    } finally {
      response.removeListener('close', close);
    }
  }
  @Header('Cache-Control', 'no-store')
  @Get(':peer')
  history(
    @Req() r: AuthenticatedRequest,
    @Param('peer') id: string,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = query(raw, ['before']);
    if (q.before !== undefined && !/^[1-9][0-9]{0,17}$/.test(q.before))
      throw new BadRequestException({ code: 'INVALID_MESSAGE' });
    return this.service.history(r.identity.uid, peer(id), q.before);
  }
  @Header('Cache-Control', 'no-store')
  @Put(':peer/messages/:id')
  send(
    @Req() r: AuthenticatedRequest,
    @Param('peer') other: string,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(MessageDTO)) b: MessageDTO,
  ) {
    return this.service.send(r.identity.uid, peer(other), id, b);
  }
  @Header('Cache-Control', 'no-store')
  @Put(':peer/request')
  decide(
    @Req() r: AuthenticatedRequest,
    @Param('peer') other: string,
    @Body(bodyPipe(DecisionDTO)) b: DecisionDTO,
  ) {
    return this.service.decide(r.identity.uid, peer(other), b.accepted);
  }
  @Header('Cache-Control', 'no-store')
  @Put(':peer/read')
  read(
    @Req() r: AuthenticatedRequest,
    @Param('peer') other: string,
    @Body(bodyPipe(ReadDTO)) b: ReadDTO,
  ) {
    return this.service.read(r.identity.uid, peer(other), b.through);
  }
  @Header('Cache-Control', 'no-store')
  @Put(':peer/messages/:id/report')
  report(
    @Req() r: AuthenticatedRequest,
    @Param('peer') other: string,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ReportDTO)) b: ReportDTO,
  ) {
    return this.service.report(
      r.identity.uid,
      peer(other),
      id,
      b.reason,
      b.alsoBlock,
    );
  }
}
