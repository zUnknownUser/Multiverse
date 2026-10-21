import 'dotenv/config';
import { readdir, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import pg from 'pg';
import {
  deploymentIdentity,
  assertDatabaseEnvironment,
  bindDatabaseEnvironment,
} from './database-environment.mjs';
const identity = deploymentIdentity(process.env);
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
const client = new pg.Client({ connectionString: process.env.DATABASE_URL });
await client.connect();
try {
  await client.query('SELECT pg_advisory_lock(72451901)');
  await assertDatabaseEnvironment(client, identity);
  // Bind before other migrations: a failed migration can be retried safely.
  await client.query('BEGIN');
  try {
    await client.query(
      await readFile(
        new URL('../migrations/029_deployment_identity.sql', import.meta.url),
        'utf8',
      ),
    );
    await bindDatabaseEnvironment(client, identity);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  }
  await client.query(
    'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, checksum text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())',
  );
  const folder = new URL('../migrations/', import.meta.url);
  for (const name of (await readdir(folder))
    .filter((x) => x.endsWith('.sql'))
    .sort()) {
    const sql = await readFile(new URL(name, folder), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const prior = await client.query(
      'SELECT checksum FROM schema_migrations WHERE name=$1',
      [name],
    );
    if (prior.rowCount) {
      if (prior.rows[0].checksum !== checksum)
        throw new Error(`Applied migration changed: ${name}`);
      continue;
    }
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query(
        'INSERT INTO schema_migrations(name, checksum) VALUES ($1,$2)',
        [name, checksum],
      );
      await client.query('COMMIT');
      console.log(`Applied ${name}`);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  }
  await bindDatabaseEnvironment(client, identity);
} finally {
  await client.end();
}
