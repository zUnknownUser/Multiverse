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
describe.skipIf(!databaseURL)(
  'Editorial reading orders with PostgreSQL',
  () => {
    let app: INestApplication, admin: pg.Pool, db: DatabaseService;
    const schema = 'orders_test_' + randomUUID().replaceAll('-', '');
    const orderID = 'marvel-event-highlights';
    const get = (uid = 'alice', lang = 'pt-BR') =>
      request(app.getHttpServer())
        .get('/api/v1/me/reading-orders')
        .auth(uid, { type: 'bearer' })
        .set('Accept-Language', lang);
    const put = (body: object, uid = 'alice') =>
      request(app.getHttpServer())
        .put('/api/v1/me/reading-orders')
        .auth(uid, { type: 'bearer' })
        .send(body);
    const input = (version = 0, action = 'following', enabled = true) => ({
      mutationID: randomUUID(),
      version,
      orderID,
      action,
      enabled,
    });
    beforeAll(async () => {
      admin = new pg.Pool({ connectionString: databaseURL });
      await admin.query(`CREATE SCHEMA "${schema}"`);
      const url = new URL(databaseURL!);
      url.searchParams.set('options', `-c search_path=${schema}`);
      db = new DatabaseService(
        new ConfigService({ DATABASE_URL: url.toString() }),
      );
      const folder = new URL('../migrations/', import.meta.url);
      for (const n of (await readdir(folder))
        .filter((n) => n.endsWith('.sql'))
        .sort())
        await db.query(await readFile(new URL(n, folder), 'utf8'));
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
      await app.listen(0, '127.0.0.1');
    });
    beforeEach(async () => {
      for (const uid of ['alice', 'bob']) {
        await db.query(
          "INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES($1,$1,$1,'#F4A814')",
          [uid],
        );
        await db.query(
          "INSERT INTO onboarding(firebase_uid,completed,step,universe_ids) VALUES($1,true,3,'{marvel}')",
          [uid],
        );
      }
    });
    afterEach(async () => {
      await db.query('DELETE FROM profiles');
      await db.query('DELETE FROM account_deletions');
      await db.query(
        "UPDATE catalog_items SET status='published' WHERE id='m-civil'",
      );
      await db.query("UPDATE reading_orders SET status='published'");
    });
    afterAll(async () => {
      await app?.close();
      if (admin) {
        await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
        await admin.end();
      }
    });
    it('publishes three bilingual journeys with catalog references and no invented counts', async () => {
      const pt = (await get().expect(200)).body,
        en = (await get('alice', 'en-US').expect(200)).body;
      expect(pt.locale).toBe('pt-BR');
      expect(en.locale).toBe('en');
      expect(pt.orders).toHaveLength(3);
      const catalog = (
        await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
      ).body.items;
      for (const order of pt.orders) {
        expect(order).toMatchObject({
          by: 'multiverse',
          votes: 0,
          followers: 0,
          following: false,
          voted: false,
        });
        expect(order.steps.length).toBeGreaterThan(1);
        for (const step of order.steps)
          expect(
            catalog.some(
              (i: { id: string; uni: string; type: string }) =>
                i.id === step && i.uni === order.uni && i.type === 'HQ',
            ),
          ).toBe(true);
        expect(
          en.orders.find((o: { id: string }) => o.id === order.id).title,
        ).not.toBe(order.title);
      }
    });
    it('persists follows and votes independently, counts unique accounts, and removes them', async () => {
      await put(input()).expect(200);
      await put(input(1, 'voted')).expect(200);
      await put(input(0, 'voted'), 'bob').expect(200);
      const alice = (await get().expect(200)).body.orders.find(
        (o: { id: string }) => o.id === orderID,
      );
      expect(alice).toMatchObject({
        following: true,
        voted: true,
        votes: 2,
        followers: 1,
      });
      expect(
        (await get('bob').expect(200)).body.orders.find(
          (o: { id: string }) => o.id === orderID,
        ),
      ).toMatchObject({
        following: false,
        voted: true,
        votes: 2,
        followers: 1,
      });
      await put(input(2, 'following', false)).expect(200);
      await put(input(3, 'voted', false)).expect(200);
      expect((await get().expect(200)).body.orders[0]).toMatchObject({
        following: false,
        voted: false,
        votes: 1,
        followers: 0,
      });
    });
    it('makes concurrent retry idempotent and returns current state after later changes', async () => {
      const on = input();
      await Promise.all([put(on).expect(200), put(on).expect(200)]);
      await put(input(1, 'following', false)).expect(200);
      const retry = (await put(on).expect(200)).body;
      expect(retry.appliedVersion).toBe(1);
      expect(retry.state.version).toBe(2);
      expect(retry.state.orders[0].following).toBe(false);
      await put({ ...on, enabled: false }).expect(409);
      expect(
        (await db.query('SELECT * FROM reading_order_mutations')).rows,
      ).toHaveLength(2);
    });
    it('rejects stale devices instead of overwriting another choice', async () => {
      await put(input()).expect(200);
      const stale = await put(input(0, 'voted')).expect(409);
      expect(stale.body.code).toBe('ORDER_STALE');
      expect((await get().expect(200)).body.orders[0]).toMatchObject({
        following: true,
        voted: false,
      });
    });
    it('hides a whole journey when any step is unavailable and preserves existing state', async () => {
      const on = input();
      await put(on).expect(200);
      await db.query(
        "UPDATE catalog_items SET status='archived' WHERE id='m-civil'",
      );
      expect(
        (await get().expect(200)).body.orders.map((o: { id: string }) => o.id),
      ).not.toContain(orderID);
      expect((await put(input(1, 'voted')).expect(404)).body.code).toBe(
        'ORDER_UNAVAILABLE',
      );
      await put(on).expect(200);
      await db.query(
        "UPDATE catalog_items SET status='published' WHERE id='m-civil'",
      );
      expect((await get().expect(200)).body.orders[0].following).toBe(true);
      await db.query('UPDATE reading_orders SET status=$2 WHERE id=$1', [
        orderID,
        'draft',
      ]);
      expect((await get().expect(200)).body.orders).toHaveLength(2);
    });
    it('excludes incomplete translations, cross-universe steps and non-comics', async () => {
      await db.query(
        "UPDATE reading_order_steps SET item_id='d-flash' WHERE order_id=$1 AND position=1",
        [orderID],
      );
      try {
        expect((await get().expect(200)).body.orders).toHaveLength(2);
      } finally {
        await db.query(
          "UPDATE reading_order_steps SET item_id='m-fenix' WHERE order_id=$1 AND position=1",
          [orderID],
        );
      }
      await db.query(
        "UPDATE reading_order_steps SET item_id='c-wanda' WHERE order_id=$1 AND position=1",
        [orderID],
      );
      try {
        expect((await get().expect(200)).body.orders).toHaveLength(2);
      } finally {
        await db.query(
          "UPDATE reading_order_steps SET item_id='m-fenix' WHERE order_id=$1 AND position=1",
          [orderID],
        );
      }
      const en = (
        await db.query(
          "DELETE FROM reading_order_translations WHERE order_id=$1 AND locale='en' RETURNING *",
          [orderID],
        )
      ).rows[0];
      try {
        expect((await get().expect(200)).body.orders).toHaveLength(2);
      } finally {
        await db.query(
          'INSERT INTO reading_order_translations(order_id,locale,title,description) VALUES($1,$2,$3,$4)',
          [en.order_id, en.locale, en.title, en.description],
        );
      }
    });
    it('keeps diary progress backed by distinct works rather than follow or vote actions', async () => {
      await put(input()).expect(200);
      for (let i = 0; i < 2; i++)
        await request(app.getHttpServer())
          .put('/api/v1/me/diary/' + randomUUID())
          .auth('alice', { type: 'bearer' })
          .send({
            itemId: 'm-civil',
            loggedAt: '2026-09-01T12:00:00Z',
            rating: 4,
            liked: false,
            rewatch: i > 0,
            spoiler: false,
            text: '',
          })
          .expect(200);
      const activity = (
        await request(app.getHttpServer())
          .get('/api/v1/me/activity')
          .auth('alice', { type: 'bearer' })
          .expect(200)
      ).body;
      const registered = new Set(
        activity.entries.map((e: { itemId: string }) => e.itemId),
      );
      const order = (await get().expect(200)).body.orders[0];
      expect(order.steps.filter((id: string) => registered.has(id))).toEqual([
        'm-civil',
      ]);
      const other = (
        await request(app.getHttpServer())
          .get('/api/v1/me/activity')
          .auth('bob', { type: 'bearer' })
          .expect(200)
      ).body;
      expect(other.entries).toEqual([]);
    });
    it('cascades private state on account deletion and updates public counters', async () => {
      await put(input()).expect(200);
      await put(input(1, 'voted')).expect(200);
      await request(app.getHttpServer())
        .delete('/api/v1/me')
        .auth('alice', { type: 'bearer' })
        .expect(200);
      expect((await get('bob').expect(200)).body.orders[0]).toMatchObject({
        votes: 0,
        followers: 0,
      });
      for (const t of [
        'reading_order_marks',
        'reading_order_state',
        'reading_order_mutations',
      ])
        expect((await db.query(`SELECT * FROM ${t}`)).rows).toEqual([]);
    });
    it('requires a completed authenticated account and strict payloads', async () => {
      await request(app.getHttpServer())
        .get('/api/v1/me/reading-orders')
        .expect(401);
      await db.query(
        "UPDATE onboarding SET completed=false WHERE firebase_uid='bob'",
      );
      await get('bob').expect(409);
      await put({ ...input(), userID: 'bob' }).expect(400);
      await put({ ...input(), action: 'complete' }).expect(400);
      await put({ ...input(), enabled: 'true' }).expect(400);
      await put({ ...input(), version: -1 }).expect(400);
      await put({ ...input(), orderID: 'absent' }).expect(404);
    });
    it('limits new writes but permits confirmed retries', async () => {
      const first = input();
      await put(first).expect(200);
      await db.query(
        "INSERT INTO reading_order_mutations(firebase_uid,id,request,applied_version) SELECT 'alice',gen_random_uuid(),'{}',1 FROM generate_series(1,119)",
      );
      await put(input(1, 'voted')).expect(429);
      await put(first).expect(200);
    });
  },
);
