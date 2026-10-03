import {
  Inject,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  AccessToken,
  RoomServiceClient,
  TrackSource,
} from 'livekit-server-sdk';

@Injectable()
export class VoiceMediaService {
  private readonly url: string;
  private readonly key: string;
  private readonly secret: string;
  private readonly client?: RoomServiceClient;
  readonly enabled: boolean;
  readonly configured: boolean;
  constructor(@Inject(ConfigService) config: ConfigService) {
    this.url = config.get<string>('LIVEKIT_URL') ?? '';
    this.key = config.get<string>('LIVEKIT_API_KEY') ?? '';
    this.secret = config.get<string>('LIVEKIT_API_SECRET') ?? '';
    this.configured = !!this.url && !!this.key && !!this.secret;
    this.enabled =
      config.get<string>('VOICE_ENABLED') === 'true' && this.configured;
    if (this.configured)
      this.client = new RoomServiceClient(
        this.url.replace(/^wss:/, 'https:'),
        this.key,
        this.secret,
        { requestTimeout: 5 },
      );
  }
  async ticket(room: string, identity: string, name: string) {
    if (!this.client || !this.enabled)
      throw new ServiceUnavailableException({ code: 'VOICE_UNAVAILABLE' });
    try {
      await this.client.createRoom({
        name: room,
        maxParticipants: 8,
        emptyTimeout: 60,
        departureTimeout: 20,
      });
      const token = new AccessToken(this.key, this.secret, {
        identity,
        name,
        ttl: 60,
      });
      token.addGrant({
        roomJoin: true,
        room,
        canSubscribe: true,
        canPublish: true,
        canPublishSources: [TrackSource.MICROPHONE],
        canPublishData: false,
        canUpdateOwnMetadata: false,
        roomAdmin: false,
        roomRecord: false,
      });
      return { serverURL: this.url, token: await token.toJwt() };
    } catch {
      throw new ServiceUnavailableException({ code: 'VOICE_UNAVAILABLE' });
    }
  }
  async remove(room: string, identity: string) {
    if (!this.client) return;
    try {
      await this.client.removeParticipant(room, identity, {
        revokeTokenTs: BigInt(Math.floor(Date.now() / 1000) + 1),
      });
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === 'not_found'
      )
        return;
      throw new ServiceUnavailableException({ code: 'VOICE_UNAVAILABLE' });
    }
  }
}
