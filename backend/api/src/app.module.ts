import { DailyDuelsController } from './duels/daily-duels.controller.js';
import { DailyDuelsService } from './duels/daily-duels.service.js';
import { ReadingOrdersController } from './reading-orders/reading-orders.controller.js';
import { ReadingOrdersService } from './reading-orders/reading-orders.service.js';
import { MessagesController } from './messages/messages.controller.js';
import { MessagesService } from './messages/messages.service.js';
import { VoiceController } from './voice/voice.controller.js';
import { VoiceService } from './voice/voice.service.js';
import { VoiceMediaService } from './voice/voice-media.service.js';
import { RoomEventsService } from './community/room-events.service.js';
import { ClubsController } from './community/clubs.controller.js';
import { RoomsController } from './community/rooms.controller.js';
import { ClubsService } from './community/clubs.service.js';
import { RoomsService } from './community/rooms.service.js';
import { ImagesService } from './community/images.service.js';
import { LibraryService } from './library/library.service.js';
import { LibraryController } from './library/library.controller.js';
import { PushService } from './notifications/push.service.js';
import { NotificationsService } from './notifications/notifications.service.js';
import { NotificationsController } from './notifications/notifications.controller.js';
import { CommunityService } from './community/community.service.js';
import { CommunityController } from './community/community.controller.js';
import { ProfileEditorController } from './accounts/profile-editor.controller.js';
import { ProfileEditorService } from './accounts/profile-editor.service.js';
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
    ProfileEditorController,
    DailyDuelsController,
    ReadingOrdersController,
    MessagesController,
    VoiceController,
    ClubsController,
    RoomsController,
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
    ProfileEditorService,
    DailyDuelsService,
    ReadingOrdersService,
    MessagesService,
    VoiceService,
    VoiceMediaService,
    RoomEventsService,
    ClubsService,
    RoomsService,
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
