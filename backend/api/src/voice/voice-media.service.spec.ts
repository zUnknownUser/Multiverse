import { ConfigService } from '@nestjs/config';
import { decodeJwt } from 'jose';
import { VoiceMediaService } from './voice-media.service.js';
import { validateEnvironment } from '../config/environment.js';
const fake = vi.hoisted(() => ({
  createRoom: vi.fn(async () => ({})),
  removeParticipant: vi.fn(async () => {}),
}));
vi.mock('livekit-server-sdk', async (importOriginal) => {
  const actual = await importOriginal<typeof import('livekit-server-sdk')>();
  return {
    ...actual,
    RoomServiceClient: class {
      createRoom = fake.createRoom;
      removeParticipant = fake.removeParticipant;
    },
  };
});
const config = {
  VOICE_ENABLED: 'true',
  LIVEKIT_URL: 'wss://test.livekit.cloud',
  LIVEKIT_API_KEY: 'test-key',
  LIVEKIT_API_SECRET: 'test-only-secret-at-least-32-characters',
};
describe('Voice media permissions', () => {
  it('issues a short-lived mic-only ticket without admin, camera, data or recording permissions', async () => {
    const media = new VoiceMediaService(new ConfigService(config));
    const result = await media.ticket('room-a', 'opaque-id', 'Name');
    const claims = decodeJwt(result.token);
    expect(claims.sub).toBe('opaque-id');
    expect(claims.name).toBe('Name');
    expect(claims.video).toEqual({
      roomJoin: true,
      room: 'room-a',
      canSubscribe: true,
      canPublish: true,
      canPublishSources: ['microphone'],
      canPublishData: false,
      canUpdateOwnMetadata: false,
      roomAdmin: false,
      roomRecord: false,
    });
    expect(claims.exp! - claims.nbf!).toBeLessThanOrEqual(60);
    expect(fake.createRoom).toHaveBeenCalledWith({
      name: 'room-a',
      maxParticipants: 8,
      emptyTimeout: 60,
      departureTimeout: 20,
    });
    await media.remove('room-a', 'opaque-id');
    expect(fake.removeParticipant).toHaveBeenCalledWith('room-a', 'opaque-id', {
      revokeTokenTs: expect.any(BigInt),
    });
  });
  it('remains unavailable without a configured provider', async () => {
    const media = new VoiceMediaService(new ConfigService({}));
    expect(media.enabled).toBe(false);
    await expect(media.ticket('r', 'id', 'name')).rejects.toThrow();
  });
  it('requires complete secure Cloud credentials when enabled', () => {
    expect(validateEnvironment(config).VOICE_ENABLED).toBe('true');
    expect(() => validateEnvironment({ VOICE_ENABLED: 'true' })).toThrow();
    expect(() =>
      validateEnvironment({
        ...config,
        LIVEKIT_URL: 'ws://test.livekit.cloud',
      }),
    ).toThrow();
    expect(() =>
      validateEnvironment({
        ...config,
        LIVEKIT_URL: 'wss://test.livekit.cloud.evil.test',
      }),
    ).toThrow();
  });
});
