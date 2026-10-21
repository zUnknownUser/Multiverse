import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import type { INestApplication } from '@nestjs/common';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/database/database.service.js';
import { configureApp } from '../src/configure-app.js';
import { operationsReport } from '../src/operations/operations-report.js';

describe('Readiness and operational reports with PostgreSQL', () => {
  const schema = 'operations_test_' + randomUUID().replaceAll('-', '');
  const identity = { environment: 'local', project: 'demo-multiverse-local' };
  let admin: pg.Pool;
  let fixture: pg.Pool;
  let config: ConfigService;
  let db: DatabaseService;
  let app: INestApplication | undefined;

  const startApp = async () => {
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(ConfigService)
      .useValue(config)
      .overrideProvider(DatabaseService)
      .useValue(db)
      .compile();
    app = module.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1');
    return app;
  };
  const report = async (expected = identity) => {
    const client = await fixture.connect();
    try {
      return await operationsReport(client, expected);
    } finally {
      client.release();
    }
  };

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL });
    await admin.query(`CREATE SCHEMA "${schema}"`);
    const url = new URL(process.env.TEST_DATABASE_URL!);
    url.searchParams.set('options', `-c search_path=${schema}`);
    fixture = new pg.Pool({ connectionString: url.toString() });
    const migrations = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(migrations))
      .filter((n) => n.endsWith('.sql'))
      .sort())
      await fixture.query(await readFile(new URL(name, migrations), 'utf8'));
    await fixture.query(
      'INSERT INTO deployment_identity(environment,firebase_project_id) VALUES($1,$2)',
      [identity.environment, identity.project],
    );
    config = new ConfigService({
      DATABASE_URL: url.toString(),
      APP_ENV: identity.environment,
      FIREBASE_PROJECT_ID: identity.project,
      PUSH_ENABLED: 'false',
      VOICE_ENABLED: 'false',
    });
  });
  beforeEach(() => {
    db = new DatabaseService(config);
  });
  afterEach(async () => {
    if (app) await app.close();
    else await db.onModuleDestroy();
    app = undefined;
    await fixture.query('DELETE FROM profiles');
    await fixture.query('DELETE FROM account_deletions');
    await fixture.query('DELETE FROM room_voice_sessions');
    await fixture.query(
      'UPDATE deployment_identity SET environment=$1, firebase_project_id=$2',
      [identity.environment, identity.project],
    );
  });
  afterAll(async () => {
    await fixture?.end();
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await admin.end();
    }
  });

  it('serves public readiness using the application pool and bound identity', async () => {
    const server = await startApp();
    await request(server.getHttpServer())
      .get('/api/v1/health/ready')
      .expect(200)
      .expect('Cache-Control', 'no-store')
      .expect('X-Multiverse-Environment', 'local')
      .expect({
        status: 'ready',
        service: 'multiverse-api',
        environment: 'local',
      });
    await request(server.getHttpServer())
      .get('/api/v1/health/ready')
      .set('X-Multiverse-Environment', 'production')
      .expect(409);
  });

  it('fails readiness on a blocked database query, preserves liveness, and recovers', async () => {
    const server = await startApp();
    const lock = await fixture.connect();
    try {
      await lock.query('BEGIN');
      await lock.query(
        'LOCK TABLE deployment_identity IN ACCESS EXCLUSIVE MODE',
      );
      const start = performance.now();
      await request(server.getHttpServer())
        .get('/api/v1/health/ready')
        .expect(503)
        .expect('Cache-Control', 'no-store')
        .expect({
          status: 'unavailable',
          service: 'multiverse-api',
          environment: 'local',
        });
      expect(performance.now() - start).toBeLessThan(3000);
      await request(server.getHttpServer()).get('/api/v1/health').expect(200);
    } finally {
      await lock.query('ROLLBACK');
      lock.release();
    }
    await new Promise((resolve) => setTimeout(resolve, 5100));
    await request(server.getHttpServer())
      .get('/api/v1/health/ready')
      .expect(200);
    expect(
      (
        await fixture.query(
          'SELECT count(*)::int AS count FROM deployment_identity',
        )
      ).rows[0].count,
    ).toBe(1);
  }, 15_000);

  it('fails closed if the database identity changes after startup', async () => {
    const server = await startApp();
    await fixture.query(
      "UPDATE deployment_identity SET environment='production',firebase_project_id='multiverse-7f87c'",
    );
    await request(server.getHttpServer())
      .get('/api/v1/health/ready')
      .expect(503);
    await request(server.getHttpServer()).get('/api/v1/health').expect(200);
  });

  it('returns empty aggregates without fabricating pending ages', async () => {
    const result = await report();
    expect(result).toEqual({
      environment: 'local',
      checkedAt: expect.any(String),
      attentionRequired: false,
      deletions: {
        pending: 0,
        attempted: 0,
        olderThan15Minutes: 0,
        oldestPendingAgeSeconds: null,
      },
      push: {
        pending: 0,
        due: 0,
        retried: 0,
        dueOver15Minutes: 0,
        oldestDueAgeSeconds: null,
      },
      voice: { expiredOrRevoked: 0, staleOver5Minutes: 0 },
    });
  });

  it('counts durable pending work without returning identities or changing it', async () => {
    await fixture.query(`INSERT INTO account_deletions(firebase_uid,requested_at,last_attempt_at,completed_at) VALUES
      ('private-old',now()-interval '20 minutes',null,null),
      ('private-retry',now()-interval '1 minute',now(),null),
      ('private-done',now()-interval '1 day',now(),now())`);
    await fixture.query(`INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES
      ('private-actor','actor','Private actor','#F4A814'),
      ('private-recipient','recipient','Private recipient','#F4A814')`);
    await fixture.query(`INSERT INTO notifications(recipient_uid,actor_uid,kind,target_type,target_id,push_state,push_attempts,push_after) VALUES
      ('private-recipient','private-actor','follow','person','private-old','pending',2,now()-interval '20 minutes'),
      ('private-recipient','private-actor','follow','person','private-recent','pending',0,now()-interval '1 minute'),
      ('private-recipient','private-actor','follow','person','private-later','pending',0,now()+interval '1 hour'),
      ('private-recipient','private-actor','follow','person','private-sent','sent',1,now()-interval '1 day'),
      ('private-recipient','private-actor','follow','person','private-skipped','skipped',5,now()-interval '1 day')`);
    await fixture.query(`INSERT INTO room_voice_sessions(id,firebase_uid,item_id,segment,room_name,expires_at,revoked_at) VALUES
      (gen_random_uuid(),'private-expired','m-civil',0,'private-room',now()-interval '10 minutes',null),
      (gen_random_uuid(),'private-revoked','m-civil',0,'private-room',now()+interval '1 minute',now()-interval '10 minutes'),
      (gen_random_uuid(),'private-recent','m-civil',0,'private-room',now()-interval '1 minute',null),
      (gen_random_uuid(),'private-active','m-civil',0,'private-room',now()+interval '1 minute',null)`);
    const result = await report();
    expect(result.attentionRequired).toBe(true);
    expect(result.deletions).toMatchObject({
      pending: 2,
      attempted: 1,
      olderThan15Minutes: 1,
    });
    expect(result.deletions.oldestPendingAgeSeconds).toBeGreaterThanOrEqual(
      1200,
    );
    expect(result.push).toMatchObject({
      pending: 3,
      due: 2,
      retried: 1,
      dueOver15Minutes: 1,
    });
    expect(result.push.oldestDueAgeSeconds).toBeGreaterThanOrEqual(1200);
    expect(result.voice).toEqual({ expiredOrRevoked: 3, staleOver5Minutes: 2 });
    expect(JSON.stringify(result)).not.toMatch(
      /private-|firebase_uid|room_name|token|password/,
    );
    expect(
      (
        await fixture.query(
          'SELECT count(*)::int AS count FROM account_deletions',
        )
      ).rows[0].count,
    ).toBe(3);
    expect(
      (await fixture.query('SELECT count(*)::int AS count FROM notifications'))
        .rows[0].count,
    ).toBe(5);
    expect(
      (
        await fixture.query(
          'SELECT count(*)::int AS count FROM room_voice_sessions',
        )
      ).rows[0].count,
    ).toBe(4);
  });

  it('enforces read-only repeatable-read and refuses the wrong environment before inspecting queues', async () => {
    const client = await fixture.connect();
    const originalQuery = client.query.bind(client);
    let transactionSettings: unknown;
    const query = vi.spyOn(client, 'query');
    query.mockImplementation((async (...args: unknown[]) => {
      if (
        typeof args[0] === 'string' &&
        args[0].includes('FROM deployment_identity')
      )
        transactionSettings = (
          await originalQuery(
            "SELECT current_setting('transaction_read_only') AS readonly, current_setting('transaction_isolation') AS isolation",
          )
        ).rows[0];
      return originalQuery(...(args as [string]));
    }) as typeof client.query);
    try {
      await expect(
        operationsReport(client, {
          environment: 'staging',
          project: 'multiverse-staging-7f87c',
        }),
      ).rejects.toThrow('OPERATIONS_ENVIRONMENT_MISMATCH');
      expect(transactionSettings).toEqual({
        readonly: 'on',
        isolation: 'repeatable read',
      });
      expect(query.mock.calls.map(([sql]) => sql).join(' ')).not.toMatch(
        /FROM account_deletions|FROM notifications|FROM room_voice_sessions/,
      );
      expect(
        (
          await originalQuery(
            "SELECT current_setting('transaction_read_only') AS readonly",
          )
        ).rows[0].readonly,
      ).toBe('off');
    } finally {
      query.mockRestore();
      client.release();
    }
  });
});
