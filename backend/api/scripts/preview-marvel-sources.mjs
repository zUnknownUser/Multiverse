import 'dotenv/config';
import pg from 'pg';
import { fetchTMDBMarvel } from '../dist/catalog/providers/tmdb.js';
import { fetchMetronMarvelIssues } from '../dist/catalog/providers/metron.js';
import { stageCandidates } from '../dist/catalog/providers/stage-candidates.js';
import { publishTMDB } from '../dist/catalog/providers/publish-tmdb.js';
import { publishMetron } from '../dist/catalog/providers/publish-metron.js';
import { metronMarvelRegistry } from '../dist/catalog/providers/metron-registry.js';

// All network reads finish before opening a transaction. Never called on API boot/login.
async function main() {
  const args = process.argv.slice(2);
  if (
    args.some(
      (a) =>
        !/^(--provider=(tmdb|metron)|--issues=[1-9]\d*(,[1-9]\d*){0,9}|--stage|--publish)$/.test(
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
  const publish = args.includes('--publish');
  if (!provider || (provider === 'metron' ? !issues && !publish : issues))
    throw new Error('USAGE');
  if (publish && args.includes('--stage')) throw new Error('USAGE');
  const issueIDs =
    issues?.split(',').map(Number) ?? metronMarvelRegistry.map((m) => m.id);
  if (
    publish &&
    provider === 'metron' &&
    (issueIDs.length !== metronMarvelRegistry.length ||
      new Set(issueIDs).size !== issueIDs.length ||
      !metronMarvelRegistry.every((m) => issueIDs.includes(m.id)))
  )
    throw new Error('CATALOG_INCOMPLETE_METRON_BATCH');
  if ((args.includes('--stage') || publish) && !process.env.DATABASE_URL)
    throw new Error('DATABASE_URL_REQUIRED');
  const batch =
    provider === 'tmdb'
      ? await fetchTMDBMarvel(process.env.TMDB_READ_ACCESS_TOKEN)
      : await fetchMetronMarvelIssues(issueIDs, process.env.METRON_API_TOKEN);
  if (args.includes('--stage') || publish) {
    const client = new pg.Client({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 5000,
      statement_timeout: 10000,
    });
    await client.connect();
    try {
      await client.query('BEGIN');
      await stageCandidates(client, batch);
      if (publish)
        await (provider === 'tmdb' ? publishTMDB : publishMetron)(
          client,
          batch,
        );
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
        mode: publish
          ? 'published'
          : args.includes('--stage')
            ? 'private-review'
            : 'preview',
        published: publish,
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
      ? 'Usage: node scripts/preview-marvel-sources.mjs --provider=tmdb|metron [--issues=ID,ID] [--stage|--publish]'
      : /^(TMDB|METRON|CATALOG)_[A-Z_0-9]+$/.test(code) ||
          code === 'DATABASE_URL_REQUIRED'
        ? code
        : 'MARVEL_PREVIEW_FAILED',
  );
  process.exitCode = 1;
});
