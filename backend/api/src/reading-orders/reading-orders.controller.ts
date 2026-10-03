import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Headers,
  Inject,
  Put,
  Query,
  Req,
} from '@nestjs/common';
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsUUID,
  Matches,
  Max,
  Min,
} from 'class-validator';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { bodyPipe } from '../social/interactions.controller.js';
import { catalogLanguage } from '../catalog/catalog.service.js';
import { ReadingOrdersService } from './reading-orders.service.js';
class OrderMutationDTO {
  @IsUUID('4') mutationID!: string;
  @IsInt() @Min(0) @Max(2147483646) version!: number;
  @Matches(/^[a-z0-9-]{1,80}$/) orderID!: string;
  @IsIn(['following', 'voted']) action!: 'following' | 'voted';
  @IsBoolean() enabled!: boolean;
}
@Controller('me/reading-orders')
export class ReadingOrdersController {
  constructor(
    @Inject(ReadingOrdersService)
    private readonly service: ReadingOrdersService,
  ) {}
  @Get() read(
    @Req() r: AuthenticatedRequest,
    @Headers('accept-language') lang: string | undefined,
    @Query() q: Record<string, unknown>,
  ) {
    if (Object.keys(q).length)
      throw new BadRequestException({ code: 'INVALID_ORDER_REQUEST' });
    return this.service.read(r.identity.uid, catalogLanguage(lang));
  }
  @Put() mutate(
    @Req() r: AuthenticatedRequest,
    @Headers('accept-language') lang: string | undefined,
    @Body(bodyPipe(OrderMutationDTO)) b: OrderMutationDTO,
  ) {
    return this.service.mutate(r.identity.uid, catalogLanguage(lang), b);
  }
}
