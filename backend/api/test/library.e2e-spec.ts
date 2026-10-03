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
describe.skipIf(!databaseURL)('Personal library with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  let migratedFavorites: string[];
  const schema = 'library_test_' + randomUUID().replaceAll('-', '');
  const verifier = {
    verify: vi.fn(async (uid: string) => ({
      uid,
      email_verified: true,
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: 'google.com' },
    })),
    deleteUser: vi.fn(async () => {}),
  };
  const read = (uid = 'owner') =>
    request(app.getHttpServer())
      .get('/api/v1/me/library')
      .auth(uid, { type: 'bearer' });
  const mutate = (body: object, uid = 'owner') =>
    request(app.getHttpServer())
      .put('/api/v1/me/library')
      .auth(uid, { type: 'bearer' })
      .send(body);
  const operation = (action: string, version: number, rest: object = {}) => ({
    action,
    version,
    mutationID: randomUUID(),
    ...rest,
  });
  const profile = async (uid = 'owner') => {
    await db.query(
      'INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES($1,$1,$1,$2)',
      [uid, '#F4A814'],
    );
    await db.query(
      "INSERT INTO onboarding(firebase_uid,completed,step,universe_ids) VALUES($1,true,3,'{marvel}')",
      [uid],
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
    const migrations = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(migrations))
      .filter((n) => n.endsWith('.sql'))
      .sort()) {
      if (name === '013_personal_library.sql') {
        await profile('migrated');
        await db.query(`INSERT INTO diary_entries(firebase_uid,id,item_id,logged_at,rating,liked) VALUES
          ('migrated',gen_random_uuid(),'m-civil','2026-01-01',4,true),
          ('migrated',gen_random_uuid(),'m-civil','2026-02-01',4,false),
          ('migrated',gen_random_uuid(),'d-flash','2026-01-01',4,false),
          ('migrated',gen_random_uuid(),'d-flash','2026-02-01',4,true)`);
      }
      await db.query(await readFile(new URL(name, migrations), 'utf8'));
    }
    migratedFavorites = (
      await db.query(
        "SELECT item_id FROM library_marks WHERE firebase_uid='migrated' AND favorite ORDER BY item_id",
      )
    ).rows.map((r) => r.item_id);
    await db.query("DELETE FROM profiles WHERE firebase_uid='migrated'");
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

  it('preserves only the latest diary favorite state during migration', () => {
    expect(migratedFavorites).toEqual(['d-flash']);
  });

  it('requires verified membership and returns an empty private library', async () => {
    await request(app.getHttpServer()).get('/api/v1/me/library').expect(401);
    await read('unknown').expect(409);
    await profile();
    expect((await read().expect(200)).body).toEqual({
      version: 0,
      wantedIDs: [],
      favoriteIDs: [],
      lists: [],
    });
  });
  it('persists independent wanted/favorite flags across reads and accounts', async () => {
    await profile();
    await profile('other');
    await mutate(
      operation('wanted', 0, { itemID: 'm-civil', enabled: true }),
    ).expect(200);
    await mutate(
      operation('favorite', 1, { itemID: 'm-civil', enabled: true }),
    ).expect(200);
    await mutate(
      operation('wanted', 2, { itemID: 'm-civil', enabled: false }),
    ).expect(200);
    expect((await read().expect(200)).body).toMatchObject({
      version: 3,
      wantedIDs: [],
      favoriteIDs: ['m-civil'],
    });
    expect((await read('other').expect(200)).body.favoriteIDs).toEqual([]);
  });
  it('creates, edits, fills and deletes lists without affecting marks or the diary', async () => {
    await profile();
    const id = randomUUID();
    await mutate(
      operation('create_list', 0, {
        listID: id,
        title: 'Maratona',
        description: 'Para depois',
      }),
    ).expect(200);
    await mutate(
      operation('add_item', 1, { listID: id, itemID: 'm-civil' }),
    ).expect(200);
    await mutate(
      operation('add_item', 2, { listID: id, itemID: 'm-civil' }),
    ).expect(200);
    const renamed = (
      await mutate(
        operation('update_list', 3, {
          listID: id,
          title: 'Minha lista',
          description: '',
        }),
      ).expect(200)
    ).body;
    expect(renamed.state.lists[0]).toMatchObject({
      id,
      title: 'Minha lista',
      description: '',
      itemIDs: ['m-civil'],
    });
    await mutate(
      operation('remove_item', 4, { listID: id, itemID: 'm-civil' }),
    ).expect(200);
    expect((await read().expect(200)).body.lists[0].itemIDs).toEqual([]);
    await mutate(operation('delete_list', 5, { listID: id })).expect(200);
    expect((await read().expect(200)).body.lists).toEqual([]);
    expect((await db.query('SELECT 1 FROM diary_entries')).rowCount).toBe(0);
  });
  it('returns the latest state on retry without reversing another device update or resurrecting deleted lists', async () => {
    await profile();
    const id = randomUUID(),
      first = operation('create_list', 0, {
        listID: id,
        title: 'Original',
        description: '',
      });
    await mutate(first).expect(200);
    await mutate(operation('delete_list', 1, { listID: id })).expect(200);
    const retry = (await mutate(first).expect(200)).body;
    expect(retry.appliedVersion).toBe(1);
    expect(retry.state.version).toBe(2);
    expect(retry.state.lists).toEqual([]);
    await mutate({ ...first, title: 'Different' }).expect(409);
  });
  it('rejects stale writes and serializes simultaneous devices without lost changes', async () => {
    await profile();
    const results = await Promise.all([
      mutate(operation('wanted', 0, { itemID: 'm-civil', enabled: true })),
      mutate(operation('favorite', 0, { itemID: 'm-civil', enabled: true })),
    ]);
    expect(results.map((r) => r.status).sort()).toEqual([200, 409]);
    expect(results.find((r) => r.status === 409)?.body.code).toBe(
      'LIBRARY_STALE',
    );
    expect((await read().expect(200)).body.version).toBe(1);
  });
  it('does not allow another account to read, edit, delete or fill a private list', async () => {
    await profile();
    await profile('other');
    const id = randomUUID();
    await mutate(
      operation('create_list', 0, {
        listID: id,
        title: 'Private',
        description: 'Private description',
      }),
    ).expect(200);
    await mutate(
      operation('update_list', 0, {
        listID: id,
        title: 'Hacked',
        description: '',
      }),
      'other',
    ).expect(404);
    await mutate(
      operation('add_item', 0, { listID: id, itemID: 'm-civil' }),
      'other',
    ).expect(404);
    await mutate(operation('delete_list', 0, { listID: id }), 'other').expect(
      404,
    );
    expect((await read('other').expect(200)).body.lists).toEqual([]);
  });
  it('validates action-specific fields, rejects whitespace, extra ownership and null flags', async () => {
    await profile();
    await mutate(
      operation('favorite', 0, { itemID: 'm-civil', enabled: null }),
    ).expect(400);
    await mutate(
      operation('favorite', 0, {
        itemID: 'm-civil',
        enabled: true,
        title: 'extra',
      }),
    ).expect(400);
    await mutate(
      operation('favorite', 0, {
        itemID: 'm-civil',
        enabled: true,
        firebase_uid: 'other',
      }),
    ).expect(400);
    await mutate(
      operation('create_list', 0, {
        listID: randomUUID(),
        title: '   ',
        description: '',
      }),
    ).expect(400);
    await mutate(
      operation('create_list', 0, { listID: randomUUID(), title: 'Name' }),
    ).expect(400);
    await mutate(
      operation('add_item', 0, { listID: randomUUID(), itemID: '../private' }),
    ).expect(400);
    expect((await read().expect(200)).body.version).toBe(0);
  });
  it('rejects unavailable catalog additions while allowing removal of saved unavailable items', async () => {
    await profile();
    const id = randomUUID();
    await mutate(
      operation('wanted', 0, { itemID: 'not-published', enabled: true }),
    ).expect(404);
    await mutate(
      operation('create_list', 0, {
        listID: id,
        title: 'List',
        description: '',
      }),
    ).expect(200);
    await mutate(
      operation('wanted', 1, { itemID: 'm-civil', enabled: true }),
    ).expect(200);
    await mutate(
      operation('add_item', 2, { listID: id, itemID: 'm-civil' }),
    ).expect(200);
    await db.query(
      "UPDATE catalog_items SET status='archived' WHERE id='m-civil'",
    );
    try {
      await mutate(
        operation('favorite', 3, { itemID: 'm-civil', enabled: true }),
      ).expect(404);
      await mutate(
        operation('remove_item', 3, { listID: id, itemID: 'm-civil' }),
      ).expect(200);
      await mutate(
        operation('wanted', 4, { itemID: 'm-civil', enabled: false }),
      ).expect(200);
    } finally {
      await db.query(
        "UPDATE catalog_items SET status='published' WHERE id='m-civil'",
      );
    }
  });
  it('enforces list limits and rate limits, but allows idempotent retries at the limit', async () => {
    await profile();
    for (let i = 0; i < 50; i++)
      await mutate(
        operation('create_list', i, {
          listID: randomUUID(),
          title: 'List ' + i,
          description: '',
        }),
      ).expect(200);
    await mutate(
      operation('create_list', 50, {
        listID: randomUUID(),
        title: 'One too many',
        description: '',
      }),
    ).expect(409);
    const input = operation('favorite', 50, {
      itemID: 'm-civil',
      enabled: true,
    });
    await mutate(input).expect(200);
    await db.query(
      "UPDATE library_state SET requests=120,window_start=now() WHERE firebase_uid='owner'",
    );
    await mutate(input).expect(200);
    await mutate(
      operation('favorite', 51, { itemID: 'm-civil', enabled: false }),
    ).expect(429);
  });
  it('cascades lists, marks, receipts and version on account deletion', async () => {
    await profile();
    const id = randomUUID();
    await mutate(
      operation('create_list', 0, {
        listID: id,
        title: 'Private',
        description: '',
      }),
    ).expect(200);
    await mutate(
      operation('add_item', 1, { listID: id, itemID: 'm-civil' }),
    ).expect(200);
    await mutate(
      operation('favorite', 2, { itemID: 'm-civil', enabled: true }),
    ).expect(200);
    await db.query("DELETE FROM profiles WHERE firebase_uid='owner'");
    for (const table of [
      'personal_lists',
      'personal_list_items',
      'library_marks',
      'library_state',
      'library_mutations',
    ])
      expect((await db.query(`SELECT 1 FROM ${table}`)).rowCount).toBe(0);
  });
});
