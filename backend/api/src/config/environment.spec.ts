import { validateEnvironment } from './environment.js';

describe('Environment configuration', () => {
  it('starts locally without an env file', () => {
    expect(validateEnvironment({})).toMatchObject({
      NODE_ENV: 'development',
      PORT: 3000,
    });
  });

  it('parses a custom port and production environment', () => {
    expect(
      validateEnvironment({
        NODE_ENV: 'production',
        PORT: '8080',
        DATABASE_URL: 'postgresql://localhost/test',
        FIREBASE_PROJECT_ID: 'multiverse-7f87c',
      }),
    ).toMatchObject({
      NODE_ENV: 'production',
      PORT: 8080,
    });
  });

  it.each(['', '0', '-1', '65536', '3000.5', '3000abc', 'NaN', '1e3'])(
    'rejects invalid PORT %j at startup',
    (port) => {
      expect(() => validateEnvironment({ PORT: port })).toThrow('PORT');
    },
  );

  it('requires real database and Firebase configuration in production', () => {
    expect(() => validateEnvironment({ NODE_ENV: 'production' })).toThrow(
      'Production',
    );
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'production',
        DATABASE_URL: 'postgresql://localhost/test',
        FIREBASE_PROJECT_ID: 'multiverse-7f87c',
        FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099',
      }),
    ).toThrow('emulator');
    expect(() =>
      validateEnvironment({ DATABASE_URL: 'https://example.com' }),
    ).toThrow('PostgreSQL');
  });

  it('rejects an unknown environment', () => {
    expect(() => validateEnvironment({ NODE_ENV: 'prod' })).toThrow('NODE_ENV');
  });

  it('supports optional OpenAI credentials and a configurable model', () => {
    expect(validateEnvironment({})).toMatchObject({
      OPENAI_API_KEY: undefined,
      OPENAI_MODEL: 'gpt-4.1-mini',
    });
    expect(
      validateEnvironment({
        OPENAI_API_KEY: ' test-placeholder ',
        OPENAI_MODEL: 'test-model',
      }),
    ).toMatchObject({
      OPENAI_API_KEY: 'test-placeholder',
      OPENAI_MODEL: 'test-model',
    });
    expect(
      validateEnvironment({ OPENAI_API_KEY: ' ' }).OPENAI_API_KEY,
    ).toBeUndefined();
    expect(() => validateEnvironment({ OPENAI_API_KEY: 123 })).toThrow(
      'OPENAI_API_KEY',
    );
    expect(() => validateEnvironment({ OPENAI_MODEL: '' })).toThrow(
      'OPENAI_MODEL',
    );
  });
});

describe('Environment isolation', () => {
  const staging = {
    APP_ENV: 'staging',
    NODE_ENV: 'production',
    DATABASE_URL: 'postgresql://localhost/staging',
    FIREBASE_PROJECT_ID: 'multiverse-staging-7f87c',
  };
  it('uses a demo Firebase project by default and accepts explicit staging', () => {
    expect(validateEnvironment({})).toMatchObject({
      APP_ENV: 'local',
      FIREBASE_PROJECT_ID: 'demo-multiverse-local',
    });
    expect(validateEnvironment(staging).APP_ENV).toBe('staging');
  });
  it.each([
    { ...staging, APP_ENV: 'unknown' },
    { ...staging, NODE_ENV: 'development' },
    { ...staging, FIREBASE_PROJECT_ID: 'multiverse-7f87c' },
    { ...staging, RAILWAY_ENVIRONMENT_NAME: 'production' },
    { ...staging, FIREBASE_AUTH_EMULATOR_HOST: 'localhost:9099' },
    {
      ...staging,
      FIREBASE_SERVICE_ACCOUNT_JSON: JSON.stringify({
        project_id: 'multiverse-7f87c',
      }),
    },
    { APP_ENV: 'local', FIREBASE_PROJECT_ID: 'multiverse-7f87c' },
    { APP_ENV: 'test', NODE_ENV: 'production' },
    { APP_ENV: 'local', NODE_ENV: 'test' },
  ])('rejects mixed deployment settings', (env) => {
    expect(() => validateEnvironment(env)).toThrow();
  });
});
