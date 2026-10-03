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
import { moderate, moderationQueue } from '../src/social/moderation.js';
const databaseURL = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseURL)('Private messages with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const schema = 'messages_test_' + randomUUID().replaceAll('-', '');
  const get = (path = '', uid = 'alice') =>
    request(app.getHttpServer())
      .get('/api/v1/me/messages' + path)
      .auth(uid, { type: 'bearer' });
  const put = (path: string, body: object, uid = 'alice') =>
    request(app.getHttpServer())
      .put('/api/v1/' + path)
      .auth(uid, { type: 'bearer' })
      .send(body);
  const body = { kind: 'text', text: 'Olá, sem spoilers!', spoiler: false };
  const send = (
    peer = 'bob',
    uid = 'alice',
    id = randomUUID(),
    input: object = body,
  ) => put(`me/messages/${peer}/messages/${id}`, input, uid);
  const member = async (uid: string) => {
    await db.query(
      "INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES($1,$1,$1,'#F4A814')",
      [uid],
    );
    await db.query(
      "INSERT INTO onboarding(firebase_uid,completed,universe_ids,step) VALUES($1,true,'{marvel}',3)",
      [uid],
    );
  };
  const accept = () =>
    put('me/messages/alice/request', { accepted: true }, 'bob').expect(200);
  const alerts = () =>
    request(app.getHttpServer())
      .get('/api/v1/me/notifications')
      .auth('bob', { type: 'bearer' });
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
    await app.listen(0, '127.0.0.1');
  });
  beforeEach(async () => {
    for (const uid of ['alice', 'bob', 'eve']) await member(uid);
  });
  afterEach(async () => {
    await db.query('DELETE FROM profiles');
    await db.query('DELETE FROM account_deletions');
    await db.query('DELETE FROM moderation_decisions');
  });
  afterAll(async () => {
    await app?.close();
    if (admin) {
      await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
      await admin.end();
    }
  });
  it('requires recipient acceptance and denies outsiders access', async () => {
    expect((await get('/bob').expect(200)).body.state).toBe('new');
    await send().expect(200);
    const inbox = (await get('', 'bob').expect(200)).body;
    expect(inbox.unreadCount).toBe(1);
    expect(inbox.conversations[0]).toMatchObject({
      state: 'pending',
      incomingRequest: true,
      user: { id: 'alice' },
    });
    expect((await get('/alice', 'eve').expect(200)).body.messages).toEqual([]);
    await send().expect(409);
    await send('alice', 'bob').expect(409);
    await put('me/messages/bob/request', { accepted: true }).expect(404);
    await accept();
    await accept();
    await send('alice', 'bob').expect(200);
    expect((await get('/bob').expect(200)).body.messages).toHaveLength(2);
  });
  it('makes concurrent retries and opposite-direction sends safe', async () => {
    const id = randomUUID();
    await Promise.all([
      send('bob', 'alice', id).expect(200),
      send('bob', 'alice', id).expect(200),
    ]);
    await send('bob', 'alice', id, { ...body, text: 'Different' }).expect(409);
    expect((await alerts().expect(200)).body.notifications).toHaveLength(1);
    await accept();
    await Promise.all([send().expect(200), send('alice', 'bob').expect(200)]);
    expect(
      (await get('/bob').expect(200)).body.messages.map(
        (m: { sequence: string }) => m.sequence,
      ),
    ).toEqual(['1', '2', '3']);
  });
  it('accepts automatically only when recipient follows sender', async () => {
    await put('me/follows/alice', { following: true }, 'bob').expect(200);
    await send().expect(200);
    expect((await get('/bob').expect(200)).body.state).toBe('accepted');
    await put('me/follows/eve', { following: true }).expect(200);
    await send('eve').expect(200);
    expect((await get('/eve').expect(200)).body.state).toBe('pending');
  });
  it('declines idempotently without letting the sender reopen', async () => {
    await send().expect(200);
    for (let i = 0; i < 2; i++)
      await put('me/messages/alice/request', { accepted: false }, 'bob').expect(
        200,
      );
    expect((await get().expect(200)).body.conversations).toEqual([]);
    await get('/bob').expect(404);
    await send().expect(404);
    await put('me/messages/alice/request', { accepted: true }, 'bob').expect(
      404,
    );
    expect((await alerts().expect(200)).body.notifications).toEqual([]);
  });
  it('paginates history and marks only the supplied sequence read', async () => {
    await send().expect(200);
    await accept();
    for (let i = 0; i < 43; i++) await send().expect(200);
    const latest = (await get('/alice', 'bob').expect(200)).body;
    expect(latest.messages).toHaveLength(40);
    expect(latest.before).toBe('5');
    const older = (await get('/alice?before=5', 'bob').expect(200)).body;
    expect(older.messages.map((m: { sequence: string }) => m.sequence)).toEqual(
      ['1', '2', '3', '4'],
    );
    expect(older.before).toBeNull();
    await put('me/messages/alice/read', { through: '44' }, 'bob').expect(200);
    await send().expect(200);
    await put('me/messages/alice/read', { through: '1' }, 'bob').expect(200);
    expect((await get('', 'bob').expect(200)).body.unreadCount).toBe(1);
    expect((await get('/bob').expect(200)).body.readThrough).toBe('44');
    await put('me/messages/alice/read', { through: '999' }, 'bob').expect(400);
  });
  it('hides both directions and alerts on block and restores on unblock', async () => {
    await send().expect(200);
    await accept();
    await put('me/blocks/alice', { blocked: true }, 'bob').expect(200);
    for (const [owner, peer] of [
      ['alice', 'bob'],
      ['bob', 'alice'],
    ]) {
      expect((await get('', owner).expect(200)).body.conversations).toEqual([]);
      await get('/' + peer, owner).expect(404);
      await send(peer, owner).expect(404);
    }
    expect((await alerts().expect(200)).body.notifications).toEqual([]);
    await put('me/blocks/alice', { blocked: false }, 'bob').expect(200);
    expect((await get('/bob').expect(200)).body.messages).toHaveLength(1);
  });
  it('shares published works and returns an unavailable card after archival', async () => {
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE status='published' LIMIT 1",
      )
    ).rows[0].id;
    await send('bob', 'alice', randomUUID(), {
      kind: 'workCard',
      text: 'Leia isso!',
      spoiler: true,
      itemID: item,
    }).expect(200);
    expect(
      (await get('/alice', 'bob').expect(200)).body.messages[0],
    ).toMatchObject({ itemID: item, spoiler: true });
    await db.query("UPDATE catalog_items SET status='archived' WHERE id=$1", [
      item,
    ]);
    try {
      expect(
        (await get('/bob').expect(200)).body.messages[0].itemID,
      ).toBeNull();
      await accept();
      await send('bob', 'alice', randomUUID(), {
        ...body,
        kind: 'workCard',
        itemID: item,
      }).expect(409);
    } finally {
      await db.query(
        "UPDATE catalog_items SET status='published' WHERE id=$1",
        [item],
      );
    }
  });
  it('restricts reports to recipients and exposes only reported messages to moderation', async () => {
    const id = randomUUID();
    await send('bob', 'alice', id).expect(200);
    await put(`me/messages/bob/messages/${id}/report`, {
      reason: 'spam',
      alsoBlock: false,
    }).expect(404);
    await put(
      `me/messages/alice/messages/${id}/report`,
      { reason: 'spam', alsoBlock: false },
      'eve',
    ).expect(404);
    await put(
      `me/messages/alice/messages/${id}/report`,
      { reason: 'spam', alsoBlock: false },
      'bob',
    ).expect(200);
    expect(
      (await get('/alice', 'bob').expect(200)).body.messages[0],
    ).toMatchObject({ kind: 'removed', text: '' });
    const queue = await db.transaction((c) => moderationQueue(c));
    expect(queue).toHaveLength(1);
    expect(queue[0].targetType).toBe('message');
    await db.transaction((c) =>
      moderate(c, {
        id: randomUUID(),
        targetType: 'message',
        targetID: id,
        action: 'hide',
        operator: 'test',
        reason: 'Spam',
      }),
    );
    expect((await get('/bob').expect(200)).body.messages[0].kind).toBe(
      'removed',
    );
    expect((await alerts().expect(200)).body.notifications).toEqual([]);
  });
  it('wakes subscribers after commit and cascades account deletion', async () => {
    const revision = (await get('/changes', 'bob').expect(200)).body.revision;
    const waiting = get('/changes?after=' + revision, 'bob')
      .timeout(5000)
      .then((r) => r);
    await send().expect(200);
    const changed = await waiting;
    expect(changed.status).toBe(200);
    expect(BigInt(changed.body.revision)).toBeGreaterThan(BigInt(revision));
    await put('me/messages/alice/read', { through: '1' }, 'bob').expect(200);
    await request(app.getHttpServer())
      .delete('/api/v1/me')
      .auth('alice', { type: 'bearer' })
      .expect(200);
    expect((await get('', 'bob').expect(200)).body.conversations).toEqual([]);
    for (const table of ['dm_threads', 'dm_messages', 'dm_reads', 'dm_reports'])
      expect((await db.query(`SELECT * FROM ${table}`)).rows).toEqual([]);
  });
  it('requires authentication and rejects malformed, oversized and self messages', async () => {
    await request(app.getHttpServer()).get('/api/v1/me/messages').expect(401);
    await send('alice').expect(404);
    await send('absent').expect(404);
    await send('bob', 'alice', randomUUID(), { ...body, text: ' ' }).expect(
      400,
    );
    await send('bob', 'alice', randomUUID(), {
      ...body,
      text: 'x'.repeat(2001),
    }).expect(400);
    await send('bob', 'alice', randomUUID(), { ...body, owner: 'eve' }).expect(
      400,
    );
    await get('?unknown=yes').expect(400);
    await get('/bob?before=-1').expect(400);
    await get('/changes?after=no').expect(400);
  });
  it('enforces durable hourly budgets without preventing acknowledged retries', async () => {
    const id = randomUUID();
    await send('bob', 'alice', id).expect(200);
    await accept();
    await db.query(
      "INSERT INTO dm_messages(id,thread_id,sender_uid,sequence,kind,text) SELECT gen_random_uuid(),id,'alice',n,'text','test' FROM dm_threads CROSS JOIN generate_series(2,120) n",
    );
    await db.query('UPDATE dm_threads SET sequence=120');
    await send().expect(429);
    await send('bob', 'alice', id).expect(200);
  });
  it('paginates inbox threads with stable cursors and limits new requests', async () => {
    for (let n = 0; n < 31; n++) {
      const peer = 'person' + n;
      await member(peer);
      await db.query(
        "INSERT INTO dm_threads(user_a,user_b,initiator,state) VALUES('alice',$1,'alice','accepted')",
        [peer],
      );
    }
    const first = (await get().expect(200)).body;
    expect(first.conversations).toHaveLength(30);
    expect(first.nextCursor).toBeTruthy();
    const second = (await get('?after=' + first.nextCursor).expect(200)).body;
    expect(second.conversations).toHaveLength(1);
    expect(second.nextCursor).toBeNull();
    expect(
      new Set(
        [...first.conversations, ...second.conversations].map((x) => x.id),
      ).size,
    ).toBe(31);
    await send('bob').expect(429);
  });
});
