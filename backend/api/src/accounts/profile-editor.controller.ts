import { ProfileEditDTO } from './profile-editor.dto.js';
import {
  Body,
  Controller,
  Get,
  Header,
  Inject,
  Param,
  ParseUUIDPipe,
  Put,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { ProfileEditorService } from './profile-editor.service.js';
@Controller()
export class ProfileEditorController {
  constructor(
    @Inject(ProfileEditorService)
    private readonly service: ProfileEditorService,
  ) {}
  @Put('me/profile/details') save(
    @Req() r: AuthenticatedRequest,
    @Body(
      new ValidationPipe({
        expectedType: ProfileEditDTO,
        transform: true,
        whitelist: true,
        forbidNonWhitelisted: true,
      }),
    )
    input: ProfileEditDTO,
  ) {
    return this.service.save(r.identity.uid, input);
  }
  @Get('people/photos/:id') @Header('Cache-Control', 'private, no-store') photo(
    @Req() r: AuthenticatedRequest,
    @Param('id', new ParseUUIDPipe({ version: '4' })) id: string,
  ) {
    return this.service.photo(r.identity.uid, id);
  }
}
