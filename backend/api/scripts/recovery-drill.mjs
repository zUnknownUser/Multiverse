// Local-only recovery rehearsal. It cannot accept a Railway URL or reuse a volume.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import pg from 'pg';

const container = process.env.TEST_DATABASE_CONTAINER;
const url = new URL(process.env.TEST_DATABASE_URL ?? 'http://invalid');
assert.match(container ?? '', /^multiverse-test-\d+-\d+$/);
assert.equal(url.hostname, '127.0.0.1');
assert.equal(url.pathname, '/multiverse_test');
assert.equal(url.username, 'multiverse_test');
const inspection = JSON.parse(
  execFileSync('docker', ['inspect', container], { encoding: 'utf8' }),
)[0];
assert.equal(inspection.Config.Labels['com.multiverse.test-database'], 'true');
assert.equal(inspection.HostConfig.AutoRemove, true);
assert.equal(
  inspection.NetworkSettings.Ports['5432/tcp'][0].HostPort,
  url.port,
);
assert.equal(
  inspection.NetworkSettings.Ports['5432/tcp'][0].HostIp,
  '127.0.0.1',
);
const env = {
  PATH: process.env.PATH,
  DATABASE_URL: url.href,
  APP_ENV: 'local',
  FIREBASE_PROJECT_ID: 'demo-multiverse',
  DOTENV_CONFIG_PATH: '/dev/null',
  DOTENV_CONFIG_QUIET: 'true',
};
execFileSync(process.execPath, ['scripts/migrate.mjs'], { env, stdio: 'pipe' });
const source = new pg.Client({ connectionString: url.href });
let restored;
try {
  await source.connect();
  await source.query(`INSERT INTO profiles(firebase_uid,username,display_name,avatar_color)
    VALUES('recovery-synthetic','recovery.synthetic','Synthetic recovery user','#F4A814');
    INSERT INTO diary_entries(firebase_uid,id,item_id,logged_at,rating,liked)
    SELECT 'recovery-synthetic','a1111111-1111-4111-8111-111111111111',id,now(),4.5,true
    FROM catalog_items WHERE universe_id='marvel' ORDER BY id LIMIT 1;
    INSERT INTO reviews(firebase_uid,entry_id,text)
    VALUES('recovery-synthetic','a1111111-1111-4111-8111-111111111111','Synthetic private review');
    INSERT INTO review_publications(firebase_uid) VALUES('recovery-synthetic');
    INSERT INTO profile_photo_limits(firebase_uid,attempts) VALUES('recovery-synthetic',20);`);
  const before = await fingerprint(source);
  const dump = execFileSync(
    'docker',
    [
      'exec',
      container,
      'pg_dump',
      '-U',
      'multiverse_test',
      '-d',
      'multiverse_test',
      '-Fc',
    ],
    { maxBuffer: 32 * 1024 * 1024 },
  );
  execFileSync('docker', [
    'exec',
    container,
    'createdb',
    '-U',
    'multiverse_test',
    'multiverse_restored',
  ]);
  execFileSync(
    'docker',
    [
      'exec',
      '-i',
      container,
      'pg_restore',
      '-U',
      'multiverse_test',
      '-d',
      'multiverse_restored',
      '--exit-on-error',
      '--no-owner',
      '--no-acl',
    ],
    { input: dump, stdio: ['pipe', 'pipe', 'pipe'] },
  );
  const restoreURL = new URL(url);
  restoreURL.pathname = '/multiverse_restored';
  restored = new pg.Client({ connectionString: restoreURL.href });
  await restored.connect();
  assert.deepEqual(await fingerprint(restored), before);
  execFileSync(process.execPath, ['scripts/migrate.mjs'], {
    env: { ...env, DATABASE_URL: restoreURL.href },
    stdio: 'pipe',
  });
  assert.deepEqual(await fingerprint(restored), before);
  assert.equal(
    (
      await restored.query(
        "SELECT attempts FROM profile_photo_limits WHERE firebase_uid='recovery-synthetic'",
      )
    ).rows[0].attempts,
    20,
  );
  await restored.query(
    "DELETE FROM diary_entries WHERE firebase_uid='recovery-synthetic'",
  );
  assert.equal(
    (
      await restored.query(
        "SELECT count(*)::int AS n FROM review_publications WHERE firebase_uid='recovery-synthetic'",
      )
    ).rows[0].n,
    1,
  );
  assert.equal(
    (
      await restored.query(
        "SELECT count(*)::int AS n FROM reviews WHERE firebase_uid='recovery-synthetic'",
      )
    ).rows[0].n,
    0,
  );
  await restored.query(
    "DELETE FROM profiles WHERE firebase_uid='recovery-synthetic'",
  );
  assert.equal(
    (
      await restored.query(
        "SELECT count(*)::int AS n FROM profile_photo_limits WHERE firebase_uid='recovery-synthetic'",
      )
    ).rows[0].n,
    0,
  );
  console.log(
    `Recovery drill passed: ${before.length} tables, custom-format dump/restore, migration checksums and quota/cascade invariants. Synthetic data only; no backup retained.`,
  );
} finally {
  await restored?.end();
  await source.end();
}
async function fingerprint(client) {
  const tables = await client.query(
    "SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename",
  );
  const result = [];
  for (const { tablename } of tables.rows) {
    const name = '"' + tablename.replaceAll('"', '""') + '"';
    const rows = await client.query(
      `SELECT row_to_json(t)::text AS value FROM ${name} t ORDER BY row_to_json(t)::text`,
    );
    result.push({
      table: tablename,
      rows: rows.rowCount,
      digest: createHash('sha256')
        .update(JSON.stringify(rows.rows))
        .digest('hex'),
    });
  }
  return result;
}
