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
describe.skipIf(!databaseURL)('Diary and reviews with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const schema = 'activity_test_' + randomUUID().replaceAll('-', '');
  const verifier = {
    verify: vi.fn(async (uid: string) => ({
      uid,
      email_verified: true,
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: 'google.com' },
    })),
    deleteUser: vi.fn(async () => {}),
  };
  const input = () => ({
    itemId: 'm-civil',
    loggedAt: '2026-09-30T23:30:00.000Z',
    rating: 4.5,
    liked: true,
    rewatch: false,
    spoiler: true,
    text: 'Minha review, sem tradução automática.',
  });
  const save = (uid: string, id: string, body: object) =>
    request(app.getHttpServer())
      .put('/api/v1/me/diary/' + id)
      .auth(uid, { type: 'bearer' })
      .send(body);
  const read = (uid: string) =>
    request(app.getHttpServer())
      .get('/api/v1/me/activity')
      .auth(uid, { type: 'bearer' });
  const profile = (uid: string) =>
    db.query(
      'INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES($1,$1,$1,$2)',
      [uid, '#F4A814'],
    );
  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: databaseURL });
    await admin.query(`CREATE SCHEMA "${schema}"`);
    const url = new URL(databaseURL!);
    url.searchParams.set('options', `-c search_path=${schema}`);
    db = new DatabaseService(
      new ConfigService({ DATABASE_URL: url.toString() }),
    );
    const migrations = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(migrations))
      .filter((n) => n.endsWith('.sql'))
      .sort())
      await db.query(await readFile(new URL(name, migrations), 'utf8'));
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(DatabaseService)
      .useValue(db)
      .overrideProvider(FirebaseTokenVerifier)
      .useValue(verifier)
      .compile();
    app = module.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1'); // Keep one port per suite; concurrent Supertest requests must not close/rebind it.
  });
  afterAll(async () => {
    await app?.close();
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await admin.end();
    }
  });
  afterEach(async () => {
    await db.query('DELETE FROM profiles');
    await db.query('DELETE FROM account_deletions');
  });

  it('keeps retired-universe history in storage without returning it to the app', async () => {
    await profile('owner');
    const retiredID = randomUUID();
    await db.query(
      "INSERT INTO diary_entries(firebase_uid,id,item_id,logged_at,rating) VALUES('owner',$1,'w-wotlk',now(),4)",
      [retiredID],
    );
    await db.query(
      "INSERT INTO reviews(firebase_uid,entry_id,text,spoiler) VALUES('owner',$1,'Legacy review',false)",
      [retiredID],
    );
    const heroID = randomUUID();
    await save('owner', heroID, input()).expect(200);
    for (const locale of ['pt-BR', 'en']) {
      const snapshot = (
        await read('owner').set('Accept-Language', locale).expect(200)
      ).body;
      expect(snapshot.entries.map((e: { id: string }) => e.id)).toEqual([
        heroID,
      ]);
      expect(snapshot.reviews.map((r: { item: string }) => r.item)).toEqual([
        'm-civil',
      ]);
      expect(snapshot.items.map((i: { id: string }) => i.id)).toEqual([
        'm-civil',
      ]);
      expect(snapshot.universes.map((u: { id: string }) => u.id)).toEqual([
        'marvel',
      ]);
    }
    expect(
      (await db.query('SELECT 1 FROM diary_entries WHERE id=$1', [retiredID]))
        .rowCount,
    ).toBe(1);
    await save('owner', randomUUID(), { ...input(), itemId: 'w-wotlk' }).expect(
      409,
    );
  });

  it('requires authentication and a real profile; an empty diary is a successful read', async () => {
    await request(app.getHttpServer()).get('/api/v1/me/activity').expect(401);
    await read('missing').expect(404);
    await profile('owner');
    expect((await read('owner').expect(200)).body).toEqual({
      entries: [],
      reviews: [],
      items: [],
      universes: [],
      followerCount: 0,
    });
    await save('owner', randomUUID(), {
      ...input(),
      firebase_uid: 'another',
    }).expect(400);
  });

  it('persists a complete log and preserves user text while localizing catalog references', async () => {
    await profile('owner');
    const id = randomUUID();
    const saved = await save('owner', id, input()).expect(200);
    expect(saved.body.entries).toEqual([
      {
        id,
        itemId: 'm-civil',
        loggedAt: input().loggedAt,
        rating: 4.5,
        liked: true,
        rewatch: false,
      },
    ]);
    expect(saved.body.reviews[0]).toMatchObject({
      user: 'owner',
      item: 'm-civil',
      rating: 4.5,
      text: input().text,
      spoiler: true,
    });
    const restored = await read('owner')
      .set('Accept-Language', 'en-US')
      .expect(200);
    expect(restored.body.entries).toEqual(saved.body.entries);
    expect(restored.body.reviews).toEqual(saved.body.reviews);
    expect(restored.body.items[0]).toMatchObject({
      avg: 4.5,
      logCount: 1,
      reviewCount: 1,
      ratingHistogram: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0],
    });
    expect(restored.body.items[0].desc).not.toBe(saved.body.items[0].desc);
  });

  it('deduplicates concurrent retries, preserves repeated visits, and weights each person once', async () => {
    await profile('owner');
    await profile('other');
    const id = randomUUID();
    const results = await Promise.all([
      save('owner', id, input()),
      save('owner', id, input()),
    ]);
    expect(results.map((r) => r.status)).toEqual([200, 200]);
    expect(results[0].body.reviews[0].id).toBe(results[1].body.reviews[0].id);
    const second = randomUUID();
    await save('owner', second, {
      ...input(),
      rating: 2,
      rewatch: true,
    }).expect(200);
    // A retry of the old request must not promote its old rating over the new one.
    const retried = await save('owner', id, input()).expect(200);
    expect(retried.body.entries).toHaveLength(2);
    expect(retried.body.items[0]).toMatchObject({
      avg: 2,
      logCount: 2,
      reviewCount: 2,
    });
    await save('other', id, { ...input(), rating: 4 }).expect(200);
    expect((await read('other').expect(200)).body.entries).toHaveLength(1);
    const mine = (await read('owner').expect(200)).body;
    expect(mine.entries).toHaveLength(2);
    expect(
      mine.reviews.every((r: { user: string }) => r.user === 'owner'),
    ).toBe(true);
    expect(mine.items[0]).toMatchObject({
      avg: 3,
      logCount: 3,
      reviewCount: 3,
      ratingHistogram: [0, 0, 0, 1, 0, 0, 0, 1, 0, 0],
    });
  });

  it('uses the same real rating distribution in activity, search, and details, excluding deleting accounts', async () => {
    await profile('owner');
    await profile('other');
    const empty = (
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/m-ultimato')
        .expect(200)
    ).body;
    expect(empty.item.ratingHistogram).toEqual(Array(10).fill(0));
    await save('owner', randomUUID(), {
      ...input(),
      itemId: 'm-ultimato',
      rating: 0.5,
    }).expect(200);
    await save('other', randomUUID(), {
      ...input(),
      itemId: 'm-ultimato',
      rating: 5,
    }).expect(200);
    // An unrated revisit does not erase the last actual rating.
    await save('owner', randomUUID(), {
      ...input(),
      itemId: 'm-ultimato',
      rating: 0,
      text: '',
    }).expect(200);
    await db.query(
      "UPDATE profiles SET deletion_requested_at=now() WHERE firebase_uid='other'",
    );
    const activity = (await read('owner').expect(200)).body;
    const catalog = (
      await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
    ).body;
    const search = (
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel?type=Filme')
        .expect(200)
    ).body;
    const detail = (
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/m-ultimato')
        .expect(200)
    ).body;
    for (const item of [
      activity.items[0],
      catalog.items.find((i: { id: string }) => i.id === 'm-ultimato'),
      search.items.find((i: { id: string }) => i.id === 'm-ultimato'),
      detail.item,
    ]) {
      expect(item).toMatchObject({
        avg: 0.5,
        logCount: 2,
        reviewCount: 1,
        ratingHistogram: [1, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      });
    }
  });

  it('orders same-time revisits by creation time so profile favorites use the newest log', async () => {
    await profile('owner');
    const first = '00000000-0000-4000-8000-000000000001';
    const latest = '00000000-0000-4000-8000-000000000002';
    await save('owner', first, { ...input(), liked: true }).expect(200);
    const snapshot = (
      await save('owner', latest, {
        ...input(),
        liked: false,
        rewatch: true,
      }).expect(200)
    ).body;
    expect(snapshot.entries.map((entry: { id: string }) => entry.id)).toEqual([
      latest,
      first,
    ]);
    expect(snapshot.entries[0].liked).toBe(false);
  });

  it('allows no rating or text, validates invalid fields, and updates the same draft safely', async () => {
    await profile('owner');
    const id = randomUUID();
    expect(
      (await save('owner', id, { ...input(), rating: 0, text: '' }).expect(200))
        .body.reviews,
    ).toEqual([]);
    const changed = await save('owner', id, {
      ...input(),
      text: '  Nova review  ',
    }).expect(200);
    expect(changed.body.entries).toHaveLength(1);
    expect(changed.body.reviews[0].text).toBe('Nova review');
    for (const overrides of [
      { rating: 4.2 },
      { rating: 6 },
      { text: 'x'.repeat(5001) },
      { loggedAt: 'not-a-date' },
      { liked: 'true' },
    ])
      await save('owner', randomUUID(), { ...input(), ...overrides }).expect(
        400,
      );
    expect(
      (
        await save('owner', randomUUID(), {
          ...input(),
          loggedAt: new Date(Date.now() + 86400000).toISOString(),
        }).expect(400)
      ).body.code,
    ).toBe('INVALID_LOG_DATE');
    expect(
      (
        await save('owner', randomUUID(), {
          ...input(),
          itemId: 'missing',
        }).expect(409)
      ).body.code,
    ).toBe('ITEM_UNAVAILABLE');
    expect((await read('owner').expect(200)).body.entries).toHaveLength(1);
  });

  it('keeps archived works in history while rejecting new logs for them', async () => {
    await profile('owner');
    await save('owner', randomUUID(), input()).expect(200);
    await db.query(
      "UPDATE catalog_items SET status='archived' WHERE id='m-civil'",
    );
    try {
      const diary = (await read('owner').expect(200)).body;
      expect(diary.entries).toHaveLength(1);
      expect(diary.items[0].id).toBe('m-civil');
      const catalog = (
        await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
      ).body;
      expect(
        catalog.items.some((i: { id: string }) => i.id === 'm-civil'),
      ).toBe(false);
      await save('owner', randomUUID(), input()).expect(409);
    } finally {
      await db.query(
        "UPDATE catalog_items SET status='published' WHERE id='m-civil'",
      );
    }
  });

  it('rolls back the diary if saving its review fails, then allows a safe retry', async () => {
    await profile('owner');
    const id = randomUUID();
    await db.query(`CREATE FUNCTION reject_review() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'test failure'; END $$;
      CREATE TRIGGER reject_review BEFORE INSERT ON reviews FOR EACH ROW EXECUTE FUNCTION reject_review()`);
    try {
      await save('owner', id, input()).expect(503);
      expect((await read('owner').expect(200)).body.entries).toEqual([]);
    } finally {
      await db.query(
        'DROP TRIGGER reject_review ON reviews; DROP FUNCTION reject_review()',
      );
    }
    expect(
      (await save('owner', id, input()).expect(200)).body.entries,
    ).toHaveLength(1);
  });

  it('deletes entries and reviews with the account and removes their aggregate contribution', async () => {
    await profile('owner');
    await save('owner', randomUUID(), input()).expect(200);
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('owner', { type: 'bearer' })
      .expect(200);
    expect((await db.query('SELECT * FROM diary_entries')).rowCount).toBe(0);
    expect((await db.query('SELECT * FROM reviews')).rowCount).toBe(0);
    expect(
      (
        await db.query(
          "SELECT average,log_count FROM catalog_item_statistics WHERE item_id='m-civil'",
        )
      ).rows[0],
    ).toEqual({ average: 0, log_count: 0 });
    await read('owner').expect(403);
    await save('owner', randomUUID(), input()).expect(403);
  });
});
