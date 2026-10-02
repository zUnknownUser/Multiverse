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
describe.skipIf(!databaseURL)('Social feed and safety with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const schema = 'social_test_' + randomUUID().replaceAll('-', '');
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
    await app.init();
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

  const privacy = (publicDiary: boolean, uid = 'alice') =>
    request(app.getHttpServer())
      .put('/api/v1/me/privacy')
      .auth(uid, { type: 'bearer' })
      .send({ publicDiary });
  const block = (uid: string, target: string, blocked = true) =>
    request(app.getHttpServer())
      .put('/api/v1/me/blocks/' + target)
      .auth(uid, { type: 'bearer' })
      .send({ blocked });
  const report = (id: string, alsoBlock = false) =>
    request(app.getHttpServer())
      .put('/api/v1/reviews/' + id + '/report')
      .auth('owner', { type: 'bearer' })
      .send({ reason: 'spam', alsoBlock });
  const input = {
    itemId: 'w-wotlk',
    loggedAt: '2026-09-30T23:30:00.000Z',
    rating: 4.5,
    liked: true,
    rewatch: false,
    spoiler: true,
    text: 'Minha review, não traduzir.',
  };
  const save = (uid: string, id = randomUUID()) =>
    request(app.getHttpServer())
      .put('/api/v1/me/diary/' + id)
      .auth(uid, { type: 'bearer' })
      .send(input);
  const setup = async () => {
    await member('owner');
    await member('alice');
    await member('bruno');
    await follow('alice', true).expect(200);
  };
  it('requires authentication and explicit opt-in for existing reviews, without losing private history', async () => {
    await setup();
    await request(app.getHttpServer()).get('/api/v1/feed').expect(401);
    await member('draft', false);
    await get('feed', 'draft').expect(409);
    const id = (await save('alice').expect(200)).body.reviews[0].id;
    expect(
      (await get('me/privacy', 'alice').expect(200)).body.publicDiary,
    ).toBe(false);
    expect((await get('feed').expect(200)).body.reviews).toEqual([]);
    await get('reviews/' + id).expect(404);
    expect((await get('feed', 'alice').expect(200)).body.reviews[0].id).toBe(
      id,
    );
    await privacy(true).expect(200);
    const page = (await get('feed').set('Accept-Language', 'en').expect(200))
      .body;
    expect(page.reviews[0]).toMatchObject({
      id,
      text: input.text,
      spoiler: true,
    });
    expect(page.items[0].id).toBe(input.itemId);
    expect(page.users[0].id).toBe('alice');
    expect(page.users[0]).not.toHaveProperty('email');
    await privacy(false).expect(200);
    expect((await get('feed').expect(200)).body.reviews).toEqual([]);
    await get('reviews/' + id).expect(404);
    expect(
      (await get('me/activity', 'alice').expect(200)).body.reviews,
    ).toHaveLength(1);
  });
  it('paginates microsecond timestamp ties without duplicates and rejects malformed cursors', async () => {
    await setup();
    await privacy(true).expect(200);
    for (let i = 0; i < 3; i++) await save('alice').expect(200);
    await db.query(
      "UPDATE reviews SET created_at='2026-10-01T10:00:00.123456Z'",
    );
    const ids: string[] = [];
    let cursor: string | null = null;
    for (let i = 0; i < 3; i++) {
      const page: { reviews: { id: string }[]; nextCursor: string | null } = (
        await get('feed?limit=1' + (cursor ? '&after=' + cursor : '')).expect(
          200,
        )
      ).body;
      ids.push(page.reviews[0].id);
      cursor = page.nextCursor;
    }
    expect(new Set(ids).size).toBe(3);
    expect(cursor).toBeNull();
    for (const q of [
      'limit=51',
      'after=not-json',
      'after=a&after=b',
      'extra=true',
    ])
      await get('feed?' + q).expect(400);
    await follow('alice', false).expect(200);
    expect((await get('feed').expect(200)).body.reviews).toEqual([]);
    await get('reviews/' + ids[0]).expect(200);
  });
  it('enforces reciprocal blocks on feed, details, discovery, follows and onboarding', async () => {
    await setup();
    await privacy(true).expect(200);
    const id = (await save('alice').expect(200)).body.reviews[0].id;
    await block('owner', 'alice').expect(200);
    await block('owner', 'alice').expect(200);
    expect(
      (await get('me/blocks').expect(200)).body.users.map(
        (u: { id: string }) => u.id,
      ),
    ).toEqual(['alice']);
    for (const [viewer, target] of [
      ['owner', 'alice'],
      ['alice', 'owner'],
    ]) {
      await get('people/' + target, viewer).expect(404);
      await follow(target, true, viewer).expect(404);
      for (const route of ['people', 'me/onboarding/suggestions'])
        expect(
          (await get(route, viewer).expect(200)).body.users.some(
            (u: { userID: string }) => u.userID === target,
          ),
        ).toBe(false);
    }
    expect((await get('feed').expect(200)).body.reviews).toEqual([]);
    await get('reviews/' + id).expect(404);
    expect(
      (await get('me').expect(200)).body.onboarding.followedUserIDs,
    ).toEqual([]);
    const progress = (await get('me').expect(200)).body.onboarding;
    await request(app.getHttpServer())
      .put('/api/v1/me/onboarding')
      .auth('owner', { type: 'bearer' })
      .send(progress)
      .expect(200);
    await block('owner', 'alice', false).expect(200);
    expect((await get('feed').expect(200)).body.reviews).toHaveLength(1);
    await block('owner', 'owner').expect(400);
  });
  it('records reports idempotently, hides for the reporter and supports atomic optional blocking', async () => {
    await setup();
    await privacy(true).expect(200);
    const id = (await save('alice').expect(200)).body.reviews[0].id;
    await report(id).expect(200);
    await report(id).expect(200);
    expect((await db.query('SELECT * FROM review_reports')).rowCount).toBe(1);
    expect((await get('feed').expect(200)).body.reviews).toEqual([]);
    await get('reviews/' + id).expect(404);
    await get('reviews/' + id, 'bruno').expect(200);
    await report(id, true).expect(200);
    await report(id, true).expect(200);
    await get('people/alice').expect(404);
    expect((await get('me/blocks').expect(200)).body.users).toHaveLength(1);
    expect(
      (await get('me/activity', 'alice').expect(200)).body.reviews,
    ).toHaveLength(1);
  });
  it('rolls back report when its optional block fails', async () => {
    await setup();
    await privacy(true).expect(200);
    const id = (await save('alice').expect(200)).body.reviews[0].id;
    await db.query(`CREATE FUNCTION reject_block() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test failure'; END $$;
      CREATE TRIGGER reject_block BEFORE INSERT ON user_blocks FOR EACH ROW EXECUTE FUNCTION reject_block()`);
    try {
      await report(id, true).expect(503);
      expect((await db.query('SELECT * FROM review_reports')).rowCount).toBe(0);
    } finally {
      await db.query(
        'DROP TRIGGER reject_block ON user_blocks; DROP FUNCTION reject_block()',
      );
    }
    await report(id, true).expect(200);
  });
  it('excludes removed, moderated, archived and incomplete authors', async () => {
    await setup();
    await privacy(true).expect(200);
    const id = (await save('alice').expect(200)).body.reviews[0].id;
    for (const [apply, undo] of [
      [
        "UPDATE profiles SET deletion_requested_at=now() WHERE firebase_uid='alice'",
        "UPDATE profiles SET deletion_requested_at=NULL WHERE firebase_uid='alice'",
      ],
      [
        "UPDATE reviews SET moderation_status='hidden'",
        "UPDATE reviews SET moderation_status='visible'",
      ],
      [
        "UPDATE catalog_items SET status='archived' WHERE id='w-wotlk'",
        "UPDATE catalog_items SET status='published' WHERE id='w-wotlk'",
      ],
      [
        "UPDATE onboarding SET completed=false WHERE firebase_uid='alice'",
        "UPDATE onboarding SET completed=true WHERE firebase_uid='alice'",
      ],
    ]) {
      await db.query(apply);
      expect((await get('feed').expect(200)).body.reviews).toEqual([]);
      await get('reviews/' + id).expect(404);
      await db.query(undo);
    }
    expect(
      (await get('me/activity', 'alice').expect(200)).body.reviews,
    ).toHaveLength(1);
  });
  it('limits reports without rejecting an idempotent retry and cleans safety data on account deletion', async () => {
    await setup();
    await privacy(true).expect(200);
    await db.query(`INSERT INTO diary_entries(firebase_uid,id,item_id,logged_at,rating)
      SELECT 'alice',gen_random_uuid(),'w-wotlk',now(),4 FROM generate_series(1,51)`);
    const reviews =
      await db.query(`INSERT INTO reviews(firebase_uid,entry_id,text)
      SELECT firebase_uid,id,'Review' FROM diary_entries WHERE firebase_uid='alice' RETURNING id`);
    await db.query(
      `INSERT INTO review_reports(reporter_uid,review_id,reason)
      SELECT 'owner',unnest($1::uuid[]),'spam'`,
      [reviews.rows.slice(0, 50).map((r) => r.id)],
    );
    await report(reviews.rows[50].id).expect(429);
    await report(reviews.rows[0].id, true).expect(200);
    await db.query("DELETE FROM profiles WHERE firebase_uid='alice'");
    expect((await db.query('SELECT * FROM review_reports')).rowCount).toBe(0);
    expect((await get('me/blocks').expect(200)).body.users).toEqual([]);
  });

  it('limits new public reviews but permits retries and rejects invalid safety writes', async () => {
    await setup();
    await privacy(true).expect(200);
    const retryID = randomUUID();
    await save('alice', retryID).expect(200);
    for (let i = 1; i < 20; i++) await save('alice').expect(200);
    await save('alice').expect(429);
    await save('alice', retryID).expect(200);
    const own = (await save('owner').expect(200)).body.reviews[0].id;
    await report(own).expect(400);
    await request(app.getHttpServer())
      .put('/api/v1/me/privacy')
      .auth('owner', { type: 'bearer' })
      .send({ publicDiary: 'true' })
      .expect(400);
    await request(app.getHttpServer())
      .put('/api/v1/me/blocks/alice')
      .auth('owner', { type: 'bearer' })
      .send({ blocked: true, uid: 'bruno' })
      .expect(400);
    await report(randomUUID()).expect(404);
  });
});
