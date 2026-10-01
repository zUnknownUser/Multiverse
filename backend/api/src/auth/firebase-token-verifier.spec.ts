import { ConfigService } from '@nestjs/config';
import { FirebaseTokenVerifier } from './firebase-token-verifier.js';

const sdk = vi.hoisted(() => ({
  applicationDefault: vi.fn(),
  cert: vi.fn(),
  getApps: vi.fn(() => []),
  initializeApp: vi.fn(),
  verifyIdToken: vi.fn(),
}));
vi.mock('firebase-admin/app', () => sdk);
vi.mock('firebase-admin/auth', () => ({
  getAuth: () => ({ verifyIdToken: sdk.verifyIdToken }),
}));

describe('Firebase server credentials', () => {
  beforeEach(() => vi.clearAllMocks());
  const verifier = (json?: string) =>
    new FirebaseTokenVerifier(
      new ConfigService({
        FIREBASE_PROJECT_ID: 'multiverse-7f87c',
        FIREBASE_SERVICE_ACCOUNT_JSON: json,
      }),
    );

  it('keeps application default credentials available locally', async () => {
    await verifier().verify('token');
    expect(sdk.applicationDefault).toHaveBeenCalledOnce();
    expect(sdk.verifyIdToken).toHaveBeenCalledWith('token', true);
  });

  it('uses the Railway secret for the configured Firebase project', async () => {
    await verifier(
      JSON.stringify({
        project_id: 'multiverse-7f87c',
        client_email: 'test@example.invalid',
        private_key: 'test-only-placeholder',
      }),
    ).verify('token');
    expect(sdk.cert).toHaveBeenCalledWith({
      projectId: 'multiverse-7f87c',
      clientEmail: 'test@example.invalid',
      privateKey: 'test-only-placeholder',
    });
    expect(sdk.applicationDefault).not.toHaveBeenCalled();
  });

  it.each([
    'malformed-private-data',
    'null',
    JSON.stringify({
      project_id: 'another-project',
      private_key: 'private-data',
    }),
  ])('rejects invalid credentials without exposing their content', (json) => {
    expect(() => verifier(json).verify('token')).toThrow(
      'Invalid FIREBASE_SERVICE_ACCOUNT_JSON configuration',
    );
    expect(sdk.cert).not.toHaveBeenCalled();
    expect(sdk.verifyIdToken).not.toHaveBeenCalled();
  });
});
