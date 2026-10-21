import pg from 'pg';
import { parseArgs } from 'node:util';
import { operationsReport } from '../dist/operations/operations-report.js';
import { deploymentIdentity } from './database-environment.mjs';

let client;
try {
  const { values } = parseArgs({ options: { help: { type: 'boolean' } } });
  if (values.help) {
    console.log(
      'Read-only: npm run ops:report\nRequires OPERATIONS_DATABASE_URL, APP_ENV and FIREBASE_PROJECT_ID. Does not load .env. Exit codes: 0 clear, 2 attention required, 1 unavailable/invalid configuration.',
    );
  } else {
    const identity = deploymentIdentity(process.env);
    const connectionString = process.env.OPERATIONS_DATABASE_URL;
    if (!connectionString || !/^postgres(?:ql)?:\/\//.test(connectionString))
      throw new Error('OPERATIONS_CONFIGURATION_INVALID');
    client = new pg.Client({
      connectionString,
      connectionTimeoutMillis: 5000,
      statement_timeout: 5000,
      query_timeout: 6000,
      idle_in_transaction_session_timeout: 5000,
    });
    client.on('error', () => {});
    await client.connect();
    const report = await operationsReport(client, identity);
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = report.attentionRequired ? 2 : 0;
  }
} catch (error) {
  const safe = [
    'OPERATIONS_ENVIRONMENT_MISMATCH',
    'OPERATIONS_CONFIGURATION_INVALID',
  ];
  console.error(
    safe.includes(error?.message) ? error.message : 'OPERATIONS_UNAVAILABLE',
  );
  process.exitCode = 1;
} finally {
  await client?.end().catch(() => {});
}
