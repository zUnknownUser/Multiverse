import { VoiceMediaService } from '../src/voice/voice-media.service.js';
import { VoiceService } from '../src/voice/voice.service.js';
import sharp from 'sharp';
import { moderate, moderationQueue } from '../src/social/moderation.js';
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
describe.skipIf(!databaseURL)('Live community features with PostgreSQL', () => {
  let app: INestApplication;
  let admin: pg.Pool;
  let db: DatabaseService;
  const voiceMedia = {
    enabled: true,
    configured: true,
    ticket: vi.fn(async (_room: string, identity: string) => ({
      serverURL: 'wss://test.livekit.cloud',
      token: 'test-token-' + identity,
    })),
    remove: vi.fn(async () => {}),
  };
  const schema = 'community_test_' + randomUUID().replaceAll('-', '');
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
      "INSERT INTO profiles(firebase_uid,username,display_name,avatar_color,comment_permission) VALUES($1,$1,$2,$3,'everyone')",
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
      .overrideProvider(VoiceMediaService)
      .useValue(voiceMedia)
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
    await db.query('DELETE FROM room_voice_sessions');
    voiceMedia.remove.mockClear();
    voiceMedia.enabled = true;
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

  it('creates one bilingual daily round and awards points only once across concurrent votes, side changes and comments', async () => {
    await member('owner');
    await member('alice');
    const [a, b] = await Promise.all([
      get('community/daily-duels').expect(200),
      get('community/daily-duels', 'alice')
        .set('Accept-Language', 'en')
        .expect(200),
    ]);
    const id = a.body.today.id;
    expect(id).toBe(b.body.today.id);
    expect(a.body.today.title).not.toBe(b.body.today.title);
    expect(a.body.today.votes.counts).toEqual([0, 0]);
    expect(
      (
        await get('posts?q=' + encodeURIComponent(b.body.today.title))
          .set('Accept-Language', 'en')
          .expect(200)
      ).body.posts[0].id,
    ).toBe(id);
    expect(
      (await get('me/onboarding/suggestions').expect(200)).body.users.some(
        (u: { userID: string }) => u.userID === 'multiverse-editorial',
      ),
    ).toBe(false);

    expect(a.body.progress).toEqual({ rounds: 0, monthlyPoints: 0, streak: 0 });
    expect((await db.query('SELECT * FROM daily_duels')).rowCount).toBe(1);
    await Promise.all([
      put(`posts/${id}/vote`, { choice: 0 }).expect(200),
      put(`posts/${id}/vote`, { choice: 0 }).expect(200),
    ]);
    await put(`posts/${id}/vote`, { choice: 1 }).expect(200);
    const state = (await get('community/daily-duels').expect(200)).body;
    expect(state.progress).toEqual({ rounds: 1, monthlyPoints: 10, streak: 1 });
    expect(state.today.votes.counts).toEqual([0, 1]);
    expect(
      (await get(`posts/${id}`).set('Accept-Language', 'en').expect(200)).body
        .posts[0].title,
    ).toBe(b.body.today.title);
    await put(`posts/${id}/comments/${randomUUID()}`, {
      text: 'Meu argumento sobre essa escolha.',
      spoiler: false,
    }).expect(200);
    expect(
      (await get('community/daily-duels').expect(200)).body.progress
        .monthlyPoints,
    ).toBe(10);
    const leaders = (await get('community/daily-duels/leaderboard').expect(200))
      .body;
    expect(leaders.me.points).toBe(10);
    expect(leaders.me.rank).toBe(1);
    expect(leaders.leaders).toHaveLength(1);
    const inviteID = randomUUID();
    const invitation = {
      kind: 'text',
      text: 'Escolha seu lado!\nmultiverse://duel/' + id,
      spoiler: false,
    };
    await put(`me/messages/alice/messages/${inviteID}`, invitation).expect(200);
    await put(`me/messages/alice/messages/${inviteID}`, invitation).expect(200);
    const received = (await get('me/messages/owner', 'alice').expect(200)).body;
    expect(received.messages).toHaveLength(1);
    expect(received.messages[0].text).toBe(invitation.text);
    expect(
      (await get(`community/daily-duels/${id}`, 'alice').expect(200)).body.round
        .id,
    ).toBe(id);
    await put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(200);
    const tied = (await get('community/daily-duels/leaderboard').expect(200))
      .body.leaders;
    expect(tied).toHaveLength(2);
    expect(
      tied.every(
        (p: { rank: number; points: number }) =>
          p.rank === 1 && p.points === 10,
      ),
    ).toBe(true);
  });
  it('enforces onboarding, the deadline, moderation and blocks for daily duels', async () => {
    await member('owner');
    await member('alice');
    await member('newbie', false);
    await get('community/daily-duels', 'newbie').expect(409);
    const id = (await get('community/daily-duels').expect(200)).body.today.id;
    await put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(200);
    await put('me/blocks/alice', { blocked: true }).expect(200);
    expect(
      (await get('community/daily-duels/leaderboard').expect(200)).body.leaders,
    ).toHaveLength(0);
    expect(
      (await get('community/daily-duels').expect(200)).body.today.votes.counts,
    ).toEqual([0, 0]);
    await db.query(
      "UPDATE community_posts SET closes_at=now()-interval '1 second' WHERE id=$1",
      [id],
    );
    await put(`posts/${id}/vote`, { choice: 1 }).expect(409);
    expect(
      (await get('community/daily-duels').expect(200)).body.progress.rounds,
    ).toBe(0);
    await db.query(
      "UPDATE community_posts SET moderation_status='hidden' WHERE id=$1",
      [id],
    );
    await get(`community/daily-duels/${id}`).expect(404);
    expect(
      (await get('community/daily-duels').expect(200)).body.today,
    ).toBeNull();
  });
  it('rolls into a new day, retains previous results and resets monthly points without losing lifetime rewards', async () => {
    await member('owner');
    const id = (await get('community/daily-duels').expect(200)).body.today.id;
    await put(`posts/${id}/vote`, { choice: 0 }).expect(200);
    await db.query(
      "UPDATE daily_duels SET day=((now() AT TIME ZONE 'UTC')::date-1),opens_at=(((now() AT TIME ZONE 'UTC')::date-1)::timestamp AT TIME ZONE 'UTC') WHERE post_id=$1",
      [id],
    );
    await db.query(
      "UPDATE community_posts SET closes_at=((now() AT TIME ZONE 'UTC')::date::timestamp AT TIME ZONE 'UTC') WHERE id=$1",
      [id],
    );
    await db.query(
      "UPDATE community_votes SET created_at=(SELECT opens_at+interval '1 hour' FROM daily_duels WHERE post_id=$1) WHERE post_id=$1",
      [id],
    );
    const current = (await get('community/daily-duels').expect(200)).body;
    expect(current.today.id).not.toBe(id);
    expect(current.previous.id).toBe(id);
    expect(current.progress.streak).toBe(1);
    await put(`posts/${current.today.id}/vote`, { choice: 1 }).expect(200);
    expect(
      (await get('community/daily-duels').expect(200)).body.progress.streak,
    ).toBe(2);
    await db.query(
      "UPDATE daily_duels SET day=(date_trunc('month',now() AT TIME ZONE 'UTC')::date-10),opens_at=((date_trunc('month',now() AT TIME ZONE 'UTC')::date-10)::timestamp AT TIME ZONE 'UTC') WHERE post_id=$1",
      [id],
    );
    await db.query(
      "UPDATE community_posts SET closes_at=(SELECT opens_at+interval '1 day' FROM daily_duels WHERE post_id=$1) WHERE id=$1",
      [id],
    );
    await db.query(
      "UPDATE community_votes SET created_at=(SELECT opens_at+interval '1 hour' FROM daily_duels WHERE post_id=$1) WHERE post_id=$1",
      [id],
    );
    const final = (await get('community/daily-duels').expect(200)).body;
    expect(final.progress.rounds).toBe(2);
    expect(final.progress.monthlyPoints).toBe(10);
    expect(final.progress.streak).toBe(1);
    expect(
      (await get('community/daily-duels/leaderboard').expect(200)).body.me
        .points,
    ).toBe(10);
  });
  const put = (path: string, body: object, uid = 'owner') =>
    request(app.getHttpServer())
      .put('/api/v1/' + path)
      .auth(uid, { type: 'bearer' })
      .send(body);
  const del = (path: string, uid = 'owner') =>
    request(app.getHttpServer())
      .delete('/api/v1/' + path)
      .auth(uid, { type: 'bearer' });
  const input = {
    universeID: 'marvel',
    itemID: null,
    title: 'Discussão de quadrinhos',
    text: 'Uma conversa real',
    spoiler: false,
  };
  const comment = (post: string, id: string, body: object, uid = 'alice') =>
    put(`posts/${post}/comments/${id}`, body, uid);
  it('edits with version protection and idempotence while retaining reactions', async () => {
    await member('owner');
    await member('alice');
    const id = randomUUID();
    await put('posts/' + id, input).expect(200);
    await put(
      `posts/${id}/reaction`,
      { reaction: 'POW!', liked: true },
      'alice',
    ).expect(200);
    const edit = {
      title: 'Novo título',
      text: 'Texto editado @alice',
      spoiler: true,
      imageIDs: [],
      version: 1,
      mutationID: randomUUID(),
    };
    const patch = (body: object, uid = 'owner') =>
      request(app.getHttpServer())
        .patch('/api/v1/posts/' + id)
        .auth(uid, { type: 'bearer' })
        .send(body);
    await patch(edit, 'alice').expect(404);
    await patch(edit).expect(200);
    await patch(edit).expect(200);
    await patch({ ...edit, mutationID: randomUUID() }).expect(409);
    const page = (await get('posts/' + id).expect(200)).body;
    expect(page.posts[0]).toMatchObject({
      title: edit.title,
      version: 2,
      spoiler: true,
      mentions: [{ id: 'alice', handle: '@alice' }],
      interaction: { likes: 1 },
    });
    const alerts = (await get('me/notifications', 'alice').expect(200)).body
      .notifications;
    expect(
      alerts.filter((n: { kind: string }) => n.kind === 'mention'),
    ).toHaveLength(1);
    await del('posts/' + id).expect(200);
    await patch({ ...edit, version: 2, mutationID: randomUUID() }).expect(404);
  });
  it('persists verified images, denies reuse and restricts bytes after report/block/delete', async () => {
    await member('owner');
    await member('alice');
    const id = randomUUID(),
      image = randomUUID();
    const base64 = (
      await sharp({
        create: { width: 40, height: 20, channels: 3, background: '#ff3300' },
      })
        .png()
        .toBuffer()
    ).toString('base64');
    await put(`posts/${id}/images/${image}`, { base64 }).expect(200);
    await put(`posts/${id}/images/${image}`, { base64 }).expect(200);
    await put(`posts/${id}/images/${randomUUID()}`, {
      base64: Buffer.from('<svg>bad</svg>').toString('base64'),
    }).expect(400);
    await put(
      'posts/' + randomUUID(),
      { ...input, imageIDs: [image] },
      'alice',
    ).expect(400);
    await put('posts/' + id, { ...input, imageIDs: [image] }).expect(200);
    const data = (await get(`posts/${id}/images/${image}`, 'alice').expect(200))
      .body;
    const metadata = await sharp(Buffer.from(data.base64, 'base64')).metadata();
    expect(metadata.format).toBe('jpeg');
    expect(metadata.exif).toBeUndefined();
    expect((await get('posts/' + id).expect(200)).body.posts[0].images).toEqual(
      [{ id: image, width: 40, height: 20 }],
    );
    await put(
      `posts/${id}/report`,
      { reason: 'spam', alsoBlock: false },
      'alice',
    ).expect(200);
    await get(`posts/${id}/images/${image}`, 'alice').expect(404);
    await del('posts/' + id).expect(200);
    await get(`posts/${id}/images/${image}`).expect(404);
  });
  it('threads replies only within a visible post and notifies reply authors and mentions once', async () => {
    await member('owner');
    await member('alice');
    await member('bob');
    const id = randomUUID(),
      other = randomUUID(),
      root = randomUUID(),
      reply = randomUUID();
    await put('posts/' + id, input).expect(200);
    await put('posts/' + other, input).expect(200);
    await comment(id, root, {
      text: 'Primeiro comentário',
      spoiler: false,
    }).expect(200);
    await comment(
      other,
      reply,
      { text: 'Errado', spoiler: false, parentID: root },
      'bob',
    ).expect(404);
    const body = { text: 'Respondendo @owner', spoiler: false, parentID: root };
    await comment(id, reply, body, 'bob').expect(200);
    await comment(id, reply, body, 'bob').expect(200);
    const page = (await get(`posts/${id}/comments`).expect(200)).body;
    expect(page.comments[1]).toMatchObject({
      parentID: root,
      isReply: true,
      mentions: [{ id: 'owner', handle: '@owner' }],
    });
    expect(
      (
        await get('me/notifications', 'alice').expect(200)
      ).body.notifications.filter((n: { kind: string }) => n.kind === 'reply'),
    ).toHaveLength(1);
    await put('me/blocks/alice', { blocked: true }, 'bob').expect(200);
    await comment(id, randomUUID(), body, 'bob').expect(404);
    expect(
      (await get(`posts/${id}/comments`, 'bob').expect(200)).body.comments[0]
        .parentID,
    ).toBeNull();
  });
  it('discovers unanswered discussions without a catalog item and removes them after a reply', async () => {
    await member('owner');
    await member('alice');
    const marvel = randomUUID(),
      dc = randomUUID(),
      answered = randomUUID();
    await put(
      'posts/' + marvel,
      { ...input, title: 'Galactus' },
      'alice',
    ).expect(200);
    await put(
      'posts/' + dc,
      {
        ...input,
        universeID: 'dc',
        title: 'Batman',
      },
      'alice',
    ).expect(200);
    await put('posts/' + answered, input).expect(200);
    const reply = randomUUID();
    await comment(answered, reply, { text: 'Conversa', spoiler: false }).expect(
      200,
    );
    const pending = (await get('posts?feed=unanswered').expect(200)).body.posts;
    expect(pending.map((p: { id: string }) => p.id).sort()).toEqual(
      [marvel, dc].sort(),
    );
    expect(
      pending.every(
        (p: { itemID: string | null; commentCount: number }) =>
          p.itemID === null && p.commentCount === 0,
      ),
    ).toBe(true);
    expect(
      (
        await get('posts?feed=unanswered&universe=dc&q=Batman').expect(200)
      ).body.posts.map((p: { id: string }) => p.id),
    ).toEqual([dc]);
    await comment(
      marvel,
      randomUUID(),
      { text: 'Primeira resposta', spoiler: false },
      'owner',
    ).expect(200);
    expect(
      (await get('posts?feed=unanswered&universe=marvel').expect(200)).body
        .posts,
    ).toHaveLength(0);
    // Existing discovery and the notification loop continue to include the answered post.
    expect(
      (await get('posts?feed=active').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toContain(marvel);
    expect(
      (await get('me/notifications', 'alice').expect(200)).body.notifications,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          targetType: 'post',
          targetID: marvel,
          kind: 'comment',
        }),
      ]),
    );
    await put(`posts/${dc}/report`, {
      reason: 'spam',
      alsoBlock: false,
    }).expect(200);
    expect(
      (await get('posts?feed=unanswered').expect(200)).body.posts,
    ).toHaveLength(0);
  });
  it('applies comment visibility and author blocks to unanswered discovery', async () => {
    await member('owner');
    await member('alice');
    const post = randomUUID(),
      reply = randomUUID(),
      hiddenAuthorPost = randomUUID();
    await put('posts/' + post, input).expect(200);
    await put('posts/' + hiddenAuthorPost, input, 'alice').expect(200);
    await comment(post, reply, { text: 'Reply', spoiler: false }).expect(200);
    await put(`posts/${post}/comments/${reply}/report`, {
      reason: 'spam',
      alsoBlock: false,
    }).expect(200);
    expect(
      (await get('posts?feed=unanswered').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toContain(post);
    await put('me/blocks/alice', { blocked: true }).expect(200);
    const page = (await get('posts?feed=unanswered').expect(200)).body;
    expect(page.posts.map((p: { id: string }) => p.id)).toEqual([post]);
    expect(page.posts[0].commentCount).toBe(0);
  });
  it('searches content and filters followed, active, theory and duel discovery', async () => {
    await member('owner');
    await member('alice');
    const a = randomUUID(),
      b = randomUUID();
    await put(
      'posts/' + a,
      { ...input, title: 'Galactus e o universo' },
      'alice',
    ).expect(200);
    await put('posts/' + b, {
      ...input,
      title: 'Teoria do futuro',
      kind: 'theory',
    }).expect(200);
    expect(
      (await get('posts?q=Galactus').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toEqual([a]);
    expect(
      (await get('posts?feed=following').expect(200)).body.posts,
    ).toHaveLength(0);
    await follow('alice', true).expect(200);
    expect(
      (await get('posts?feed=following').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toEqual([a]);
    await comment(
      a,
      randomUUID(),
      { text: 'Conversa', spoiler: false },
      'owner',
    ).expect(200);
    expect(
      (await get('posts?feed=active').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toEqual([a]);
    expect(
      (await get('posts?kind=theory').expect(200)).body.posts.map(
        (p: { id: string }) => p.id,
      ),
    ).toEqual([b]);
    await put(`posts/${a}/report`, { reason: 'spam', alsoBlock: false }).expect(
      200,
    );
    expect((await get('posts?q=Galactus').expect(200)).body.posts).toHaveLength(
      0,
    );
  });
  it('counts actual votes, allows changing vote and closes duels and resolved theories', async () => {
    await member('owner');
    await member('alice');
    await member('bob');
    const id = randomUUID();
    await put('posts/' + id, {
      ...input,
      kind: 'duel',
      optionA: 'A',
      optionB: 'B',
      closesAt: new Date(Date.now() + 86400000).toISOString(),
    }).expect(200);
    await Promise.all([
      put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(200),
      put(`posts/${id}/vote`, { choice: 1 }, 'bob').expect(200),
    ]);
    await put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(200);
    expect(
      (await get('posts/' + id, 'alice').expect(200)).body.posts[0].votes,
    ).toEqual({ counts: [1, 1], mine: 0 });
    await put(`posts/${id}/vote`, { choice: 1 }, 'alice').expect(200);
    expect(
      (await get('posts/' + id).expect(200)).body.posts[0].votes.counts,
    ).toEqual([0, 2]);
    await db.query(
      "UPDATE community_posts SET closes_at=now()-interval '1 second' WHERE id=$1",
      [id],
    );
    await put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(409);
    const theory = randomUUID();
    await put('posts/' + theory, { ...input, kind: 'theory' }).expect(200);
    await put(
      `posts/${theory}/resolution`,
      { status: 'confirmed', note: 'Fonte e explicação', version: 1 },
      'alice',
    ).expect(404);
    await put(`posts/${theory}/resolution`, {
      status: 'confirmed',
      note: 'Fonte e explicação',
      version: 1,
    }).expect(200);
    await put(`posts/${theory}/vote`, { choice: 0 }, 'alice').expect(409);
    expect(
      (await get('posts/' + theory).expect(200)).body.posts[0].resolution,
    ).toBe('confirmed');
  });
  it('creates real clubs, membership, schedule, per-member progress and discussions', async () => {
    await member('owner');
    await member('alice');
    const club = randomUUID(),
      schedule = randomUUID(),
      post = randomUUID();
    const clubInput = {
      name: 'Leitores Marvel',
      description: 'Clube de HQs',
      universeID: 'marvel',
    };
    await put('community/clubs/' + club, clubInput).expect(200);
    await put('community/clubs/' + club, clubInput).expect(200);
    expect(
      (await get('community/clubs?q=Marvel', 'alice').expect(200)).body
        .clubs[0],
    ).toMatchObject({ memberCount: 1, joined: false });
    await put('posts/' + post, { ...input, clubID: club }, 'alice').expect(403);
    await put(
      `community/clubs/${club}/membership`,
      { joined: true },
      'alice',
    ).expect(200);
    const work = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const plan = {
      itemID: work,
      startsOn: '2026-10-03',
      totalUnits: 7,
      unitLabel: 'Edições',
    };
    await put(
      `community/clubs/${club}/schedule/${schedule}`,
      plan,
      'alice',
    ).expect(403);
    await put(`community/clubs/${club}/schedule/${schedule}`, plan).expect(200);
    await put(`community/clubs/${club}/schedule/${schedule}`, plan).expect(200);
    await put(
      `community/clubs/${club}/schedule/${schedule}/progress`,
      { units: 3 },
      'alice',
    ).expect(200);
    await put(
      `community/clubs/${club}/schedule/${schedule}/progress`,
      { units: 8 },
      'alice',
    ).expect(400);
    expect(
      (await get(`community/clubs/${club}`, 'alice').expect(200)).body
        .schedule[0].myUnits,
    ).toBe(3);
    expect(
      (
        await get(
          `community/clubs/${club}/members?schedule=${schedule}`,
        ).expect(200)
      ).body.members.find((m: { id: string }) => m.id === 'alice').units,
    ).toBe(3);
    await put(
      'posts/' + post,
      { ...input, clubID: club, scheduleID: schedule, itemID: work },
      'alice',
    ).expect(200);
    expect(
      (await get(`posts?club=${club}&schedule=${schedule}`).expect(200)).body
        .posts,
    ).toHaveLength(1);
    expect((await get('posts').expect(200)).body.posts).toHaveLength(0);
    await put(
      `community/clubs/${club}/membership`,
      { joined: false },
      'alice',
    ).expect(200);
    await comment(
      post,
      randomUUID(),
      { text: 'Fora do clube', spoiler: false },
      'alice',
    ).expect(403);
    await del('community/clubs/' + club).expect(200);
    await get('posts/' + post).expect(404);
  });
  it('creates rooms from published works and stores actual presence, progress and messages', async () => {
    await member('owner');
    await member('alice');
    const rooms = (await get('community/rooms?universe=marvel').expect(200))
      .body.rooms;
    expect(rooms.length).toBeGreaterThan(0);
    const room = rooms[0];
    expect(room.online).toBe(0);
    await put(`community/rooms/${room.itemID}/visit`, { progress: 30 }).expect(
      200,
    );
    expect(
      (await put(`community/rooms/${room.itemID}/visit`, {}).expect(200)).body,
    ).toMatchObject({ progress: 30, online: 1 });
    expect(
      (
        await put(`community/rooms/${room.itemID}/visit`, {}, 'alice').expect(
          200,
        )
      ).body.online,
    ).toBe(2);
    const post = randomUUID();
    await put('posts/' + post, {
      ...input,
      itemID: room.itemID,
      kind: 'room',
    }).expect(200);
    expect(
      (await get(`posts?kind=room&item=${room.itemID}`, 'alice').expect(200))
        .body.posts,
    ).toHaveLength(1);
    expect((await get('posts', 'alice').expect(200)).body.posts).toHaveLength(
      0,
    );
    await db.query("UPDATE room_visits SET seen_at=now()-interval '2 minutes'");
    expect(
      (await get('community/rooms?universe=marvel').expect(200)).body.rooms[0]
        .online,
    ).toBe(0);
  });

  it('delivers room changes immediately and recovers missed revisions without exposing messages', async () => {
    await member('owner');
    await member('alice');
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const path = `community/rooms/${item}/changes`;
    const initial = (await get(path, 'alice').expect(200)).body;
    expect(initial).toMatchObject({ itemID: item, progress: 0 });
    let resolved = false;
    const waiting = get(`${path}?after=${initial.revision}`, 'alice')
      .timeout({ response: 3000 })
      .expect(200)
      .then((r) => {
        resolved = true;
        return r.body;
      });
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(resolved).toBe(false);
    const id = randomUUID();
    await put(`posts/${id}`, { ...input, kind: 'room', itemID: item }).expect(
      200,
    );
    const changed = await waiting;
    expect(BigInt(changed.revision)).toBeGreaterThan(BigInt(initial.revision));
    expect(Object.keys(changed).sort()).toEqual([
      'itemID',
      'online',
      'progress',
      'revision',
    ]);
    // Editing while the viewer is disconnected is recovered from the durable cursor.
    await request(app.getHttpServer())
      .patch(`/api/v1/posts/${id}`)
      .auth('owner', { type: 'bearer' })
      .send({
        title: 'Edited',
        text: 'Changed text',
        spoiler: false,
        imageIDs: [],
        version: 1,
        mutationID: randomUUID(),
      })
      .expect(200);
    const edited = (
      await get(`${path}?after=${changed.revision}`, 'alice')
        .timeout({ response: 3000 })
        .expect(200)
    ).body;
    expect(BigInt(edited.revision)).toBeGreaterThan(BigInt(changed.revision));
    await del(`posts/${id}`).expect(200);
    const deleted = (
      await get(`${path}?after=${edited.revision}`, 'alice')
        .timeout({ response: 3000 })
        .expect(200)
    ).body;
    expect(BigInt(deleted.revision)).toBeGreaterThan(BigInt(edited.revision));
  });

  it('does not advance room revisions for rolled-back writes and validates subscriptions', async () => {
    await member('owner');
    await member('incomplete', false);
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const id = randomUUID(),
      path = `community/rooms/${item}/changes`;
    await put(`posts/${id}`, { ...input, kind: 'room', itemID: item }).expect(
      200,
    );
    const before = (await get(path).expect(200)).body;
    await expect(
      db.transaction(async (client) => {
        await client.query('UPDATE community_posts SET text=$2 WHERE id=$1', [
          id,
          'Must roll back',
        ]);
        throw new Error('rollback');
      }),
    ).rejects.toThrow();
    expect((await get(path).expect(200)).body.revision).toBe(before.revision);
    await get(`${path}?after=-1`).expect(400);
    await get(`${path}?unexpected=1`).expect(400);
    await get('community/rooms/nonexistent/changes').expect(404);
    const incomplete = await get(path, 'incomplete').expect(409);
    expect(incomplete.body.code).toBe('ONBOARDING_REQUIRED');
    await request(app.getHttpServer())
      .get('/api/v1/' + path)
      .expect(401);
  });

  it('authorizes voice by account and segment, keeps retries stable and separates spoiler rooms', async () => {
    await member('owner');
    await member('alice');
    await member('incomplete', false);
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const id = randomUUID(),
      path = `community/rooms/${item}/voice/${id}`;
    await put(path, { segment: 2 }).expect(403);
    await put(path, { segment: 0 }, 'incomplete').expect(409);
    await put(path, { segment: 4 }).expect(400);
    await put(`community/rooms/${item}/visit`, { progress: 100 }).expect(200);
    const first = (await put(path, { segment: 2 }).expect(200)).body;
    const retry = (await put(path, { segment: 2 }).expect(200)).body;
    expect(first).toEqual(retry);
    expect(first.id).toBe(id);
    await put(path, { segment: 0 }, 'alice').expect(409);
    const other = (
      await put(
        `community/rooms/${item}/voice/${randomUUID()}`,
        { segment: 0 },
        'alice',
      ).expect(200)
    ).body;
    expect(first.room).not.toBe(other.room);
    await put(`community/voice/${id}/heartbeat`, {}).expect(200);
    await put(`community/voice/${id}/heartbeat`, {}, 'alice').expect(403);
    expect(voiceMedia.remove).not.toHaveBeenCalled();
    await put(`community/rooms/${item}/visit`, { progress: 0 }).expect(200);
    await put(`community/voice/${id}/heartbeat`, {}).expect(403);
    expect(voiceMedia.remove).toHaveBeenCalledWith(first.room, id);
  });

  it('limits voice capacity, enforces blocks and cleans up expired media leases', async () => {
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const joined: { id: string; uid: string; room: string }[] = [];
    for (let i = 0; i < 8; i++) {
      const uid = 'voice' + i,
        id = randomUUID();
      await member(uid);
      const response = await put(
        `community/rooms/${item}/voice/${id}`,
        { segment: 0 },
        uid,
      ).expect(200);
      joined.push({ uid, id, room: response.body.room });
    }
    await member('extra');
    const full = await put(
      `community/rooms/${item}/voice/${randomUUID()}`,
      { segment: 0 },
      'extra',
    ).expect(409);
    expect(full.body.code).toBe('VOICE_FULL');
    await db.query(
      'INSERT INTO user_blocks(blocker_uid,blocked_uid) VALUES($1,$2)',
      ['extra', joined[0].uid],
    );
    const blocked = await put(
      `community/rooms/${item}/voice/${randomUUID()}`,
      { segment: 0 },
      'extra',
    ).expect(403);
    expect(blocked.body.code).toBe('VOICE_BLOCKED');
    await db.query(
      "UPDATE room_voice_sessions SET expires_at=now()-interval '1 second' WHERE id=$1",
      [joined[0].id],
    );
    await app.get(VoiceService).cleanup();
    expect(voiceMedia.remove).toHaveBeenCalledWith(
      joined[0].room,
      joined[0].id,
    );
    await del(`community/voice/${joined[1].id}`, joined[1].uid).expect(200);
    await del(`community/voice/${joined[1].id}`, joined[1].uid).expect(200);
    await put(
      `community/voice/${joined[1].id}/heartbeat`,
      {},
      joined[1].uid,
    ).expect(403);
  });

  it('limits repeated joins while preserving retry and revokes sessions when voice is disabled', async () => {
    await member('owner');
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const id = randomUUID(),
      path = `community/rooms/${item}/voice/${id}`;
    const joined = (await put(path, { segment: 0 }).expect(200)).body;
    await db.query(
      'UPDATE room_voice_join_limits SET attempts=30 WHERE firebase_uid=$1',
      ['owner'],
    );
    await put(path, { segment: 0 }).expect(200);
    await del(`community/voice/${id}`).expect(200);
    const blocked = await put(`community/rooms/${item}/voice/${randomUUID()}`, {
      segment: 0,
    }).expect(429);
    expect(blocked.body.code).toBe('VOICE_JOIN_LIMIT');
    voiceMedia.enabled = false;
    expect((await get('community/voice').expect(200)).body.enabled).toBe(false);
    await app.get(VoiceService).cleanup();
    expect(voiceMedia.remove).toHaveBeenCalledWith(joined.room, id);
  });

  it('disconnects a deleted account even after its profile has disappeared', async () => {
    await member('owner');
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const id = randomUUID();
    const joined = await put(`community/rooms/${item}/voice/${id}`, {
      segment: 0,
    }).expect(200);
    await db.query('DELETE FROM profiles WHERE firebase_uid=$1', ['owner']);
    await app.get(VoiceService).cleanup();
    expect(voiceMedia.remove).toHaveBeenCalledWith(joined.body.room, id);
  });

  it('protects room spoiler segments, including image endpoints and search', async () => {
    await member('owner');
    await member('alice');
    const item = (
      await db.query(
        "SELECT id FROM catalog_items WHERE universe_id='marvel' AND status='published' LIMIT 1",
      )
    ).rows[0].id;
    const id = randomUUID();
    const body = { ...input, itemID: item, kind: 'room', segment: 2 };
    await put('posts/' + id, body).expect(403);
    await put(`community/rooms/${item}/visit`, { progress: 100 }).expect(200);
    await put('posts/' + id, body).expect(200);
    await get('posts/' + id, 'alice').expect(404);
    expect(
      (await get(`posts?kind=room&item=${item}&segment=2`, 'alice').expect(200))
        .body.posts,
    ).toHaveLength(0);
    await put(
      `community/rooms/${item}/visit`,
      { progress: 100 },
      'alice',
    ).expect(200);
    expect(
      (await get(`posts?kind=room&item=${item}&segment=2`, 'alice').expect(200))
        .body.posts,
    ).toHaveLength(1);
    await put(`community/rooms/${item}/visit`, { progress: 0 }, 'alice').expect(
      200,
    );
    await get('posts/' + id, 'alice').expect(404);
    await put('posts/' + randomUUID(), { ...input, segment: 2 }).expect(400);
    await get('posts?segment=9').expect(400);
  });
  it('hides reported clubs and all associated conversations and supports audited moderation', async () => {
    await member('owner');
    await member('alice');
    await member('bob');
    const club = randomUUID(),
      post = randomUUID();
    await put('community/clubs/' + club, {
      name: 'Clube',
      description: 'Descrição',
      universeID: 'marvel',
    }).expect(200);
    await put('posts/' + post, { ...input, clubID: club }).expect(200);
    await put(
      `community/clubs/${club}/report`,
      { reason: 'spam', alsoBlock: false },
      'alice',
    ).expect(200);
    await put(
      `community/clubs/${club}/report`,
      { reason: 'spam', alsoBlock: false },
      'alice',
    ).expect(200);
    await get('community/clubs/' + club, 'alice').expect(404);
    await get('posts/' + post, 'alice').expect(404);
    await put(
      `community/clubs/${club}/membership`,
      { joined: true },
      'alice',
    ).expect(404);
    expect(await db.transaction((c) => moderationQueue(c))).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          targetType: 'club',
          targetID: club,
          reports: 1,
        }),
      ]),
    );
    await db.transaction((c) =>
      moderate(c, {
        id: randomUUID(),
        targetType: 'club',
        targetID: club,
        action: 'hide',
        operator: 'test',
        reason: 'reviewed',
      }),
    );
    await get('community/clubs/' + club, 'bob').expect(404);
    await get('posts/' + post, 'bob').expect(404);
    await put('community/clubs/' + club, {
      name: 'Outro nome',
      description: 'Descrição',
      universeID: 'marvel',
      version: 1,
    }).expect(404);
  });
  it('enforces image ownership and clears media, mentions, memberships and votes when accounts are deleted', async () => {
    await member('owner');
    await member('alice');
    const id = randomUUID(),
      image = randomUUID(),
      club = randomUUID();
    const base64 = (
      await sharp({
        create: { width: 8, height: 8, channels: 3, background: '#000000' },
      })
        .png()
        .toBuffer()
    ).toString('base64');
    await put(`posts/${id}/images/${image}`, { base64 }).expect(200);
    await put(`posts/${id}/images/${image}`, { base64 }, 'alice').expect(409);
    await put('posts/' + id, {
      ...input,
      kind: 'theory',
      text: 'Oi @alice',
      imageIDs: [image],
    }).expect(200);
    await put(`posts/${id}/vote`, { choice: 0 }, 'alice').expect(200);
    await put('community/clubs/' + club, {
      name: 'Clube',
      description: 'Descrição',
      universeID: 'marvel',
    }).expect(200);
    await put(
      `community/clubs/${club}/membership`,
      { joined: true },
      'alice',
    ).expect(200);
    await db.query("DELETE FROM profiles WHERE firebase_uid='owner'");
    for (const table of [
      'community_images',
      'post_images',
      'community_posts',
      'community_votes',
      'community_mentions',
      'community_clubs',
      'club_members',
    ])
      expect(
        (await db.query(`SELECT count(*)::int AS n FROM ${table}`)).rows[0].n,
      ).toBe(0);
    await get(`posts/${id}/images/${image}`, 'alice').expect(404);
  });
  it('paginates discovery without duplicating posts and rejects malformed or excessive inputs', async () => {
    await member('owner');
    for (let i = 0; i < 35; i++)
      await db.query(
        "INSERT INTO community_posts(id,firebase_uid,universe_id,title,text) VALUES($1,'owner','marvel','Chronicle','Searchable discussion')",
        [randomUUID()],
      );
    const first = (await get('posts?q=Chronicle').expect(200)).body;
    expect(first.posts).toHaveLength(30);
    expect(first.nextCursor).toBeTypeOf('string');
    const next = (
      await get('posts?q=Chronicle&after=' + first.nextCursor).expect(200)
    ).body;
    expect(next.posts).toHaveLength(5);
    expect(
      new Set([...first.posts, ...next.posts].map((p: { id: string }) => p.id))
        .size,
    ).toBe(35);
    expect(next.nextCursor).toBeNull();
    await get('posts?q=' + 'x'.repeat(121)).expect(400);
    await get('posts?feed=unknown').expect(400);
    await get('posts?club=wrong').expect(400);
    await get('posts?after=garbage').expect(400);
    await put('posts/' + randomUUID(), {
      ...input,
      imageIDs: Array(5).fill(randomUUID()),
    }).expect(400);
    await put('posts/' + randomUUID(), {
      ...input,
      kind: 'duel',
      optionA: 'A',
      optionB: 'A',
      closesAt: new Date(Date.now() + 10000).toISOString(),
    }).expect(400);
  });
  it('resolves dotted handles and suppresses removed or blocked mentions in activity', async () => {
    await member('owner');
    await member('alice');
    await db.query(
      "UPDATE profiles SET username='alice.dev' WHERE firebase_uid='alice'",
    );
    const id = randomUUID();
    await put('posts/' + id, { ...input, text: 'Olá @alice.dev!' }).expect(200);
    expect(
      (await get('me/notifications', 'alice').expect(200)).body.notifications,
    ).toHaveLength(1);
    const edit = {
      title: input.title,
      text: 'Sem menções',
      spoiler: false,
      imageIDs: [],
      version: 1,
      mutationID: randomUUID(),
    };
    await request(app.getHttpServer())
      .patch('/api/v1/posts/' + id)
      .auth('owner', { type: 'bearer' })
      .send(edit)
      .expect(200);
    expect(
      (await get('me/notifications', 'alice').expect(200)).body.notifications,
    ).toHaveLength(0);
    await put('me/blocks/alice', { blocked: true }).expect(200);
    await put('posts/' + randomUUID(), {
      ...input,
      text: 'Olá @alice.dev!',
    }).expect(200);
    expect(
      (await get('me/notifications', 'alice').expect(200)).body.notifications,
    ).toHaveLength(0);
  });
});
