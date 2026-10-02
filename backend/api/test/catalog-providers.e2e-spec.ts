import { randomUUID } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { Test } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import {
  ServiceUnavailableException,
  type INestApplication,
} from '@nestjs/common';
import pg from 'pg';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { DatabaseService } from '../src/database/database.service.js';
import { FirebaseTokenVerifier } from '../src/auth/firebase-token-verifier.js';
import { configureApp } from '../src/configure-app.js';
import { importMarvel } from '../src/catalog/providers/import-marvel.js';
import { marvelRegistry } from '../src/catalog/providers/marvel-registry.js';
import type { ImportedMarvelItem } from '../src/catalog/providers/wikidata.js';
import {
  parseTMDB,
  tmdbMarvelRegistry,
} from '../src/catalog/providers/tmdb.js';
import { stageCandidates } from '../src/catalog/providers/stage-candidates.js';
import { publishTMDB } from '../src/catalog/providers/publish-tmdb.js';

import { parseMetronIssue } from '../src/catalog/providers/metron.js';
import { metronMarvelRegistry } from '../src/catalog/providers/metron-registry.js';
import { publishMetron } from '../src/catalog/providers/publish-metron.js';

const metronBatch = () =>
  metronMarvelRegistry.map((m) =>
    parseMetronIssue(
      {
        id: m.id,
        publisher: { id: 1, name: 'Marvel' },
        series: {
          id: m.seriesID,
          name: m.series,
          year_began: m.year,
          language: 'en',
        },
        number: m.number,
        cover_date: `${m.year}-07-01`,
        store_date: null,
        desc: `English issue synopsis: ${m.series}`,
        page: 32,
      },
      m.id,
    ),
  );

