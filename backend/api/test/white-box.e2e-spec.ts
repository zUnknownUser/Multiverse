import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import type { INestApplication } from '@nestjs/common';
import pg from 'pg';
import request from 'supertest';
import sharp from 'sharp';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FirebaseTokenVerifier } from '../src/auth/firebase-token-verifier.js';
import { configureApp } from '../src/configure-app.js';
import { AccountLifecycleService } from '../src/accounts/account-lifecycle.service.js';

describe('White-box security assertions — 2026-10-22', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const schema = 'whitebox_' + randomUUID().replaceAll('-', '');
  const input = {
    itemId: 'm-civil',
    loggedAt: '2026-09-30T12:00:00.000Z',
    rating: 4,
    liked: false,
    rewatch: false,
    spoiler: false,
    text: 'Local audit fixture',
  };
  const save = (id: string, body = input) =>
    request(app.getHttpServer())
      .put('/api/v1/me/diary/' + id)
      .auth('audit_owner', { type: 'bearer' })
      .send(body);
  const photoInput = (photo: string) => ({
    displayName: 'Audit',
    bio: '',
    avatarColor: '#F4A814',
    photoAction: 'replace',
    photo,
  });
  const savePhoto = (photo: string, uid = 'audit_owner') =>
    request(app.getHttpServer())
      .put('/api/v1/me/profile/details')
      .auth(uid, { type: 'bearer' })
      .send(photoInput(photo));
  const tinyPhoto = () =>
    sharp({
      create: { width: 8, height: 8, channels: 3, background: '#F4A814' },
    })
      .png()
      .toBuffer();

  beforeAll(async () => {
    // Uses the same explicitly selected test database as the regular HTTP suite.
    const url = new URL(process.env.TEST_DATABASE_URL!);
    admin = new pg.Pool({ connectionString: url.toString() });
    await admin.query(`CREATE SCHEMA "${schema}"`);
    url.searchParams.set('options', `-c search_path=${schema}`);
    db = new DatabaseService(
      new ConfigService({ DATABASE_URL: url.toString() }),
    );
    const migrations = new URL('../migrations/', import.meta.url);
    for (const name of (await readdir(migrations))
      .filter((name) => name.endsWith('.sql'))
      .sort())
      await db.query(await readFile(new URL(name, migrations), 'utf8'));
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
    await db.query(
      "INSERT INTO profiles(firebase_uid,username,display_name,avatar_color,public_diary) VALUES('audit_owner','audit_owner','Audit','#F4A814',true),('audit_other','audit_other','Other','#F4A814',true)",
    );
    await db.query(
      "INSERT INTO onboarding(firebase_uid,completed,step) VALUES('audit_owner',true,3),('audit_other',true,3)",
    );
  });
  afterEach(async () => {
    vi.restoreAllMocks();
    await db.query('DELETE FROM profiles');
    await db.query('DELETE FROM account_deletions');
  });
  afterAll(async () => {
    if (app) await app.close();
    else await db?.onModuleDestroy();
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await admin.end();
    }
  });

  it('WB-01: migration preserves recent consumption without retaining expired reviews', async () => {
    const recent = randomUUID(),
      expired = randomUUID();
    await save(recent).expect(200);
    await save(expired).expect(200);
    await db.query(
      "UPDATE reviews SET created_at=now()-interval '61 minutes' WHERE entry_id=$1",
      [expired],
    );
    await db.transaction(async (client) => {
      await client.query('DROP TABLE review_publications,profile_photo_limits');
      await client.query(
        await readFile(
          new URL(
            '../migrations/030_review_and_photo_budgets.sql',
            import.meta.url,
          ),
          'utf8',
        ),
      );
      const receipts = await client.query(
        'SELECT id FROM review_publications ORDER BY id',
      );
      const expected = await client.query(
        'SELECT id FROM reviews WHERE entry_id=$1',
        [recent],
      );
      expect(receipts.rows).toEqual(expected.rows);
    });
  });

  it('CONTROL: rejects unauthenticated reads and another account deleting a diary entry', async () => {
    await request(app.getHttpServer()).get('/api/v1/me/activity').expect(401);
    const id = randomUUID();
    await save(id).expect(200);
    await request(app.getHttpServer())
      .delete('/api/v1/me/diary/' + id)
      .auth('audit_other', { type: 'bearer' })
      .expect(404);
    const result = await db.query('SELECT 1 FROM diary_entries WHERE id=$1', [
      id,
    ]);
    expect(result.rowCount).toBe(1);
  });

  it('WB-01: deleting a review must not refund the hourly publication budget', async () => {
    const ids = Array.from({ length: 20 }, () => randomUUID());
    for (const id of ids) await save(id).expect(200);
    // Positive control establishes that the configured budget is exhausted.
    await save(randomUUID()).expect(429);
    await request(app.getHttpServer())
      .delete('/api/v1/me/diary/' + ids[0])
      .auth('audit_owner', { type: 'bearer' })
      .expect(200);
    const result = await save(randomUUID());
    expect(result.status, 'WB-01: expected 429 after deletion').toBe(429);
  });

  it('WB-02: a missing profile must be rejected before image re-encoding', async () => {
    const photo = await sharp({
      create: { width: 8, height: 8, channels: 3, background: '#F4A814' },
    })
      .png()
      .toBuffer();
    // Call-through spy: real sharp processes a tiny fixture, without load testing.
    const encode = vi.spyOn(sharp.prototype, 'toBuffer');
    await request(app.getHttpServer())
      .put('/api/v1/me/profile/details')
      .auth('audit_missing', { type: 'bearer' })
      .send({
        displayName: 'Audit',
        bio: '',
        avatarColor: '#F4A814',
        photoAction: 'replace',
        photo: photo.toString('base64'),
      })
      .expect(404);
    expect(
      encode,
      'WB-02: unauthorized profile triggered sharp',
    ).not.toHaveBeenCalled();
  });

  it('WB-01: retries do not consume twice; clearing text, privacy and concurrent writes cannot reset the budget', async () => {
    const ids = Array.from({ length: 19 }, () => randomUUID());
    for (const id of ids) await save(id).expect(200);
    await save(ids[0]).expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/privacy')
      .auth('audit_owner', { type: 'bearer' })
      .send({ publicDiary: false })
      .expect(200);
    const results = await Promise.all([save(randomUUID()), save(randomUUID())]);
    expect(results.map((r) => r.status).sort((a, b) => a - b)).toEqual([
      200, 429,
    ]);
    await save(ids[0], { ...input, text: '', rating: 0 }).expect(200);
    await save(ids[0]).expect(429);
    await save(ids[1]).expect(200);
    expect((await db.query('SELECT 1 FROM review_publications')).rowCount).toBe(
      20,
    );
    await db.query(
      "UPDATE review_publications SET created_at=now()-interval '61 minutes'",
    );
    await save(ids[0]).expect(200);
    expect((await db.query('SELECT 1 FROM review_publications')).rowCount).toBe(
      1,
    );
  });

  it('WB-02: invalid processing attempts exhaust the durable quota; expiry and removal still work', async () => {
    const invalid = Buffer.from('not an image').toString('base64');
    for (let i = 0; i < 20; i++) await savePhoto(invalid).expect(400);
    expect(
      (await db.query('SELECT attempts FROM profile_photo_limits')).rows[0]
        .attempts,
    ).toBe(20);
    const photo = (await tinyPhoto()).toString('base64');
    const metadata = vi.spyOn(sharp.prototype, 'metadata');
    await savePhoto(photo).expect(429);
    expect(metadata).not.toHaveBeenCalled();
    await request(app.getHttpServer())
      .put('/api/v1/me/profile/details')
      .auth('audit_owner', { type: 'bearer' })
      .send({ ...photoInput(''), photo: undefined, photoAction: 'remove' })
      .expect(200);
    await db.query(
      "UPDATE profile_photo_limits SET window_start=now()-interval '61 minutes'",
    );
    await savePhoto(photo).expect(200);
    expect(
      (await db.query('SELECT attempts FROM profile_photo_limits')).rows[0]
        .attempts,
    ).toBe(1);
  });

  it('WB-02: bounds concurrent processing and rechecks deletion before saving', async () => {
    const bytes = await tinyPhoto();
    const photo = bytes.toString('base64');
    let release!: (value: Buffer) => void;
    const blocked = new Promise<Buffer>((resolve) => {
      release = resolve;
    });
    const encode = vi
      .spyOn(sharp.prototype, 'toBuffer')
      .mockReturnValueOnce(blocked as never)
      .mockReturnValueOnce(blocked as never);
    const first = savePhoto(photo).then((r) => r.status);
    const second = savePhoto(photo, 'audit_other').then((r) => r.status);
    try {
      await vi.waitFor(() => expect(encode).toHaveBeenCalledTimes(2));
      await savePhoto(photo).expect(429);
      await savePhoto(photo, 'audit_missing').expect(429);
      await app
        .get(AccountLifecycleService)
        .deleteAccount('audit_owner', Math.floor(Date.now() / 1000));
    } finally {
      release(bytes);
    }
    expect(await first).toBe(403);
    expect(await second).toBe(200);
    expect(
      (
        await db.query(
          "SELECT 1 FROM profile_photos WHERE firebase_uid='audit_owner'",
        )
      ).rowCount,
    ).toBe(0);
    expect(
      (
        await db.query(
          "SELECT 1 FROM profile_photo_limits WHERE firebase_uid='audit_owner'",
        )
      ).rowCount,
    ).toBe(0);
    await savePhoto(photo, 'audit_other').expect(200);
  });
});
