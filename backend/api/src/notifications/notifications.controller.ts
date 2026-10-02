import {
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
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsString,
  IsUUID,
  Length,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { bodyPipe, cursor } from '../social/interactions.controller.js';
import { NotificationsService } from './notifications.service.js';
class ReadDTO {
  @IsArray()
  @ArrayMaxSize(100)
  @ArrayUnique()
  @IsUUID('4', { each: true })
  ids!: string[];
}
class PreferencesDTO {
  @IsBoolean() activity!: boolean;
  @IsBoolean() push!: boolean;
}
class DeviceDTO {
  @IsString() @Length(20, 4096) token!: string;
}
@Controller('me')
export class NotificationsController {
  constructor(
    @Inject(NotificationsService)
    private readonly service: NotificationsService,
  ) {}
  @Get('notifications') list(
    @Req() r: AuthenticatedRequest,
    @Query() q: Record<string, unknown>,
  ) {
    return this.service.list(r.identity.uid, cursor(q));
  }
  @Put('notifications/read') read(
    @Req() r: AuthenticatedRequest,
    @Body(bodyPipe(ReadDTO)) b: ReadDTO,
  ) {
    return this.service.read(r.identity.uid, b.ids);
  }
  @Get('notification-preferences') preferences(@Req() r: AuthenticatedRequest) {
    return this.service.preferences(r.identity.uid);
  }
  @Put('notification-preferences') savePreferences(
    @Req() r: AuthenticatedRequest,
    @Body(bodyPipe(PreferencesDTO)) b: PreferencesDTO,
  ) {
    return this.service.preferences(r.identity.uid, b);
  }
  @Put('push-devices/:id') device(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
    @Body(bodyPipe(DeviceDTO)) b: DeviceDTO,
  ) {
    return this.service.device(r.identity.uid, id, b.token);
  }
  @Delete('push-devices/:id') removeDevice(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.device(r.identity.uid, id);
  }
}