const databaseURL = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseURL)(
  'Marvel catalog and importer with PostgreSQL',
  () => {
    let app: INestApplication;
    let admin: pg.Pool;
    let db: DatabaseService;
    const schema = 'marvel_test_' + randomUUID().replaceAll('-', '');
    const verifier = { verify: vi.fn() };
    const batch: ImportedMarvelItem[] = marvelRegistry.map((mapping) => ({
      mapping,
      revision: 1,
      sourceUrl: 'https://www.wikidata.org/wiki/' + mapping.entityId,
      metadata: {
        titles: {
          'pt-BR': 'Título da fonte',
          en: mapping.expectedEnglishTitle,
        },
        descriptions: { 'pt-BR': '', en: 'Source description' },
        year: '1991',
        creatorIds: [],
        publisherIds: [],
      },
    }));
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
      await app.init();
    });
    afterAll(async () => {
      await app?.close();
      if (admin) {
        await admin.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
        await admin.end();
      }
    });
    it('supports localized search, type filters and stable pagination without provider calls', async () => {
      const get = (query: object) =>
        request(app.getHttpServer())
          .get('/api/v1/catalog/marvel')
          .query(query)
          .set('Accept-Language', 'en');
      const first = (await get({ type: 'HQ', limit: 1 }).expect(200)).body;
      expect(first.total).toBe(3);
      expect(first.items).toHaveLength(1);
      const next = (
        await get({ type: 'HQ', limit: 1, after: first.nextCursor }).expect(200)
      ).body;
      expect(next.items[0].id).not.toBe(first.items[0].id);
      expect((await get({ q: 'CIVIL' }).expect(200)).body.items[0].title).toBe(
        'Civil War',
      );
      expect((await get({ q: 'notfound' }).expect(200)).body.items).toEqual([]);
      for (const query of [
        { limit: 51 },
        { limit: -1 },
        { type: 'unknown' },
        { unknown: 1 },
        { q: ['a', 'b'] },
      ])
        await get(query).expect(400);
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/w-wotlk')
        .expect(404);
    });
    it('searches accents literally and reaches the end of a filtered SQL page', async () => {
      const get = (query: object) =>
        request(app.getHttpServer())
          .get('/api/v1/catalog/marvel')
          .query(query)
          .set('Accept-Language', 'pt-BR');
      const accent = (await get({ q: 'FENIX' }).expect(200)).body;
      expect(accent.items.map((i: { id: string }) => i.id)).toEqual([
        'm-fenix',
      ]);
      for (const q of ['%', '_', "' OR 1=1 --"])
        expect((await get({ q }).expect(200)).body.total).toBe(0);
      const ids: string[] = [];
      let after: string | undefined;
      do {
        const page = (
          await get({
            type: 'HQ',
            limit: 1,
            ...(after ? { after } : {}),
          }).expect(200)
        ).body;
        expect(page.total).toBe(3);
        ids.push(...page.items.map((i: { id: string }) => i.id));
        after = page.nextCursor;
      } while (after && ids.length < 10);
      expect(ids).toEqual(['m-civil', 'm-fenix', 'm-secret']);
      const empty = (await get({ type: 'HQ', after: 'zzz' }).expect(200)).body;
      expect(empty).toMatchObject({ total: 3, items: [], nextCursor: null });
    });
    it('imports idempotently while preserving editorial titles, user references and archival decisions', async () => {
      await db.transaction((client) => importMarvel(client, batch));
      await db.query(
        "UPDATE catalog_items SET status='archived' WHERE id='m-house-of-m'",
      );
      await db.transaction((client) =>
        importMarvel(
          client,
          batch.map((b) => ({ ...b, revision: 2 })),
        ),
      );
      expect(
        (await db.query('SELECT count(*)::int AS count FROM catalog_sources'))
          .rows[0].count,
      ).toBe(batch.length);
      expect(
        (
          await db.query(
            "SELECT status FROM catalog_items WHERE id='m-house-of-m'",
          )
        ).rows[0].status,
      ).toBe('archived');
      const detail = (
        await request(app.getHttpServer())
          .get('/api/v1/catalog/marvel/m-fenix')
          .set('Accept-Language', 'pt-BR')
          .expect(200)
      ).body;
      expect(detail.item.title).toBe('A Saga da Fênix Negra');
      expect(detail.sources[0].metadata.titles['pt-BR']).toBe(
        'Título da fonte',
      );
      expect(detail.sources[0].revision).toBe('2');
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/m-house-of-m')
        .expect(404);
      const fresh = (
        await request(app.getHttpServer())
          .get('/api/v1/catalog/marvel/m-infinity-gauntlet')
          .expect(200)
      ).body;
      expect(fresh.item.desc).toBe('Descrição ainda não disponível.');
      const catalog = (
        await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
      ).body;
      expect(
        catalog.items.some(
          (i: { id: string }) => i.id === 'm-infinity-gauntlet',
        ),
      ).toBe(true);
    });
    it('stages provider data privately and atomically without modifying the published catalog', async () => {
      const candidate = parseTMDB(
        { id: 299534, title: 'Avengers: Endgame', release_date: '2019-04-24' },
        tmdbMarvelRegistry[0],
      );
      const before = (
        await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
      ).body;
      await db.transaction((client) => stageCandidates(client, [candidate]));
      await db.transaction((client) => stageCandidates(client, [candidate]));
      const old = {
        ...candidate,
        fetchedAt: '2000-01-01T00:00:00Z',
        metadata: { ...candidate.metadata, year: '1900' },
      };
      await db.transaction((client) => stageCandidates(client, [old]));
      const rows = (
        await db.query('SELECT metadata FROM catalog_import_candidates')
      ).rows;
      expect(rows).toHaveLength(1);
      expect(rows[0].metadata.year).toBe('2019');
      const after = (
        await request(app.getHttpServer()).get('/api/v1/catalog').expect(200)
      ).body;
      expect(after).toEqual(before);
      expect(
        (
          await request(app.getHttpServer())
            .get('/api/v1/catalog/marvel/m-ultimato')
            .expect(200)
        ).body.sources,
      ).toEqual([]);
      await expect(
        db.transaction((client) =>
          stageCandidates(client, [
            {
              ...candidate,
              externalId: 'movie:999',
              suggestedItemId: 'm-candidate-test',
            },
            { ...candidate, suggestedItemId: 'm-wrong-item' },
          ]),
        ),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      expect(
        (
          await db.query(
            'SELECT count(*)::int AS count FROM catalog_import_candidates',
          )
        ).rows[0].count,
      ).toBe(1);
    });
    it('publishes only reviewed TMDB mappings with localized fallback and preserved editorial data', async () => {
      const candidates = tmdbMarvelRegistry.map((m) =>
        parseTMDB(
          {
            id: m.id,
            ...(m.kind === 'movie'
              ? { title: m.title, release_date: `${m.year}-01-01` }
              : { name: m.title, first_air_date: `${m.year}-01-01` }),
            overview: 'English TMDB synopsis',
            translations: {
              translations: [
                {
                  iso_639_1: 'pt',
                  iso_3166_1: 'BR',
                  data: { overview: 'Sinopse TMDB' },
                },
              ],
            },
          },
          m,
        ),
      );
      await db.transaction((client) => publishTMDB(client, candidates));
      await db.transaction((client) => publishTMDB(client, candidates));
      const get = (locale: string) =>
        request(app.getHttpServer())
          .get('/api/v1/catalog/marvel/m-ultimato')
          .set('Accept-Language', locale)
          .expect(200);
      expect((await get('pt-BR')).body.item).toMatchObject({
        title: 'Vingadores: Ultimato',
        desc: 'Sinopse TMDB',
        avg: 0,
        canon: 'MCU',
      });
      expect((await get('en')).body.item.desc).toBe('English TMDB synopsis');
      expect((await get('en')).body.sources).toHaveLength(1);
      const editorial = (
        await db.query(
          "SELECT description FROM catalog_item_translations WHERE item_id='m-ultimato' AND locale='pt-BR'",
        )
      ).rows[0].description;
      expect(editorial).not.toBe('Sinopse TMDB');
      const missingPT = candidates.map((c) => ({
        ...c,
        fetchedAt: new Date(Date.parse(c.fetchedAt) + 1000).toISOString(),
        metadata: {
          ...c.metadata,
          descriptions: { en: 'Updated English', 'pt-BR': '' },
        },
      }));
      await db.transaction((client) => publishTMDB(client, missingPT));
      await db.transaction((client) => publishTMDB(client, candidates));
      expect((await get('pt-BR')).body.item.desc).toBe(editorial);
      expect((await get('en')).body.item.desc).toBe('Updated English');
      verifier.verify.mockResolvedValue({
        uid: 'tmdb-reader',
        email_verified: true,
        firebase: { sign_in_provider: 'password' },
      });
      await request(app.getHttpServer())
        .put('/api/v1/me/profile')
        .set('Authorization', 'Bearer test')
        .send({
          username: 'tmdb-reader'.replace('-', ''),
          displayName: 'Reader',
          avatarColor: '#123456',
          bio: '',
        })
        .expect(200);
      const activity = (
        await request(app.getHttpServer())
          .put('/api/v1/me/diary/' + randomUUID())
          .set('Authorization', 'Bearer test')
          .set('Accept-Language', 'en')
          .send({
            itemId: 'm-ultimato',
            loggedAt: new Date().toISOString(),
            rating: 0,
            liked: false,
            rewatch: false,
            spoiler: false,
            text: '',
          })
          .expect(200)
      ).body;
      expect(
        activity.items.find((i: { id: string }) => i.id === 'm-ultimato').desc,
      ).toBe('Updated English');
      await expect(
        db.transaction((client) => publishTMDB(client, [candidates[0]])),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      await expect(
        db.transaction((client) =>
          publishTMDB(
            client,
            candidates.map((c, i) =>
              i === 2
                ? { ...c, suggestedItemId: 'd-watchmen' }
                : {
                    ...c,
                    fetchedAt: new Date(
                      Date.parse(c.fetchedAt) + 2000,
                    ).toISOString(),
                  },
            ),
          ),
        ),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      expect((await get('en')).body.item.desc).toBe('Updated English');
      await db.query(
        "UPDATE catalog_items SET status='archived' WHERE id='m-loki'",
      );
      await db.transaction((client) => publishTMDB(client, candidates));
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/m-loki')
        .expect(404);
    });
    it('rolls back the complete batch on mapping conflict and never downgrades a source revision', async () => {
      await db.transaction((client) => importMarvel(client, [batch[0]]));
      expect(
        (
          await db.query(
            "SELECT revision::int FROM catalog_sources WHERE item_id='m-fenix'",
          )
        ).rows[0].revision,
      ).toBe(2);
      await expect(
        db.transaction((client) =>
          importMarvel(client, [
            {
              ...batch[0],
              mapping: {
                ...batch[0].mapping,
                itemId: 'm-new-test',
                entityId: 'Q999',
              },
            },
            {
              ...batch[1],
              mapping: { ...batch[1].mapping, itemId: 'w-wotlk' },
            },
          ]),
        ),
      ).rejects.toBeDefined();
      expect(
        (await db.query("SELECT id FROM catalog_items WHERE id='m-new-test'"))
          .rowCount,
      ).toBe(0);
    });
    it('publishes reviewed Metron issues in PT-BR and EN without replacing arcs or importing engagement', async () => {
      const candidates = metronBatch();
      const before = (
        await request(app.getHttpServer())
          .get('/api/v1/catalog/marvel/m-civil')
          .expect(200)
      ).body;
      await db.transaction(async (client) => {
        for (let offset = 0; offset < candidates.length; offset += 10)
          await stageCandidates(client, candidates.slice(offset, offset + 10));
        await publishMetron(client, candidates);
      });
      await db.transaction((client) => publishMetron(client, candidates));
      for (const m of metronMarvelRegistry) {
        const get = (locale: string) =>
          request(app.getHttpServer())
            .get(`/api/v1/catalog/marvel/m-metron-issue-${m.id}`)
            .set('Accept-Language', locale)
            .expect(200);
        const pt = (await get('pt-BR')).body,
          en = (await get('en')).body;
        expect(pt.item).toMatchObject({
          title: m.titlePT,
          desc: m.descriptionPT,
          avg: 0,
          logCount: 0,
          reviewCount: 0,
        });
        expect(en.item).toMatchObject({
          title: `${m.series} #${m.number}`,
          desc: `English issue synopsis: ${m.series}`,
        });
        expect(pt.sources).toHaveLength(1);
        expect(pt.sources[0]).toMatchObject({
          provider: 'metron',
          externalId: `issue:${m.id}`,
          url: `https://metron.cloud/issue/${m.id}/`,
        });
        expect(pt.sources[0].metadata.attribution.termsUrl).toBe(
          'https://creativecommons.org/licenses/by-sa/4.0/',
        );
        expect(pt.sources[0].metadata.descriptions['pt-BR']).toBe('');
      }
      expect(
        (
          await request(app.getHttpServer())
            .get('/api/v1/catalog/marvel/m-civil')
            .expect(200)
        ).body,
      ).toEqual(before);
      const search = (
        await request(app.getHttpServer())
          .get('/api/v1/catalog/marvel')
          .query({ q: 'guerra civil #1' })
          .set('Accept-Language', 'pt-BR')
          .expect(200)
      ).body;
      expect(search.items.map((i: { id: string }) => i.id)).toEqual([
        'm-metron-issue-3726',
      ]);
      const catalog = (
        await request(app.getHttpServer())
          .get('/api/v1/catalog')
          .set('Accept-Language', 'en')
          .expect(200)
      ).body;
      expect(
        catalog.items.find(
          (i: { id: string }) => i.id === 'm-metron-issue-3726',
        ).desc,
      ).toBe('English issue synopsis: Civil War');
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/m-metron-issue-999999')
        .expect(404);
    });
    it('keeps complete series membership ordered and supports localized diary, reviews and private library after reopening', async () => {
      const expected = [
        { id: 402, count: 7 },
        { id: 1761, count: 8 },
        { id: 2019, count: 9 },
        { id: 3047, count: 6 },
      ];
      for (const locale of ['pt-BR', 'en']) {
        const catalog = (
          await request(app.getHttpServer())
            .get('/api/v1/catalog')
            .set('Accept-Language', locale)
            .expect(200)
        ).body;
        for (const group of expected) {
          const items = catalog.items.filter(
            (i: { series?: { id: string } }) =>
              i.series?.id === `metron-${group.id}`,
          );
          expect(items).toHaveLength(group.count);
          expect(
            items
              .map((i: { series: { position: number } }) => i.series.position)
              .sort((a: number, b: number) => a - b),
          ).toEqual(Array.from({ length: group.count }, (_, i) => i + 1));
          const m = metronMarvelRegistry.find((m) => m.seriesID === group.id)!;
          expect(
            items.every(
              (i: { series: { title: string } }) =>
                i.series.title === (locale === 'pt-BR' ? m.seriesPT : m.series),
            ),
          ).toBe(true);
        }
      }
      verifier.verify.mockImplementation(async (uid: string) => ({
        uid,
        email_verified: true,
        firebase: { sign_in_provider: 'google.com' },
      }));
      await db.query(
        "INSERT INTO profiles(firebase_uid,username,display_name,avatar_color) VALUES('metron-user','metronreader','Reader','#123456')",
      );
      await db.query(
        "INSERT INTO onboarding(firebase_uid,completed,step,universe_ids) VALUES('metron-user',true,3,'{marvel}')",
      );
      const itemID = 'm-metron-issue-42516',
        diaryID = randomUUID();
      const input = {
        itemId: itemID,
        loggedAt: new Date().toISOString(),
        rating: 4,
        liked: false,
        rewatch: false,
        spoiler: false,
        text: 'Minha leitura',
      };
      await request(app.getHttpServer())
        .put('/api/v1/me/diary/' + diaryID)
        .auth('metron-user', { type: 'bearer' })
        .send(input)
        .expect(200);
      await request(app.getHttpServer())
        .put('/api/v1/me/diary/' + diaryID)
        .auth('metron-user', { type: 'bearer' })
        .send(input)
        .expect(200);
      for (const locale of ['pt-BR', 'en']) {
        const history = (
          await request(app.getHttpServer())
            .get('/api/v1/me/activity')
            .auth('metron-user', { type: 'bearer' })
            .set('Accept-Language', locale)
            .expect(200)
        ).body;
        expect(history.entries).toHaveLength(1);
        expect(history.reviews[0].text).toBe('Minha leitura');
        expect(history.items[0].series).toMatchObject({
          id: 'metron-3047',
          number: '6',
          position: 6,
          title:
            locale === 'pt-BR' ? 'Desafio Infinito' : 'The Infinity Gauntlet',
        });
      }
      const listID = randomUUID();
      const ops = [
        { action: 'favorite', itemID, enabled: true },
        { action: 'wanted', itemID, enabled: true },
        { action: 'create_list', listID, title: 'Leituras', description: '' },
        { action: 'add_item', listID, itemID },
      ];
      for (const [version, op] of ops.entries())
        await request(app.getHttpServer())
          .put('/api/v1/me/library')
          .auth('metron-user', { type: 'bearer' })
          .send({ mutationID: randomUUID(), version, ...op })
          .expect(200);
      // Reimport must not alter UID-owned data or duplicate published issues.
      await db.transaction((client) => publishMetron(client, metronBatch()));
      const library = (
        await request(app.getHttpServer())
          .get('/api/v1/me/library')
          .auth('metron-user', { type: 'bearer' })
          .expect(200)
      ).body;
      expect(library).toMatchObject({
        version: 4,
        favoriteIDs: [itemID],
        wantedIDs: [itemID],
      });
      expect(library.lists[0].itemIDs).toEqual([itemID]);
      expect(
        (await db.query('SELECT count(*)::int AS n FROM catalog_series_items'))
          .rows[0].n,
      ).toBe(30);
      expect(
        (
          await db.query(
            "SELECT count(*)::int AS n FROM diary_entries WHERE firebase_uid='metron-user'",
          )
        ).rows[0].n,
      ).toBe(1);
    });
    it('keeps editorial translations and archive decisions, rejects conflicting batches atomically and never downgrades Metron data', async () => {
      const candidates = metronBatch();
      const firstID = candidates[0].suggestedItemId;
      await db.query(
        "UPDATE catalog_item_translations SET title='Título revisado',description='Sinopse revisada' WHERE item_id=$1 AND locale='pt-BR'",
        [firstID],
      );
      const fresh = candidates.map((c) => ({
        ...c,
        fetchedAt: '2030-01-01T00:00:00Z',
        metadata: {
          ...c.metadata,
          descriptions: { en: 'New English', 'pt-BR': '' },
        },
      }));
      await db.transaction((client) => publishMetron(client, fresh));
      await db.transaction((client) => publishMetron(client, candidates));
      const get = (locale: string) =>
        request(app.getHttpServer())
          .get('/api/v1/catalog/marvel/' + firstID)
          .set('Accept-Language', locale)
          .expect(200);
      expect((await get('pt-BR')).body.item).toMatchObject({
        title: 'Título revisado',
        desc: 'Sinopse revisada',
      });
      expect((await get('en')).body.item.desc).toBe('New English');
      await expect(
        db.transaction((client) => publishMetron(client, [fresh[0]])),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      const invalid = fresh.map((c, i) => ({
        ...c,
        fetchedAt: '2031-01-01T00:00:00Z',
        metadata: {
          ...c.metadata,
          descriptions: { en: 'Must roll back', 'pt-BR': '' },
          ...(i === 3 ? { series: { ...c.metadata.series!, id: 999 } } : {}),
        },
      }));
      await expect(
        db.transaction((client) => publishMetron(client, invalid)),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
      expect((await get('en')).body.item.desc).toBe('New English');
      await db.query("UPDATE catalog_items SET status='archived' WHERE id=$1", [
        firstID,
      ]);
      await db.transaction((client) => publishMetron(client, fresh));
      await request(app.getHttpServer())
        .get('/api/v1/catalog/marvel/' + firstID)
        .expect(404);
      await db.query(
        "UPDATE catalog_sources SET item_id='m-civil' WHERE provider='metron' AND external_id='issue:3726'",
      );
      await expect(
        db.transaction((client) => publishMetron(client, fresh)),
      ).rejects.toBeInstanceOf(ServiceUnavailableException);
    });
  },
);
