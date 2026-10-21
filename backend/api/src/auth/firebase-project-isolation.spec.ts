import { ConfigService } from '@nestjs/config';
import { deleteApp, getApps } from 'firebase-admin/app';
import { FirebaseTokenVerifier } from './firebase-token-verifier.js';

// Real Admin SDK content validation; no network, signing keys or live users.
describe('Firebase project boundary', () => {
  afterAll(async () => {
    await Promise.all(
      getApps()
        .filter((app) => app.name.startsWith('multiverse-api-'))
        .map(deleteApp),
    );
  });
  it('rejects a production audience when the API is configured for staging', async () => {
    const now = Math.floor(Date.now() / 1000);
    const part = (value: object) =>
      Buffer.from(JSON.stringify(value)).toString('base64url');
    const token = [
      part({ alg: 'RS256', kid: 'test-key' }),
      part({
        aud: 'multiverse-7f87c',
        iss: 'https://securetoken.google.com/multiverse-7f87c',
        sub: 'test-user',
        iat: now,
        exp: now + 3600,
        auth_time: now,
      }),
      'test-signature',
    ].join('.');
    const verifier = new FirebaseTokenVerifier(
      new ConfigService({ FIREBASE_PROJECT_ID: 'multiverse-staging-7f87c' }),
    );
    await expect(verifier.verify(token)).rejects.toThrow('incorrect "aud"');
  });
});
