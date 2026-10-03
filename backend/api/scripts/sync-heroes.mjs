import 'dotenv/config';
import pg from 'pg';
import {
  fetchHeroExpansion,
  publishHeroExpansion,
} from '../dist/catalog/providers/hero-expansion.js';

// Fixed reviewed mappings. No discovery, automatic publication or provider calls at API startup.
async function main() {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length && args[0] !== '--publish'))
    throw new Error('CATALOG_USAGE');
  const publish = args.includes('--publish');
  if (publish && !process.env.DATABASE_URL)
    throw new Error('CATALOG_DATABASE_REQUIRED');
  const batch = await fetchHeroExpansion({
    tmdb: process.env.TMDB_READ_ACCESS_TOKEN,
    metron: process.env.METRON_API_TOKEN,
  });
  if (publish) {
    const client = new pg.Client({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
      statement_timeout: 15000,
    });
    await client.connect();
    try {
      await client.query('BEGIN');
      await publishHeroExpansion(client, batch);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      await client.end();
    }
  }
  console.log(
    JSON.stringify({
      mode: publish ? 'published' : 'preview',
      count: batch.length,
      withCover: batch.filter((c) => c.metadata.posterURL).length,
    }),
  );
}
main().catch((error) => {
  const code = error instanceof Error ? error.message : '';
  console.error(
    /^(CATALOG|TMDB|METRON)_[A-Z_0-9]+$/.test(code)
      ? code
      : 'CATALOG_SYNC_FAILED',
  );
  process.exitCode = 1;
});
