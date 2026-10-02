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
import { MarvelService } from './catalog/marvel.service.js';
import { MarvelController } from './catalog/marvel.controller.js';
import { ActivityController } from './activity/activity.controller.js';
import { ActivityService } from './activity/activity.service.js';
import { PeopleController } from './people/people.controller.js';
import { PeopleService } from './people/people.service.js';

import { SocialController } from './social/social.controller.js';
import { SocialService } from './social/social.service.js';
import { InteractionsService } from './social/interactions.service.js';
import { InteractionsController } from './social/interactions.controller.js';

@Module({
  controllers: [
    InteractionsController,
    SocialController,
    PeopleController,
    AccountsController,
    CatalogController,
    ActivityController,
    MarvelController,
  ],
  providers: [
    InteractionsService,
    SocialService,
    PeopleService,
    DatabaseService,
    CatalogService,
    MarvelService,
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
