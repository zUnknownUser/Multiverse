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
        FIREBASE_PROJECT_ID: 'demo-test',
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
        FIREBASE_PROJECT_ID: 'demo-test',
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
});
