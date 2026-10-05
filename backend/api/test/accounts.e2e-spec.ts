import sharp from 'sharp';
import { randomInt, randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import type { INestApplication } from '@nestjs/common';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FirebaseTokenVerifier } from '../src/auth/firebase-token-verifier.js';
import { AccountLifecycleService } from '../src/accounts/account-lifecycle.service.js';
import { AccountsService } from '../src/accounts/accounts.service.js';
import { configureApp } from '../src/configure-app.js';

const databaseURL = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseURL)('Account API with real PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let database: DatabaseService;
  const schema = 'account_test_' + randomUUID().replaceAll('-', '');
  const verifier = {
    verify: vi.fn(async (token: string) => {
      if (['expired', 'forged', 'revoked', 'disabled'].includes(token))
        throw { code: 'auth/invalid-id-token' };
      if (token === 'unavailable') throw { code: 'auth/internal-error' };
      return {
        uid: token,
        email_verified: token !== 'unverified',
        auth_time: token === 'old-login' ? 0 : Math.floor(Date.now() / 1000),
        firebase: { sign_in_provider: 'google.com' },
      };
    }),
    deleteUser: vi.fn(async (_uid: string) => {}),
  };
  const input = (username: string) => ({
    username,
    displayName: 'Test User',
    avatarColor: '#F4A814',
    bio: 'My bio',
  });
  const progress = (
    version = 0,
    completed = false,
    followedUserIDs: string[] = [],
  ) => ({
    universeIDs: ['marvel'],
    seenItemIDs: ['m-civil'],
    followedUserIDs,
    step: completed ? 3 : 2,
    completed,
    version,
  });
  const putProfile = (uid: string, username = uid.replaceAll('-', '_')) =>
    request(app.getHttpServer())
      .put('/api/v1/me/profile')
      .auth(uid, { type: 'bearer' })
      .send(input(username));
  const putProgress = (uid: string, value: ReturnType<typeof progress>) =>
    request(app.getHttpServer())
      .put('/api/v1/me/onboarding')
      .auth(uid, { type: 'bearer' })
      .send(value);

  beforeAll(async () => {
    admin = new pg.Pool({ connectionString: databaseURL });
    await admin.query(`CREATE SCHEMA "${schema}"`);
    const url = new URL(databaseURL!);
    url.searchParams.set('options', `-c search_path=${schema}`);
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: url.toString() }),
    );
    const migrations = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(migrations))
      .filter((name) => name.endsWith('.sql'))
      .sort()) {
      if (name === '019_heroes_scope.sql') {
        await database.query(`INSERT INTO profiles(firebase_uid,username,display_name,avatar_color)
          VALUES('pivot-mixed','pivot_mixed','Mixed','#000000'),('pivot-old','pivot_old','Old','#000000'),('pivot-done','pivot_done','Done','#000000');
          INSERT INTO onboarding(firebase_uid,universe_ids,seen_item_ids,step,version,completed) VALUES
          ('pivot-mixed','{wow,dc,marvel}','{w-wotlk,d-crise,m-civil}',2,5,false),
          ('pivot-old','{wow}','{w-wotlk}',2,5,false),
          ('pivot-done','{wow}','{w-wotlk}',3,5,true)`);
      }
      await database.query(await readFile(new URL(name, migrations), 'utf8'));
      if (name === '001_accounts.sql') {
        // Simulate an existing installation with an interrupted deletion before the upgrade.
        await database.query(
          `INSERT INTO profiles(firebase_uid,username,display_name,avatar_color,deletion_requested_at) VALUES('legacy-deletion','legacy_deleted','Legacy','#000000',now())`,
        );
      }
    }
    const module = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(DatabaseService)
      .useValue(database)
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

  it('migrates interrupted deletions from the previous schema and reconciles them', async () => {
    const migrated = await database.query(
      'SELECT completed_at FROM account_deletions WHERE firebase_uid=$1',
      ['legacy-deletion'],
    );
    expect(migrated.rows).toEqual([{ completed_at: null }]);
    await app.get(AccountLifecycleService).reconcileDeletions();
    expect(
      (
        await database.query('SELECT 1 FROM profiles WHERE firebase_uid=$1', [
          'legacy-deletion',
        ])
      ).rowCount,
    ).toBe(0);
    await putProfile('legacy-deletion').expect(403);
  });

  it('migrates retired preferences without inventing choices or resetting completed accounts', async () => {
    const result = await database.query(
      "SELECT firebase_uid,universe_ids,seen_item_ids,step,version,completed FROM onboarding WHERE firebase_uid LIKE 'pivot-%' ORDER BY firebase_uid",
    );
    expect(result.rows).toEqual([
      {
        firebase_uid: 'pivot-done',
        universe_ids: [],
        seen_item_ids: [],
        step: 3,
        version: 6,
        completed: true,
      },
      {
        firebase_uid: 'pivot-mixed',
        universe_ids: ['dc', 'marvel'],
        seen_item_ids: ['d-crise', 'm-civil'],
        step: 2,
        version: 6,
        completed: false,
      },
      {
        firebase_uid: 'pivot-old',
        universe_ids: [],
        seen_item_ids: [],
        step: 1,
        version: 6,
        completed: false,
      },
    ]);
    await database.query(
      "DELETE FROM profiles WHERE firebase_uid LIKE 'pivot-%'",
    );
    for (const locale of ['pt-BR', 'en']) {
      const response = await request(app.getHttpServer())
        .get('/api/v1/catalog')
        .set('Accept-Language', locale)
        .expect(200);
      expect(response.body.universes.map((u: { id: string }) => u.id)).toEqual([
        'marvel',
        'dc',
      ]);
      expect(response.body.comingSoon).toEqual([]);
      expect(
        response.body.items.every((i: { uni: string }) =>
          ['marvel', 'dc'].includes(i.uni),
        ),
      ).toBe(true);
      await request(app.getHttpServer())
        .get('/api/v1/catalog/wow/w-wotlk')
        .set('Accept-Language', locale)
        .expect(404);
    }
  });

  it('requires a valid, verified identity and leaves health public', async () => {
    await request(app.getHttpServer()).get('/api/v1/me').expect(401);
    for (const token of ['expired', 'forged', 'revoked', 'disabled'])
      await request(app.getHttpServer())
        .get('/api/v1/me')
        .auth(token, { type: 'bearer' })
        .expect(401);
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('unverified', { type: 'bearer' })
      .expect(403);
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('unavailable', { type: 'bearer' })
      .expect(503);
    await request(app.getHttpServer()).get('/api/v1/health').expect(200);
  });
  it('creates no fake profile, scopes ownership, validates payloads, and normalizes handles', async () => {
    const empty = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('owner', { type: 'bearer' })
      .expect(200);
    expect(empty.body.profile).toBeNull();
    expect(empty.headers['cache-control']).toBe('no-store');
    await putProfile('owner', 'Mixed.Case').expect(200);
    const me = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('owner', { type: 'bearer' })
      .expect(200);
    expect(me.body.profile).toMatchObject({
      userID: 'owner',
      username: 'mixed.case',
      displayName: 'Test User',
    });
    const other = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('other', { type: 'bearer' })
      .expect(200);
    expect(other.body.profile).toBeNull();
    await request(app.getHttpServer())
      .put('/api/v1/me/profile')
      .auth('owner', { type: 'bearer' })
      .send({ ...input('valid'), userID: 'other' })
      .expect(400);
    await putProfile('owner', 'x').expect(400);
    await putProfile('owner', 'admin').expect(409);
  });
  it('persists curated avatars, preserves them for old clients, validates IDs and allows initials', async () => {
    const uid = 'avatar-owner';
    const save = (extra: object) =>
      request(app.getHttpServer())
        .put('/api/v1/me/profile')
        .auth(uid, { type: 'bearer' })
        .send({ ...input('avatar_owner'), ...extra });
    for (const avatarID of ['vigilant', 'cosmic', 'robot']) {
      const response = await save({ avatarID }).expect(200);
      expect(response.body.avatarID).toBe(avatarID);
    }
    await save({}).expect(200);
    const own = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth(uid, { type: 'bearer' })
      .expect(200);
    expect(own.body.profile.avatarID).toBe('robot');
    await save({ avatarID: 'untrusted/path' }).expect(400);
    const cleared = await save({ avatarID: null }).expect(200);
    expect(cleared.body.avatarID).toBeNull();
    const other = await putProfile('avatar-other').expect(200);
    expect(other.body.avatarID).toBeNull();
  });

  it('edits profile details atomically and serves bounded private photos until removal or deletion', async () => {
    const uid = 'photo-owner';
    await putProfile(uid).expect(200);
    await putProgress(uid, progress(0, true)).expect(200);
    await putProfile('photo-reader').expect(200);
    await putProgress('photo-reader', progress(0, true)).expect(200);
    const photo = (
      await sharp({
        create: { width: 800, height: 600, channels: 3, background: '#e4412f' },
      })
        .png()
        .toBuffer()
    ).toString('base64');
    const input = {
      displayName: 'Updated Name',
      bio: 'Updated bio',
      avatarColor: '#2E5BE8',
      avatarID: null,
      photoAction: 'replace',
      photo,
    };
    const save = (body: object) =>
      request(app.getHttpServer())
        .put('/api/v1/me/profile/details')
        .auth(uid, { type: 'bearer' })
        .send(body);
    const fetch = (id: string, viewer = 'photo-reader') =>
      request(app.getHttpServer())
        .get('/api/v1/people/photos/' + id)
        .auth(viewer, { type: 'bearer' });
    const saved = (await save(input).expect(200)).body;
    expect(saved).toMatchObject({
      userID: uid,
      displayName: 'Updated Name',
      bio: 'Updated bio',
      username: 'photo_owner',
      avatarID: null,
    });
    expect(saved.avatarPhotoID).toMatch(/^[a-f0-9-]{36}$/);
    const image = (await fetch(saved.avatarPhotoID).expect(200)).body;
    const bytes = Buffer.from(image.base64, 'base64');
    const meta = await sharp(bytes).metadata();
    expect(meta.width).toBe(512);
    expect(meta.height).toBe(512);
    expect(bytes.length).toBeLessThanOrEqual(262144);
    expect(meta.exif).toBeUndefined();
    const person = await request(app.getHttpServer())
      .get('/api/v1/people/' + uid)
      .auth('photo-reader', { type: 'bearer' })
      .expect(200);
    expect(person.body.person.avatarPhotoID).toBe(saved.avatarPhotoID);
    await save({ ...input, displayName: 'Bad', photo: 'invalid!' }).expect(400);
    const unchanged = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth(uid, { type: 'bearer' })
      .expect(200);
    expect(unchanged.body.profile.displayName).toBe('Updated Name');
    await save({
      ...input,
      photo: undefined,
      photoAction: 'keep',
      bio: 'Second bio',
    }).expect(200);
    await fetch(saved.avatarPhotoID).expect(200);
    await database.query(
      'INSERT INTO user_blocks(blocker_uid,blocked_uid) VALUES($1,$2)',
      [uid, 'photo-reader'],
    );
    await fetch(saved.avatarPhotoID).expect(404);
    await fetch(saved.avatarPhotoID, uid).expect(200);
    await database.query('DELETE FROM user_blocks WHERE blocker_uid=$1', [uid]);
    const avatar = (
      await save({
        ...input,
        photo: undefined,
        photoAction: 'remove',
        avatarID: 'robot',
      }).expect(200)
    ).body;
    expect(avatar.avatarPhotoID).toBeNull();
    expect(avatar.avatarID).toBe('robot');
    await fetch(saved.avatarPhotoID).expect(404);
    const replaced = (await save(input).expect(200)).body;
    const legacy = await putProfile(uid).expect(200);
    expect(legacy.body.avatarPhotoID).toBe(replaced.avatarPhotoID);
    await request(app.getHttpServer())
      .put('/api/v1/me/profile')
      .auth(uid, { type: 'bearer' })
      .send({
        username: 'photo_owner',
        displayName: 'Legacy',
        bio: '',
        avatarColor: '#F4A814',
        avatarID: 'robot',
      })
      .expect(200);
    await fetch(replaced.avatarPhotoID).expect(404);
    const final = (await save(input).expect(200)).body;
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth(uid, { type: 'bearer' })
      .expect(200);
    await fetch(final.avatarPhotoID).expect(404);
    expect(
      (
        await database.query(
          'SELECT 1 FROM profile_photos WHERE firebase_uid=$1',
          [uid],
        )
      ).rowCount,
    ).toBe(0);
    await database.query('DELETE FROM profiles WHERE firebase_uid=$1', [
      'photo-reader',
    ]);
  });

  it('atomically reserves a username across simultaneous users', async () => {
    const results = await Promise.all([
      putProfile('race-a', 'same.name'),
      putProfile('race-b', 'SAME.NAME'),
    ]);
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      200, 409,
    ]);
    expect(results.find((r) => r.status === 409)?.body.code).toBe(
      'USERNAME_TAKEN',
    );
    const availability = await request(app.getHttpServer())
      .get('/api/v1/me/username-availability?username=same.name')
      .auth('third', { type: 'bearer' })
      .expect(200);
    expect(availability.body.available).toBe(false);
  });
  it('persists and resumes progress, rejects stale writes, and enforces real follow availability', async () => {
    await putProfile('first-lorekeeper').expect(200);
    let suggestions = await request(app.getHttpServer())
      .get('/api/v1/me/onboarding/suggestions')
      .auth('first-lorekeeper', { type: 'bearer' })
      .expect(200);
    expect(suggestions.body).toEqual({
      users: [],
      minimumFollows: 0,
      followingOptional: true,
    });
    await putProgress('first-lorekeeper', progress(0, true)).expect(200);
    await putProfile('new-lorekeeper').expect(200);
    const saved = await putProgress('new-lorekeeper', progress()).expect(200);
    expect(saved.body.version).toBe(1);
    const restored = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('new-lorekeeper', { type: 'bearer' })
      .expect(200);
    expect(restored.body.onboarding).toEqual(saved.body);
    await putProgress('new-lorekeeper', progress(0)).expect(409);
    await putProgress(
      'new-lorekeeper',
      progress(1, true, ['mock-user']),
    ).expect(409);
    await putProgress(
      'new-lorekeeper',
      progress(1, true, ['new-lorekeeper']),
    ).expect(409);
    const completed = await putProgress(
      'new-lorekeeper',
      progress(1, true, ['first-lorekeeper']),
    ).expect(200);
    expect(completed.body).toMatchObject({
      completed: true,
      version: 2,
      followedUserIDs: ['first-lorekeeper'],
    });
    suggestions = await request(app.getHttpServer())
      .get('/api/v1/me/onboarding/suggestions')
      .auth('new-lorekeeper', { type: 'bearer' })
      .expect(200);
    expect(suggestions.body.minimumFollows).toBe(1);
    expect(
      suggestions.body.users.map((u: { userID: string }) => u.userID),
    ).toEqual(['first-lorekeeper']);
    await putProgress('new-lorekeeper', progress(2, false)).expect(409);
    await request(app.getHttpServer())
      .put('/api/v1/me/onboarding')
      .auth('owner', { type: 'bearer' })
      .send({ ...progress(), universeIDs: ['fake'] })
      .expect(409);
  });
  it('serves the seeded public catalog with PT/EN content and real item totals', async () => {
    const pt = await request(app.getHttpServer())
      .get('/api/v1/catalog')
      .expect(200);
    const en = await request(app.getHttpServer())
      .get('/api/v1/catalog')
      .set('Accept-Language', 'en-US')
      .expect(200);
    expect(pt.headers.vary).toBe('Accept-Language');
    expect(pt.body.version).toBe(1);
    expect(pt.body.locale).toBe('pt-BR');
    expect(en.body.locale).toBe('en');
    expect(pt.body.universes.map((u: { id: string }) => u.id)).toEqual([
      'marvel',
      'dc',
    ]);
    expect(pt.body.items).toHaveLength(139);
    expect(pt.body.comingSoon.map((u: { name: string }) => u.name)).toEqual([]);
    expect(
      pt.body.items.find((i: { id: string }) => i.id === 'm-civil').title,
    ).toBe('Guerra Civil');
    expect(
      en.body.items.find((i: { id: string }) => i.id === 'm-civil').title,
    ).toBe('Civil War');
    for (const u of pt.body.universes) {
      expect(u.total).toBe(
        pt.body.items.filter((i: { uni: string }) => i.uni === u.id).length,
      );
      expect(u.base).toBe(0);
      expect(u.live).toBe(0);
    }
    expect(pt.body.items.every((i: { avg: number }) => i.avg === 0)).toBe(true);
  });

  it('accepts new database catalog IDs and handles missing translations and publication changes', async () => {
    const uid = 'catalog-test-user';
    await putProfile(uid).expect(200);
    await database.query(`INSERT INTO catalog_universes(id,color,dark_color,ink_color,track) VALUES('test-universe','#E4412F','#C9362A','#FFFDF8','track');
      INSERT INTO catalog_universe_translations(universe_id,locale,name) VALUES('test-universe','pt-BR','Novo universo');
      INSERT INTO catalog_items(id,universe_id,type) VALUES('test-item','test-universe','Livro');
      INSERT INTO catalog_item_translations(item_id,locale,title,year) VALUES('test-item','pt-BR','Novo livro','2026');`);
    try {
      const snapshot = await request(app.getHttpServer())
        .get('/api/v1/catalog')
        .set('Accept-Language', 'en')
        .expect(200);
      expect(
        snapshot.body.items.find((i: { id: string }) => i.id === 'test-item')
          .title,
      ).toBe('Novo livro');
      expect(
        snapshot.body.universes.find(
          (u: { id: string }) => u.id === 'test-universe',
        ),
      ).toMatchObject({ name: 'Novo universo', total: 1, members: 0 });
      const value = {
        ...progress(),
        universeIDs: ['test-universe'],
        seenItemIDs: ['test-item'],
      };
      await putProgress(uid, value).expect(200);
      for (const overrides of [
        { universeIDs: ['league-of-legends'] },
        { universeIDs: ['missing'] },
        { seenItemIDs: ['c-wanda'] },
        { seenItemIDs: ['missing'] },
      ]) {
        const rejected = await putProgress(uid, {
          ...value,
          version: 1,
          ...overrides,
        }).expect(409);
        expect(rejected.body.code).toBe('CATALOG_CHANGED');
      }
      await database.query(
        "UPDATE catalog_items SET status='archived' WHERE id='test-item'",
      );
      const retired = await request(app.getHttpServer())
        .get('/api/v1/catalog')
        .expect(200);
      expect(
        retired.body.items.some((i: { id: string }) => i.id === 'test-item'),
      ).toBe(false);
      expect(
        retired.body.universes.find(
          (u: { id: string }) => u.id === 'test-universe',
        ).total,
      ).toBe(0);
      expect(
        (await putProgress(uid, { ...value, version: 1 }).expect(409)).body
          .code,
      ).toBe('CATALOG_CHANGED');
      const stored = await database.query(
        'SELECT version,seen_item_ids FROM onboarding WHERE firebase_uid=$1',
        [uid],
      );
      expect(stored.rows[0]).toEqual({
        version: 1,
        seen_item_ids: ['test-item'],
      });
      await database.query(
        "UPDATE catalog_universes SET status='archived' WHERE id='test-universe'",
      );
      const archived = await request(app.getHttpServer())
        .get('/api/v1/catalog')
        .expect(200);
      expect(
        archived.body.universes.some(
          (u: { id: string }) => u.id === 'test-universe',
        ),
      ).toBe(false);
    } finally {
      await database.query("DELETE FROM catalog_items WHERE id='test-item'");
      await database.query(
        "DELETE FROM catalog_universes WHERE id='test-universe'",
      );
      await database.query('DELETE FROM profiles WHERE firebase_uid=$1', [uid]);
    }
  });

  it('preserves legacy suggestions while allowing fewer voluntary follows', async () => {
    await putProfile('third-person').expect(200);
    const two = await request(app.getHttpServer())
      .get('/api/v1/me/onboarding/suggestions')
      .auth('third-person', { type: 'bearer' })
      .expect(200);
    expect(two.body.minimumFollows).toBe(2);
    await putProgress(
      'third-person',
      progress(0, true, ['first-lorekeeper', 'new-lorekeeper']),
    ).expect(200);
    await putProfile('fourth-person').expect(200);
    const three = await request(app.getHttpServer())
      .get('/api/v1/me/onboarding/suggestions')
      .auth('fourth-person', { type: 'bearer' })
      .expect(200);
    expect(three.body.minimumFollows).toBe(3);
    await putProgress(
      'fourth-person',
      progress(0, true, ['first-lorekeeper', 'new-lorekeeper']),
    ).expect(200);
    expect(three.body.followingOptional).toBe(true);
  });

  it('completes without following anyone even when suggestions exist and resumes completed', async () => {
    const uid = 'skip-following';
    try {
      await putProfile(uid).expect(200);
      const suggestions = await request(app.getHttpServer())
        .get('/api/v1/me/onboarding/suggestions')
        .auth(uid, { type: 'bearer' })
        .expect(200);
      expect(suggestions.body.users.length).toBeGreaterThan(0);
      expect(suggestions.body.followingOptional).toBe(true);
      const saved = await putProgress(uid, progress(0, true)).expect(200);
      expect(saved.body.completed).toBe(true);
      expect(saved.body.followedUserIDs).toEqual([]);
      expect(
        (
          await database.query(
            'SELECT count(*)::int AS count FROM follows WHERE follower_uid=$1',
            [uid],
          )
        ).rows[0].count,
      ).toBe(0);
      const restored = await request(app.getHttpServer())
        .get('/api/v1/me')
        .auth(uid, { type: 'bearer' })
        .expect(200);
      expect(restored.body.onboarding).toEqual(saved.body);
    } finally {
      await database.query('DELETE FROM profiles WHERE firebase_uid=$1', [uid]);
    }
  });

  it('keeps already selected eligible people visible when suggestions exceed the page limit', async () => {
    const uid = 'suggestion-owner';
    const people = Array.from(
      { length: 24 },
      (_, i) => 'suggestion-person-' + i,
    );
    const ids = [uid, ...people];
    try {
      await database.query(
        `INSERT INTO profiles(firebase_uid,username,display_name,avatar_color)
        SELECT id,replace(id,'-','_'),'Person','#F4A814' FROM unnest($1::text[]) AS id`,
        [ids],
      );
      await database.query(
        `INSERT INTO onboarding(firebase_uid,completed)
        SELECT id,true FROM unnest($1::text[]) AS id`,
        [people],
      );
      const selected = people.at(-1)!;
      await database.query(
        'INSERT INTO onboarding(firebase_uid,followed_user_ids) VALUES($1,$2)',
        [uid, [selected]],
      );
      const result = await request(app.getHttpServer())
        .get('/api/v1/me/onboarding/suggestions')
        .auth(uid, { type: 'bearer' })
        .expect(200);
      expect(result.body.users).toHaveLength(20);
      expect(result.body.minimumFollows).toBe(3);
      expect(result.body.users[0].userID).toBe(selected);
      expect(
        result.body.users.some((p: { userID: string }) => p.userID === uid),
      ).toBe(false);
      await database.query(
        'UPDATE profiles SET deletion_requested_at=now() WHERE firebase_uid=$1',
        [selected],
      );
      const refreshed = await request(app.getHttpServer())
        .get('/api/v1/me/onboarding/suggestions')
        .auth(uid, { type: 'bearer' })
        .expect(200);
      expect(
        refreshed.body.users.some(
          (p: { userID: string }) => p.userID === selected,
        ),
      ).toBe(false);
    } finally {
      await database.query(
        'DELETE FROM profiles WHERE firebase_uid=ANY($1::text[])',
        [ids],
      );
    }
  });

  it('does not complete onboarding when the save fails and serializes concurrent progress writes', async () => {
    await putProfile('draft-user').expect(200);
    const results = await Promise.all([
      putProgress('draft-user', progress()),
      putProgress('draft-user', progress()),
    ]);
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      200, 409,
    ]);
    const restored = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('draft-user', { type: 'bearer' })
      .expect(200);
    expect(restored.body.onboarding.completed).toBe(false);
  });
  it('does not recreate a deleted profile from a write authenticated before deletion', async () => {
    await putProfile('closing-user').expect(200);
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('closing-user', { type: 'bearer' })
      .expect(200);
    // The guard may have accepted a token before deletion; the delayed mutation must still be rejected.
    await expect(
      app
        .get(AccountsService)
        .saveProfile('closing-user', input('closing_user')),
    ).rejects.toMatchObject({ response: { code: 'ACCOUNT_DELETING' } });
  });

  it('serializes concurrent profile updates and deletion without leaving orphan data', async () => {
    await putProfile('delete-race').expect(200);
    const [save, deletion] = await Promise.allSettled([
      app.get(AccountsService).saveProfile('delete-race', input('delete_race')),
      app
        .get(AccountLifecycleService)
        .deleteAccount('delete-race', Math.floor(Date.now() / 1000)),
    ]);
    expect(deletion.status).toBe('fulfilled');
    if (save.status === 'rejected')
      expect(save.reason).toMatchObject({
        response: { code: 'ACCOUNT_DELETING' },
      });
    expect(
      (
        await database.query('SELECT 1 FROM profiles WHERE firebase_uid=$1', [
          'delete-race',
        ])
      ).rowCount,
    ).toBe(0);
    await putProfile('delete-race').expect(403);
  });

  it('durably retries deletion even when the user has no profile yet', async () => {
    verifier.deleteUser.mockRejectedValueOnce(
      new Error('Firebase unavailable'),
    );
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('profileless-user', { type: 'bearer' })
      .expect(503);
    await putProfile('profileless-user').expect(403);
    await app.get(AccountLifecycleService).reconcileDeletions();
    const pending = await database.query(
      'SELECT completed_at FROM account_deletions WHERE firebase_uid=$1',
      ['profileless-user'],
    );
    expect(pending.rows[0].completed_at).toBeInstanceOf(Date);
    await putProfile('profileless-user').expect(403);
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('profileless-user', { type: 'bearer' })
      .expect(403);
  });

  it('requires recent authentication and reconciles interrupted account deletion', async () => {
    await putProfile('old-login').expect(200);
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('old-login', { type: 'bearer' })
      .expect(403);
    await putProfile('delete-user').expect(200);
    verifier.deleteUser.mockRejectedValueOnce(
      new Error('temporarily unavailable'),
    );
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('delete-user', { type: 'bearer' })
      .expect(503);
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('delete-user', { type: 'bearer' })
      .expect(403);
    await app.get(AccountLifecycleService).reconcileDeletions();
    const result = await database.query(
      'SELECT 1 FROM profiles WHERE firebase_uid=$1',
      ['delete-user'],
    );
    expect(result.rowCount).toBe(0);
    expect(verifier.deleteUser).toHaveBeenCalledWith('delete-user');
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('first-lorekeeper', { type: 'bearer' })
      .expect(200);
    expect(
      (
        await database.query(
          'SELECT 1 FROM follows WHERE follower_uid=$1 OR followed_uid=$1',
          ['first-lorekeeper'],
        )
      ).rowCount,
    ).toBe(0);
    const surviving = await request(app.getHttpServer())
      .get('/api/v1/me')
      .auth('new-lorekeeper', { type: 'bearer' })
      .expect(200);
    expect(surviving.body.onboarding.followedUserIDs).toEqual([]);
    expect(surviving.body.onboarding.version).toBe(3);
  });
  it('processes newer pending deletions even when the first batch keeps failing', async () => {
    const blocked = Array.from(
      { length: 25 },
      (_, index) => `blocked-delete-${index}`,
    );
    const healthy = 'healthy-delete';
    await database.query(
      `INSERT INTO account_deletions(firebase_uid,requested_at) SELECT unnest($1::text[]),now()-interval '1 day'`,
      [blocked],
    );
    await database.query(
      'INSERT INTO account_deletions(firebase_uid) VALUES($1)',
      [healthy],
    );
    verifier.deleteUser.mockImplementation(async (uid: string) => {
      if (blocked.includes(uid)) throw new Error('temporary identity failure');
    });
    try {
      await app.get(AccountLifecycleService).reconcileDeletions();
      await app.get(AccountLifecycleService).reconcileDeletions();
      const result = await database.query(
        'SELECT completed_at FROM account_deletions WHERE firebase_uid=$1',
        [healthy],
      );
      expect(result.rows[0].completed_at).toBeInstanceOf(Date);
    } finally {
      verifier.deleteUser.mockImplementation(async (_uid: string) => {});
      await database.query(
        'DELETE FROM account_deletions WHERE firebase_uid=ANY($1::text[])',
        [[...blocked, healthy]],
      );
    }
  });

  it('allows concurrent onboarding writes for people who follow each other', async () => {
    const uids = [
      'concurrent-a',
      'concurrent-b',
      'concurrent-c',
      'concurrent-d',
    ];
    for (const uid of uids) await putProfile(uid).expect(200);
    await database.query(
      'INSERT INTO onboarding(firebase_uid,completed) SELECT unnest($1::text[]),true',
      [uids],
    );
    // Completed accounts retain their canonical relationships when an older
    // client saves onboarding again. Seed those relationships before the race.
    for (const uid of uids.slice(0, 2)) {
      await database.query(
        'INSERT INTO follows(follower_uid,followed_uid) SELECT $1,unnest($2::text[])',
        [uid, uids.filter((id) => id !== uid)],
      );
    }
    // A test-only trigger holds both requests after they lock their own profile.
    // This makes the mutual-follow lock cycle deterministic instead of relying on timing.
    const gate = await admin.connect();
    const gateKey = randomInt(1, 2_147_483_647);
    await gate.query('SELECT pg_advisory_lock($1, 2)', [gateKey]);
    await database.query(`CREATE FUNCTION hold_onboarding_writes() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
      IF NEW.firebase_uid IN ('concurrent-a','concurrent-b') THEN
        PERFORM pg_advisory_xact_lock_shared(${gateKey}, 2);
      END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER hold_onboarding_writes BEFORE INSERT ON onboarding FOR EACH ROW EXECUTE FUNCTION hold_onboarding_writes()`);
    const requests = Promise.all([
      putProgress(uids[0], progress(0, true, [uids[1], uids[2], uids[3]])),
      putProgress(uids[1], progress(0, true, [uids[0], uids[2], uids[3]])),
    ]);
    let waiting = 0;
    try {
      for (let attempt = 0; attempt < 200; attempt++) {
        const result = await admin.query<{ count: string }>(
          "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND classid=$1 AND objid=2 AND NOT granted",
          [gateKey],
        );
        waiting = Number(result.rows[0].count);
        if (waiting === 2) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
    } finally {
      await gate.query('SELECT pg_advisory_unlock($1, 2)', [gateKey]);
      gate.release();
    }
    const results = await requests;
    await database.query(
      'DROP TRIGGER hold_onboarding_writes ON onboarding; DROP FUNCTION hold_onboarding_writes()',
    );
    try {
      expect(waiting).toBe(2);
      expect(results.map((result) => result.status)).toEqual([200, 200]);
      for (const uid of uids.slice(0, 2)) {
        const restored = await request(app.getHttpServer())
          .get('/api/v1/me')
          .auth(uid, { type: 'bearer' })
          .expect(200);
        expect(restored.body.onboarding.version).toBe(1);
        expect(restored.body.onboarding.followedUserIDs).toHaveLength(3);
      }
    } finally {
      await database.query(
        'DELETE FROM profiles WHERE firebase_uid=ANY($1::text[])',
        [uids],
      );
    }
  });
  it.each([false, true])(
    'restores only eligible follows while identity deletion is pending (completed=%s)',
    async (completed) => {
      const suffix = completed ? 'done' : 'draft';
      const viewer = `pending-viewer-${suffix}`;
      const departing = `pending-target-${suffix}`;
      const remaining = [1, 2, 3].map(
        (index) => `pending-peer${index}-${suffix}`,
      );
      const uids = [viewer, departing, ...remaining];
      try {
        for (const uid of uids) await putProfile(uid).expect(200);
        await database.query(
          'INSERT INTO onboarding(firebase_uid,completed) SELECT unnest($1::text[]),true',
          [[departing, ...remaining]],
        );
        const saved = await putProgress(
          viewer,
          progress(0, completed, [
            remaining[0],
            departing,
            ...remaining.slice(1),
          ]),
        ).expect(200);
        verifier.deleteUser.mockRejectedValueOnce(
          new Error('identity provider unavailable'),
        );
        await request(app.getHttpServer())
          .delete('/api/v1/me')
          .auth(departing, { type: 'bearer' })
          .expect(503);
        const restored = await request(app.getHttpServer())
          .get('/api/v1/me')
          .auth(viewer, { type: 'bearer' })
          .expect(200);
        expect(restored.body.onboarding).toMatchObject({
          followedUserIDs: remaining,
          completed,
          version: saved.body.version,
        });
        // Reading the recoverable draft is side-effect free; the next versioned save
        // reconciles both the onboarding array and the follows relation.
        const persisted = await database.query<{ followed_user_ids: string[] }>(
          'SELECT followed_user_ids FROM onboarding WHERE firebase_uid=$1',
          [viewer],
        );
        expect(persisted.rows[0].followed_user_ids).toContain(departing);
        const finished = await putProgress(viewer, {
          ...restored.body.onboarding,
          completed: true,
          step: 3,
        }).expect(200);
        expect(finished.body.completed).toBe(true);
        expect(finished.body.version).toBe(saved.body.version + 1);
        const follows = await database.query<{ followed_uid: string }>(
          'SELECT followed_uid FROM follows WHERE follower_uid=$1 ORDER BY followed_uid',
          [viewer],
        );
        expect(follows.rows.map((row) => row.followed_uid)).toEqual(remaining);
      } finally {
        await database.query(
          'DELETE FROM profiles WHERE firebase_uid=ANY($1::text[])',
          [uids],
        );
        await database.query(
          'DELETE FROM account_deletions WHERE firebase_uid=ANY($1::text[])',
          [uids],
        );
      }
    },
  );
});
