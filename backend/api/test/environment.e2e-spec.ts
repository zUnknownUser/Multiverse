import { randomUUID } from 'node:crypto';
import { cp, mkdtemp, mkdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { ConfigService } from '@nestjs/config';
import pg from 'pg';
import { DatabaseService } from '../src/database/database.service.js';

const run = promisify(execFile);
const databaseURL = process.env.TEST_DATABASE_URL!;
describe('Deployment isolation with PostgreSQL and the real migrator', () => {
  let admin: pg.Client;
  let client: pg.Client;
  let url: string;
  let schema: string;
  const migrate = (
    environment = 'staging',
    project = 'multiverse-staging-7f87c',
    script = 'scripts/migrate.mjs',
  ) =>
    run(process.execPath, [script], {
      env: {
        PATH: process.env.PATH,
        APP_ENV: environment,
        FIREBASE_PROJECT_ID: project,
        DATABASE_URL: url,
        DOTENV_CONFIG_PATH: '/dev/null',
        DOTENV_CONFIG_QUIET: 'true',
      },
    });
  beforeAll(async () => {
    admin = new pg.Client({ connectionString: databaseURL });
    await admin.connect();
  });
  beforeEach(async () => {
    schema = 'deployment_test_' + randomUUID().replaceAll('-', '');
    await admin.query(`CREATE SCHEMA "${schema}"`);
    const connection = new URL(databaseURL);
    connection.searchParams.set('options', `-c search_path=${schema}`);
    url = connection.toString();
    client = new pg.Client({ connectionString: url });
    await client.connect();
  });
  afterEach(async () => {
    await client.end();
    await admin.query(`DROP SCHEMA "${schema}" CASCADE`);
  });
  afterAll(async () => {
    await admin.end();
  });

  it('binds a fresh staging database, supports reruns, and rejects a production target', async () => {
    await migrate();
    await migrate();
    expect(
      (
        await client.query(
          'SELECT environment, firebase_project_id FROM deployment_identity',
        )
      ).rows,
    ).toEqual([
      {
        environment: 'staging',
        firebase_project_id: 'multiverse-staging-7f87c',
      },
    ]);
    const before = (
      await client.query('SELECT count(*)::int AS count FROM schema_migrations')
    ).rows[0].count;
    expect(before).toBe(29);
    await expect(migrate('production', 'multiverse-7f87c')).rejects.toThrow(
      'Database belongs to another environment',
    );
    expect(
      (
        await client.query(
          'SELECT count(*)::int AS count FROM schema_migrations',
        )
      ).rows[0].count,
    ).toBe(before);
    const valid = new DatabaseService(
      new ConfigService({
        DATABASE_URL: url,
        APP_ENV: 'staging',
        FIREBASE_PROJECT_ID: 'multiverse-staging-7f87c',
      }),
    );
    try {
      await expect(valid.onModuleInit()).resolves.toBeUndefined();
    } finally {
      await valid.onModuleDestroy();
    }
    const wrong = new DatabaseService(
      new ConfigService({
        DATABASE_URL: url,
        APP_ENV: 'production',
        FIREBASE_PROJECT_ID: 'multiverse-7f87c',
      }),
    );
    try {
      await expect(wrong.onModuleInit()).rejects.toThrow(
        'Database environment mismatch',
      );
    } finally {
      await wrong.onModuleDestroy();
    }
  });
  it('keeps its identity after a failed migration and permits a safe retry', async () => {
    const fixture = await mkdtemp(
      join(tmpdir(), 'multiverse-migration-retry-'),
    );
    try {
      await mkdir(join(fixture, 'scripts'));
      await cp('migrations', join(fixture, 'migrations'), { recursive: true });
      for (const script of ['migrate.mjs', 'database-environment.mjs'])
        await cp(join('scripts', script), join(fixture, 'scripts', script));
      await symlink(resolve('node_modules'), join(fixture, 'node_modules'));
      const migration = join(fixture, 'migrations/030_retry_fixture.sql');
      const script = join(fixture, 'scripts/migrate.mjs');
      await writeFile(migration, 'INVALID SQL FOR RETRY TEST');
      await expect(
        migrate('staging', 'multiverse-staging-7f87c', script),
      ).rejects.toThrow('syntax error');
      expect(
        (await client.query('SELECT environment FROM deployment_identity'))
          .rows[0].environment,
      ).toBe('staging');
      await writeFile(migration, 'CREATE TABLE retry_fixture (id integer)');
      await migrate('staging', 'multiverse-staging-7f87c', script);
      expect(
        (
          await client.query(
            "SELECT count(*)::int AS count FROM schema_migrations WHERE name='030_retry_fixture.sql'",
          )
        ).rows[0].count,
      ).toBe(1);
    } finally {
      await rm(fixture, { recursive: true, force: true });
    }
  });

  it('refuses to relabel a legacy database as staging before writing anything', async () => {
    await client.query('CREATE TABLE existing_data (id integer)');
    await expect(migrate()).rejects.toThrow(
      'Refusing to bind an existing database',
    );
    expect(
      (
        await client.query(
          'SELECT tablename FROM pg_tables WHERE schemaname = current_schema()',
        )
      ).rows,
    ).toEqual([{ tablename: 'existing_data' }]);
  });
  it('fails closed when identity is absent at runtime', async () => {
    const db = new DatabaseService(
      new ConfigService({
        DATABASE_URL: url,
        APP_ENV: 'staging',
        FIREBASE_PROJECT_ID: 'multiverse-staging-7f87c',
      }),
    );
    try {
      await expect(db.onModuleInit()).rejects.toThrow('missing identity');
    } finally {
      await db.onModuleDestroy();
    }
  });
});
