import { VoiceController } from './voice/voice.controller.js';
import { VoiceService } from './voice/voice.service.js';
import { VoiceMediaService } from './voice/voice-media.service.js';
import { RoomEventsService } from './community/room-events.service.js';
import { SpacesController } from './community/spaces.controller.js';
import { SpacesService } from './community/spaces.service.js';
import { ImagesService } from './community/images.service.js';
import { LibraryService } from './library/library.service.js';
import { LibraryController } from './library/library.controller.js';
import { PushService } from './notifications/push.service.js';
import { NotificationsService } from './notifications/notifications.service.js';
import { NotificationsController } from './notifications/notifications.controller.js';
import { CommunityService } from './community/community.service.js';
import { CommunityController } from './community/community.controller.js';
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
    VoiceController,
    SpacesController,
    LibraryController,
    NotificationsController,
    CommunityController,
    InteractionsController,
    SocialController,
    PeopleController,
    AccountsController,
    CatalogController,
    ActivityController,
    MarvelController,
  ],
  providers: [
    VoiceService,
    VoiceMediaService,
    RoomEventsService,
    SpacesService,
    ImagesService,
    LibraryService,
    PushService,
    NotificationsService,
    CommunityService,
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
