import pg from 'pg';

export default async function requireTestDatabase() {
  const connectionString = process.env.TEST_DATABASE_URL;
  if (!connectionString) {
    throw new Error(
      'TEST_DATABASE_URL is required. Run npm run test:local for a disposable PostgreSQL database, or set a dedicated test database URL.',
    );
  }

  let url: URL;
  try {
    url = new URL(connectionString);
  } catch {
    throw new Error('TEST_DATABASE_URL must be a PostgreSQL connection URL.');
  }
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('TEST_DATABASE_URL must be a PostgreSQL connection URL.');
  }

  const client = new pg.Client({
    connectionString,
    connectionTimeoutMillis: 5_000,
    query_timeout: 5_000,
  });
  try {
    await client.connect();
    await client.query('SELECT 1');
  } catch {
    // Never include the connection string or driver error (which may contain it).
    throw new Error(
      'Cannot connect to TEST_DATABASE_URL. Start the test database or run npm run test:local.',
    );
  } finally {
    await client.end();
  }
}
