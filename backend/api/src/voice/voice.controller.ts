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
  Req,
} from '@nestjs/common';
import { IsInt, Max, Min } from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { bodyPipe } from '../social/interactions.controller.js';
import { VoiceService } from './voice.service.js';
class VoiceJoinDTO {
  @IsInt() @Min(0) @Max(2) segment!: number;
}
const uuid = new ParseUUIDPipe({ version: '4' });
@Controller('community')
export class VoiceController {
  constructor(@Inject(VoiceService) private readonly voice: VoiceService) {}
  @Get('voice') availability() {
    return this.voice.availability();
  }
  @Put('rooms/:item/voice/:id') join(
    @Req() r: AuthenticatedRequest,
    @Param('item') item: string,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(VoiceJoinDTO)) body: VoiceJoinDTO,
  ) {
    if (!/^[\w-]{1,120}$/.test(item))
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.voice.join(r.identity.uid, item, body.segment, id);
  }
  @Put('voice/:id/heartbeat') heartbeat(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.voice.heartbeat(r.identity.uid, id);
  }
  @Delete('voice/:id') leave(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.voice.leave(r.identity.uid, id);
  }
}
