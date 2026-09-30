import { validateEnvironment } from './environment.js';

describe('Environment configuration', () => {
  it('starts locally without an env file', () => {
    expect(validateEnvironment({})).toEqual({
      NODE_ENV: 'development',
      PORT: 3000,
    });
  });

  it('parses a custom port and production environment', () => {
    expect(
      validateEnvironment({ NODE_ENV: 'production', PORT: '8080' }),
    ).toEqual({
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

  it('rejects an unknown environment', () => {
    expect(() => validateEnvironment({ NODE_ENV: 'prod' })).toThrow('NODE_ENV');
  });
});
