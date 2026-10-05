import pg from 'pg';
import { readFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { curateDuel, validateDecision } from '../dist/duels/duel-curation.js';
const { values } = parseArgs({
  options: {
    queue: { type: 'boolean' },
    file: { type: 'string' },
    execute: { type: 'boolean' },
  },
});
if (!values.queue && !values.file) {
  console.log(
    'Queue: --queue\nValidate locally: --file decision.json\nApply: --file decision.json --execute\nRequires CURATION_DATABASE_URL for queue/apply. Build API first.',
  );
  process.exit(0);
}
let pool, client;
try {
  const input = values.file
    ? JSON.parse(await readFile(values.file, 'utf8'))
    : null;
  if (input) validateDecision(input);
  if (input && !values.execute) {
    console.log('VALID_FORMAT (database conflicts checked only on apply)');
  } else {
    if (!process.env.CURATION_DATABASE_URL)
      throw new Error('CURATION_DATABASE_URL_REQUIRED');
    pool = new pg.Pool({
      connectionString: process.env.CURATION_DATABASE_URL,
      connectionTimeoutMillis: 5000,
      statement_timeout: 10000,
    });
    client = await pool.connect();
    if (values.queue) {
      const summary = (
        await client.query(
          `SELECT status,count(*)::int AS count FROM duel_candidates GROUP BY status ORDER BY status`,
        )
      ).rows;
      const queue = (
        await client.query(`SELECT id,origin,source_post_id,source_version,snapshot,universe_id,category,translations,status,scheduled_on,reason_code
        FROM duel_candidates WHERE status IN ('pending','approved') ORDER BY scheduled_on ASC NULLS LAST,created_at,id LIMIT 200`)
      ).rows;
      console.log(JSON.stringify({ summary, queue }, null, 2));
    } else {
      await client.query('BEGIN');
      const result = await curateDuel(client, input);
      await client.query('COMMIT');
      console.log(JSON.stringify(result));
    }
  }
} catch (error) {
  if (client) await client.query('ROLLBACK').catch(() => {});
  const safe = [
    'CURATION_DATABASE_URL_REQUIRED',
    'INVALID_CURATION',
    'DECISION_CONFLICT',
    'CANDIDATE_CONFLICT',
    'CANDIDATE_UNAVAILABLE',
    'SOURCE_CHANGED',
    'DATE_UNAVAILABLE',
    'DUPLICATE_DUEL',
  ];
  console.error(
    safe.includes(error.message) ? error.message : 'CURATION_FAILED',
  );
  process.exitCode = 1;
} finally {
  client?.release();
  await pool?.end();
}
