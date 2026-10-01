import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { FirebaseAuthGuard } from './auth/firebase-auth.guard.js';
import { FirebaseTokenVerifier } from './auth/firebase-token-verifier.js';
import { DatabaseService } from './database/database.service.js';
import { AccountsService } from './accounts/accounts.service.js';
import { AccountLifecycleService } from './accounts/account-lifecycle.service.js';
import { AccountsController } from './accounts/accounts.controller.js';
import { ConfigModule } from '@nestjs/config';
import { validateEnvironment } from './config/environment.js';
import { HealthModule } from './health/health.module.js';
import { AIModule } from './ai/ai.module.js';
import { CatalogController } from './catalog/catalog.controller.js';
import { CatalogService } from './catalog/catalog.service.js';
import { ActivityController } from './activity/activity.controller.js';
import { ActivityService } from './activity/activity.service.js';

@Module({
  controllers: [AccountsController, CatalogController, ActivityController],
  providers: [
    DatabaseService,
    CatalogService,
    ActivityService,
    FirebaseTokenVerifier,
    AccountsService,
    AccountLifecycleService,
    { provide: APP_GUARD, useClass: FirebaseAuthGuard },
  ],
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      ignoreEnvFile: process.env.NODE_ENV === 'test',
      validate: validateEnvironment,
    }),
    HealthModule,
    AIModule,
  ],
})
export class AppModule {}
