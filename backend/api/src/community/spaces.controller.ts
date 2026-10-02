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
  IsInt,
  IsOptional,
  IsString,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { bodyPipe, ReportDTO } from '../social/interactions.controller.js';
import { SpacesService } from './spaces.service.js';
class ClubDTO {
  @IsString() @Length(1, 80) @Matches(/\S/u) name!: string;
  @IsString() @Length(1, 1000) @Matches(/\S/u) description!: string;
  @IsString() @Matches(/^[\w-]{1,120}$/) universeID!: string;
  @IsOptional() @IsInt() @Min(1) version?: number;
}
class JoinDTO {
  @IsBoolean() joined!: boolean;
}
class ScheduleDTO {
  @IsString() @Matches(/^[\w-]{1,120}$/) itemID!: string;
  @IsString() @Matches(/^\d{4}-\d{2}-\d{2}$/) startsOn!: string;
  @IsInt() @Min(1) @Max(10000) totalUnits!: number;
  @IsString() @Length(1, 30) @Matches(/\S/u) unitLabel!: string;
}
class ProgressDTO {
  @IsInt() @Min(0) @Max(10000) units!: number;
}
class VisitDTO {
  @IsOptional() @IsInt() @Min(0) @Max(100) progress?: number;
}
const uuid = new ParseUUIDPipe({ version: '4' });
const uuidRE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function query(q: Record<string, unknown>, keys: string[]) {
  if (
    Object.keys(q).some((k) => !keys.includes(k)) ||
    Object.values(q).some((v) => typeof v !== 'string' || v.length > 120)
  )
    throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
  return q as Record<string, string>;
}
@Controller('community')
export class SpacesController {
  constructor(@Inject(SpacesService) private readonly service: SpacesService) {}
  @Get('clubs') list(
    @Req() r: AuthenticatedRequest,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = query(raw, ['q', 'after', 'universe']);
    if (q.after && !uuidRE.test(q.after))
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.service.list(r.identity.uid, q.q ?? '', q.after, q.universe);
  }
  @Get('clubs/:id') detail(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.service.detail(r.identity.uid, id);
  }
  @Put('clubs/:id') save(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ClubDTO)) b: ClubDTO,
  ) {
    return this.service.save(r.identity.uid, id, b);
  }
  @Delete('clubs/:id') remove(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
  ) {
    return this.service.remove(r.identity.uid, id);
  }
  @Put('clubs/:id/membership') join(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(JoinDTO)) b: JoinDTO,
  ) {
    return this.service.membership(r.identity.uid, id, b.joined);
  }
  @Get('clubs/:id/members') members(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = query(raw, ['schedule', 'after']);
    if (q.schedule && !uuidRE.test(q.schedule))
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.service.members(r.identity.uid, id, q.schedule, q.after);
  }
  @Put('clubs/:id/schedule/:schedule') schedule(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('schedule', uuid) schedule: string,
    @Body(bodyPipe(ScheduleDTO)) b: ScheduleDTO,
  ) {
    const date = new Date(b.startsOn + 'T00:00:00Z');
    if (
      !Number.isFinite(date.getTime()) ||
      date.toISOString().slice(0, 10) !== b.startsOn
    )
      throw new BadRequestException({ code: 'INVALID_SOCIAL_REQUEST' });
    return this.service.schedule(r.identity.uid, id, schedule, b);
  }
  @Delete('clubs/:id/schedule/:schedule') removeSchedule(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('schedule', uuid) schedule: string,
  ) {
    return this.service.removeSchedule(r.identity.uid, id, schedule);
  }
  @Put('clubs/:id/schedule/:schedule/progress') progress(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Param('schedule', uuid) schedule: string,
    @Body(bodyPipe(ProgressDTO)) b: ProgressDTO,
  ) {
    return this.service.progress(r.identity.uid, id, schedule, b.units);
  }
  @Put('clubs/:id/report') report(
    @Req() r: AuthenticatedRequest,
    @Param('id', uuid) id: string,
    @Body(bodyPipe(ReportDTO)) b: ReportDTO,
  ) {
    return this.service.report(r.identity.uid, id, b.reason, b.alsoBlock);
  }
  @Get('rooms') rooms(
    @Req() r: AuthenticatedRequest,
    @Query() raw: Record<string, unknown>,
  ) {
    const q = query(raw, ['q', 'after', 'universe']);
    return this.service.rooms(r.identity.uid, q.q ?? '', q.after, q.universe);
  }
  @Put('rooms/:item/visit') visit(
    @Req() r: AuthenticatedRequest,
    @Param('item') item: string,
    @Body(bodyPipe(VisitDTO)) b: VisitDTO,
  ) {
    return this.service.visit(r.identity.uid, item, b.progress);
  }
}
