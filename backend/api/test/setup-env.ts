// Test runs must not inherit the developer's application database or providers.
process.env.NODE_ENV = 'test';
process.env.APP_ENV = 'test';
process.env.PORT = '3000';
process.env.FIREBASE_PROJECT_ID = 'multiverse-test';
process.env.PUSH_ENABLED = 'false';
process.env.VOICE_ENABLED = 'false';
process.env.OPENAI_MODEL = 'gpt-4.1-mini';

for (const key of [
  'DATABASE_URL',
  'RAILWAY_ENVIRONMENT_NAME',
  'FIREBASE_SERVICE_ACCOUNT_JSON',
  'GOOGLE_APPLICATION_CREDENTIALS',
  'FIREBASE_AUTH_EMULATOR_HOST',
  'OPENAI_API_KEY',
  'LIVEKIT_URL',
  'LIVEKIT_API_KEY',
  'LIVEKIT_API_SECRET',
]) {
  delete process.env[key];
}
