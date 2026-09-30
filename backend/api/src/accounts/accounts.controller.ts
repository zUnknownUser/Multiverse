import {
  Body,
  Controller,
  Delete,
  Get,
  Inject,
  Put,
  Query,
  Req,
  ValidationPipe,
} from '@nestjs/common';
import type { AuthenticatedRequest } from '../auth/firebase-auth.guard.js';
import { AccountLifecycleService } from './account-lifecycle.service.js';
import { AccountsService } from './accounts.service.js';
import { OnboardingDTO, ProfileDTO, UsernameDTO } from './account.dto.js';
const validated = (
  expectedType: typeof ProfileDTO | typeof OnboardingDTO | typeof UsernameDTO,
) =>
  new ValidationPipe({
    expectedType,
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
  });
@Controller('me')
export class AccountsController {
  constructor(
    @Inject(AccountsService) private readonly accounts: AccountsService,
    @Inject(AccountLifecycleService)
    private readonly lifecycle: AccountLifecycleService,
  ) {}
  @Get() me(@Req() req: AuthenticatedRequest) {
    return this.accounts.me(req.identity.uid);
  }
  @Get('username-availability') available(
    @Req() req: AuthenticatedRequest,
    @Query(validated(UsernameDTO)) query: UsernameDTO,
  ) {
    return this.accounts.availability(req.identity.uid, query.username);
  }
  @Put('profile') profile(
    @Req() req: AuthenticatedRequest,
    @Body(validated(ProfileDTO)) body: ProfileDTO,
  ) {
    return this.accounts.saveProfile(req.identity.uid, body);
  }
  @Get('onboarding/suggestions') suggestions(@Req() req: AuthenticatedRequest) {
    return this.accounts.suggestions(req.identity.uid);
  }
  @Put('onboarding') onboarding(
    @Req() req: AuthenticatedRequest,
    @Body(validated(OnboardingDTO)) body: OnboardingDTO,
  ) {
    return this.accounts.saveOnboarding(req.identity.uid, body);
  }
  @Delete() delete(@Req() req: AuthenticatedRequest) {
    return this.lifecycle.deleteAccount(
      req.identity.uid,
      req.identity.auth_time,
    );
  }
}
