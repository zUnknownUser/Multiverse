import 'dotenv/config';
import pg from 'pg';
import { marvelRegistry } from '../dist/catalog/providers/marvel-registry.js';
import { fetchMarvelMetadata } from '../dist/catalog/providers/wikidata.js';
import { importMarvel } from '../dist/catalog/providers/import-marvel.js';
if (process.argv.slice(2).some((arg) => !['--write'].includes(arg)))
  throw new Error('Usage: node scripts/sync-marvel.mjs [--write]');
try {
  const batch = await fetchMarvelMetadata(marvelRegistry);
  console.log(
    JSON.stringify(
      {
        mode: process.argv.includes('--write') ? 'write' : 'preview',
        items: batch.map(({ mapping, revision, metadata }) => ({
          ...mapping,
          revision,
          ...metadata,
        })),
      },
      null,
      2,
    ),
  );
  if (process.argv.includes('--write')) {
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL_REQUIRED');
    const client = new pg.Client({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
      statement_timeout: 10000,
    });
    await client.connect();
    try {
      await client.query('BEGIN');
      await importMarvel(client, batch);
      await client.query('COMMIT');
      console.log(`Synced ${batch.length} Marvel references.`);
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      await client.end();
    }
  }
} catch (error) {
  // Do not expose database URLs or query parameters in CLI logs.
  console.error(
    error instanceof Error &&
      /^(WIKIDATA_|INVALID_ENTITY|CATALOG_|DATABASE_URL)/.test(error.message)
      ? error.message
      : 'MARVEL_SYNC_FAILED: check source availability and database configuration',
  );
  process.exitCode = 1;
}
