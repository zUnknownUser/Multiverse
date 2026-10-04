import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import type { INestApplication } from '@nestjs/common';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FirebaseTokenVerifier } from '../src/auth/firebase-token-verifier.js';
import { configureApp } from '../src/configure-app.js';

const databaseURL = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseURL)('People and follows with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const schema = 'people_test_' + randomUUID().replaceAll('-', '');
  const get = (path: string, uid = 'owner') =>
    request(app.getHttpServer())
      .get('/api/v1/' + path)
      .auth(uid, { type: 'bearer' });
  const follow = (target: string, following: boolean, uid = 'owner') =>
    request(app.getHttpServer())
      .put('/api/v1/me/follows/' + target)
      .auth(uid, { type: 'bearer' })
      .send({ following });
  const member = async (uid: string, completed = true, name = uid) => {
    await db.query(
      'INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES($1,$1,$2,$3)',
      [uid, name, '#F4A814'],
    );
    await db.query(
      "INSERT INTO onboarding(firebase_uid,completed,universe_ids,step) VALUES($1,$2,'{marvel}',3)",
      [uid, completed],
    );
  };
  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: databaseURL });
    await admin.query(`CREATE SCHEMA "${schema}"`);
    const url = new URL(databaseURL!);
    url.searchParams.set('options', `-c search_path=${schema}`);
    db = new DatabaseService(
      new ConfigService({ DATABASE_URL: url.toString() }),
    );
    const folder = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(folder))
      .filter((n) => n.endsWith('.sql'))
      .sort())
      await db.query(await readFile(new URL(name, folder), 'utf8'));
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(DatabaseService)
      .useValue(db)
      .overrideProvider(FirebaseTokenVerifier)
      .useValue({
        verify: async (uid: string) => ({
          uid,
          email_verified: true,
          auth_time: Math.floor(Date.now() / 1000),
          firebase: { sign_in_provider: 'google.com' },
        }),
        deleteUser: async () => {},
      })
      .compile();
    app = module.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1'); // Keep one port per suite; concurrent Supertest requests must not close/rebind it.
  });
  afterEach(async () => {
    await db.query('DELETE FROM profiles');
    await db.query('DELETE FROM account_deletions');
  });
  afterAll(async () => {
    await app?.close();
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await admin.end();
    }
  });

  it('requires authentication and completed onboarding; no people is successful empty content', async () => {
    await request(app.getHttpServer()).get('/api/v1/people').expect(401);
    await member('owner', false);
    await get('people').expect(409);
    await db.query(
      "UPDATE onboarding SET completed=true WHERE firebase_uid='owner'",
    );
    expect((await get('people/suggestions').expect(200)).body).toEqual({
      users: [],
      nextCursor: null,
      state: { version: 0, followingIDs: [], followerCount: 0 },
    });
  });
  it('searches real people by accent-insensitive name or handle with stable pagination and no private fields', async () => {
    await member('owner');
    await member('alice', true, 'Álice');
    await member('bruno');
    await member('draft', false);
    const first = (await get('people?limit=1').expect(200)).body;
    expect(first.users.map((u: { userID: string }) => u.userID)).toEqual([
      'alice',
    ]);
    expect(first.nextCursor).toBe('alice');
    expect(
      (await get('people?limit=1&after=alice').expect(200)).body.users[0]
        .userID,
    ).toBe('bruno');
    for (const q of ['alice', '@alice'])
      expect(
        (await get('people?q=' + encodeURIComponent(q)).expect(200)).body.users,
      ).toHaveLength(1);
    expect((await get('people?q=%25').expect(200)).body.users).toEqual([]);
    expect(Object.keys(first.users[0]).sort()).toEqual(
      [
        'avatarColor',
        'avatarID',
        'bio',
        'displayName',
        'followerCount',
        'followingCount',
        'logCount',
        'userID',
        'username',
      ].sort(),
    );
    for (const query of [
      'limit=100',
      'q=a&q=b',
      'after=invalid%20cursor',
      'extra=true',
    ])
      await get('people?' + query).expect(400);
  });
  it('persists idempotent follow and unfollow, accurate counts and availability after reopening', async () => {
    await member('owner');
    await member('alice');
    const saved = (await follow('alice', true).expect(200)).body;
    expect(saved.state).toEqual({
      version: 1,
      followingIDs: ['alice'],
      followerCount: 0,
    });
    expect(saved.person.followerCount).toBe(1);
    const retried = (await follow('alice', true).expect(200)).body;
    expect(retried.state.version).toBe(1);
    expect(retried.person.followerCount).toBe(1);
    expect((await get('people/suggestions').expect(200)).body.users).toEqual(
      [],
    );
    expect(
      (await get('me').expect(200)).body.onboarding.followedUserIDs,
    ).toEqual(['alice']);
    expect(
      (await get('people/owner').expect(200)).body.person.followingCount,
    ).toBe(1);
    const removed = (await follow('alice', false).expect(200)).body;
    expect(removed.state.followingIDs).toEqual([]);
    expect(removed.person.followerCount).toBe(0);
    expect((await follow('alice', false).expect(200)).body.state.version).toBe(
      2,
    );
    expect(
      (await get('people/suggestions').expect(200)).body.users,
    ).toHaveLength(1);
    expect(
      (await get('me').expect(200)).body.onboarding.followedUserIDs,
    ).toEqual([]);
  });
  it('a completed onboarding write cannot resurrect old relationships or require three follows again', async () => {
    await member('owner');
    await member('alice');
    await member('bruno');
    await follow('alice', true).expect(200);
    await follow('alice', false).expect(200);
    await follow('bruno', true).expect(200);
    const current = (await get('me').expect(200)).body.onboarding;
    const result = await request(app.getHttpServer())
      .put('/api/v1/me/onboarding')
      .auth('owner', { type: 'bearer' })
      .send({ ...current, followedUserIDs: ['alice'] })
      .expect(200);
    expect(result.body.followedUserIDs).toEqual(['bruno']);
    expect(
      (await get('people/owner').expect(200)).body.state.followingIDs,
    ).toEqual(['bruno']);
  });
  it('serializes duplicate and reciprocal writes without changing another account', async () => {
    await member('owner');
    await member('alice');
    await member('bruno');
    const results = await Promise.all([
      follow('alice', true),
      follow('alice', true),
      follow('owner', true, 'alice'),
    ]);
    expect(results.map((r) => r.status)).toEqual([200, 200, 200]);
    expect((await get('people/owner').expect(200)).body.person).toMatchObject({
      followerCount: 1,
      followingCount: 1,
    });
    expect(
      (await get('people/owner', 'bruno').expect(200)).body.state.followingIDs,
    ).toEqual([]);
  });
  it('excludes unavailable accounts from discovery and counts and rejects self, unknown, and invalid writes', async () => {
    await member('owner');
    await member('alice');
    await member('draft', false);
    await follow('alice', true).expect(200);
    await db.query(
      "UPDATE profiles SET deletion_requested_at=now() WHERE firebase_uid='alice'",
    );
    expect((await get('people').expect(200)).body.users).toEqual([]);
    expect(
      (await get('people/owner').expect(200)).body.person.followingCount,
    ).toBe(0);
    for (const target of ['alice', 'draft', 'missing']) {
      await follow(target, true).expect(404);
      await get('people/' + target).expect(404);
    }
    await follow('owner', true).expect(409);
    await request(app.getHttpServer())
      .put('/api/v1/me/follows/alice')
      .auth('owner', { type: 'bearer' })
      .send({ following: true, uid: 'bruno' })
      .expect(400);
  });
  it('rolls back the relationship when the transaction fails and permits a safe retry', async () => {
    await member('owner');
    await member('alice');
    await db.query(`CREATE FUNCTION reject_follow_version() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test failure'; END $$;
      CREATE TRIGGER reject_follow_version BEFORE UPDATE ON onboarding FOR EACH ROW EXECUTE FUNCTION reject_follow_version()`);
    try {
      await follow('alice', true).expect(503);
      expect(
        (await get('people/owner').expect(200)).body.state.followingIDs,
      ).toEqual([]);
    } finally {
      await db.query(
        'DROP TRIGGER reject_follow_version ON onboarding; DROP FUNCTION reject_follow_version()',
      );
    }
    await follow('alice', true).expect(200);
  });
});
