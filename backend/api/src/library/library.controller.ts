import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Inject,
  Put,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { LibraryService } from './library.service.js';
import { LibraryMutationDTO } from './library.dto.js';
@Controller('me/library')
export class LibraryController {
  constructor(
    @Inject(LibraryService) private readonly service: LibraryService,
  ) {}
  @Get() read(@Req() req: AuthenticatedRequest) {
    return this.service.read(req.identity.uid);
  }
  @Put() mutate(
    @Req() req: AuthenticatedRequest,
    @Body(
      new ValidationPipe({
        expectedType: LibraryMutationDTO,
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
        exceptionFactory: () =>
          new BadRequestException({ code: 'INVALID_LIBRARY_REQUEST' }),
      }),
    )
    input: LibraryMutationDTO,
  ) {
    const fields: Record<string, string[]> = {
      wanted: ['itemID', 'enabled'],
      favorite: ['itemID', 'enabled'],
      create_list: ['listID', 'title', 'description'],
      update_list: ['listID', 'title', 'description'],
      delete_list: ['listID'],
      add_item: ['listID', 'itemID'],
      remove_item: ['listID', 'itemID'],
    };
    const required = [
      'mutationID',
      'version',
      'action',
      ...fields[input.action],
    ];
    if (
      Object.keys(input).filter(
        (key) =>
          (input as unknown as Record<string, unknown>)[key] !== undefined,
      ).length !== required.length ||
      required.some(
        (key) => (input as unknown as Record<string, unknown>)[key] == null,
      )
    )
      throw new BadRequestException({ code: 'INVALID_LIBRARY_REQUEST' });
    return this.service.mutate(req.identity.uid, input);
  }
}
