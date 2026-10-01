import 'dotenv/config';
import pg from 'pg';
import { fetchTMDBMarvel } from '../dist/catalog/providers/tmdb.js';
import { fetchMetronMarvelIssues } from '../dist/catalog/providers/metron.js';
import { stageCandidates } from '../dist/catalog/providers/stage-candidates.js';

// All network reads finish before opening a transaction. Never called on API boot/login.
async function main() {
  const args = process.argv.slice(2);
  if (
    args.some(
      (a) =>
        !/^(--provider=(tmdb|metron)|--issues=[1-9]\d*(,[1-9]\d*){0,9}|--stage)$/.test(
          a,
        ),
    ) ||
    new Set(args.map((a) => a.split('=')[0])).size !== args.length
  )
    throw new Error('USAGE');
  const provider = args
    .find((a) => a.startsWith('--provider='))
    ?.slice('--provider='.length);
  const issues = args
    .find((a) => a.startsWith('--issues='))
    ?.slice('--issues='.length);
  if (!provider || (provider === 'metron' ? !issues : issues))
    throw new Error('USAGE');
  if (args.includes('--stage') && !process.env.DATABASE_URL)
    throw new Error('DATABASE_URL_REQUIRED');
  const batch =
    provider === 'tmdb'
      ? await fetchTMDBMarvel(process.env.TMDB_READ_ACCESS_TOKEN)
      : await fetchMetronMarvelIssues(
          issues.split(',').map(Number),
          process.env.METRON_API_TOKEN,
        );
  if (args.includes('--stage')) {
    const client = new pg.Client({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
      statement_timeout: 10000,
    });
    await client.connect();
    try {
      await client.query('BEGIN');
      await stageCandidates(client, batch);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      await client.end();
    }
  }
  console.log(
    JSON.stringify(
      {
        mode: args.includes('--stage') ? 'private-review' : 'preview',
        published: false,
        candidates: batch,
      },
      null,
      2,
    ),
  );
}
main().catch((error) => {
  // Only our known machine codes. Never print an upstream body or a DB error/URL.
  const code = error instanceof Error ? error.message : '';
  console.error(
    code === 'USAGE'
      ? 'Usage: node scripts/preview-marvel-sources.mjs --provider=tmdb|metron [--issues=ID,ID] [--stage]'
      : /^(TMDB|METRON|CATALOG)_[A-Z_0-9]+$/.test(code) ||
          code === 'DATABASE_URL_REQUIRED'
        ? code
        : 'MARVEL_PREVIEW_FAILED',
  );
  process.exitCode = 1;
});
