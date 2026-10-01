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
import { importMarvel } from '../src/catalog/providers/import-marvel.js';
import { marvelRegistry } from '../src/catalog/providers/marvel-registry.js';
import type { ImportedMarvelItem } from '../src/catalog/providers/wikidata.js';

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
  },
);
