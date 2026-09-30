import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Inject,
  Injectable,
  ServiceUnavailableException,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request, Response } from 'express';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { FirebaseTokenVerifier } from './firebase-token-verifier.js';

export const Public = () => SetMetadata('public', true);
export type AuthenticatedRequest = Request & { identity: DecodedIdToken };

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  constructor(
    @Inject(Reflector) private readonly reflector: Reflector,
    @Inject(FirebaseTokenVerifier)
    private readonly verifier: FirebaseTokenVerifier,
  ) {}
  async canActivate(context: ExecutionContext) {
    if (
      this.reflector.getAllAndOverride<boolean>('public', [
        context.getHandler(),
        context.getClass(),
      ])
    )
      return true;
    context
      .switchToHttp()
      .getResponse<Response>()
      .setHeader('Cache-Control', 'no-store');
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const match = /^Bearer ([^\s]+)$/i.exec(
      request.headers.authorization ?? '',
    );
    if (!match || match[1].length > 16384)
      throw new UnauthorizedException({ code: 'AUTH_REQUIRED' });
    try {
      request.identity = await this.verifier.verify(match[1]);
    } catch (error) {
      const code =
        typeof error === 'object' && error !== null && 'code' in error
          ? String(error.code)
          : '';
      if (
        [
          'auth/id-token-expired',
          'auth/id-token-revoked',
          'auth/invalid-id-token',
          'auth/argument-error',
          'auth/user-disabled',
          'auth/user-not-found',
        ].includes(code)
      )
        throw new UnauthorizedException({ code: 'INVALID_TOKEN' });
      throw new ServiceUnavailableException({ code: 'AUTH_UNAVAILABLE' });
    }
    if (
      !request.identity.email_verified ||
      request.identity.firebase?.sign_in_provider === 'anonymous'
    )
      throw new ForbiddenException({ code: 'EMAIL_NOT_VERIFIED' });
    return true;
  }
}
