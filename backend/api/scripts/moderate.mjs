import pg from 'pg';
import { parseArgs } from 'node:util';
import { moderate, moderationQueue } from '../dist/social/moderation.js';

const { values } = parseArgs({
  options: {
    queue: { type: 'boolean' },
    execute: { type: 'boolean' },
    id: { type: 'string' },
    target: { type: 'string' },
    type: { type: 'string' },
    action: { type: 'string' },
    operator: { type: 'string' },
    reason: { type: 'string' },
  },
});
if (!values.queue && !values.execute) {
  console.log(
    'Read: node scripts/moderate.mjs --queue\nDecide: --execute --id UUID --type review|comment|post|post_comment --target UUID --action hide|dismiss|restore --operator NAME --reason TEXT\nRequires MODERATION_DATABASE_URL from an authorized private database connection. Reuse --id when retrying the same decision.',
  );
  process.exit(0);
}
if (!process.env.MODERATION_DATABASE_URL) {
  console.error('MODERATION_DATABASE_URL_REQUIRED');
  process.exit(1);
}
const pool = new pg.Pool({
  connectionString: process.env.MODERATION_DATABASE_URL,
  connectionTimeoutMillis: 5000,
  statement_timeout: 10000,
});
let client;
try {
  client = await pool.connect();
  if (values.queue)
    console.log(JSON.stringify(await moderationQueue(client), null, 2));
  else {
    await client.query('BEGIN');
    const result = await moderate(client, {
      id: values.id ?? '',
      targetType: values.type,
      targetID: values.target ?? '',
      action: values.action,
      operator: values.operator ?? '',
      reason: values.reason ?? '',
    });
    await client.query('COMMIT');
    console.log(JSON.stringify(result));
  }
} catch (error) {
  if (client) await client.query('ROLLBACK').catch(() => {});
  const safe = [
    'INVALID_MODERATION_DECISION',
    'DECISION_CONFLICT',
    'TARGET_UNAVAILABLE',
  ];
  console.error(
    safe.includes(error.message) ? error.message : 'MODERATION_FAILED',
  );
  process.exitCode = 1;
} finally {
  client?.release();
  await pool.end();
}
