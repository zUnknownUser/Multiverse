import { Test } from '@nestjs/testing';
import type { INestApplication } from '@nestjs/common';
import request from 'supertest';
import type { App } from 'supertest/types.js';
import { AppModule } from '../src/app.module.js';
import { configureApp } from '../src/configure-app.js';

describe('API bootstrap (e2e)', () => {
  let app: INestApplication<App>;

  beforeAll(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    configureApp(app);
    await app.listen(0, '127.0.0.1'); // Keep one port per suite; concurrent Supertest requests must not close/rebind it.
  });

  afterAll(async () => {
    await app.close();
  });

  it('serves the health endpoint with security headers', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/health')
      .expect(200)
      .expect('X-Content-Type-Options', 'nosniff')
      .expect('Cache-Control', 'no-store')
      .expect('X-Multiverse-Environment', 'test')
      .expect({ status: 'ok', service: 'multiverse-api', environment: 'test' });
  });

  it('keeps liveness available but readiness unavailable without a configured database', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/health/ready')
      .expect(503)
      .expect('Cache-Control', 'no-store')
      .expect('X-Content-Type-Options', 'nosniff')
      .expect('X-Multiverse-Environment', 'test')
      .expect({
        status: 'unavailable',
        service: 'multiverse-api',
        environment: 'test',
      });
    await request(app.getHttpServer()).get('/api/v1/health').expect(200);
  });

  it('rejects a client from another environment before authentication or writes', async () => {
    await request(app.getHttpServer())
      .put('/api/v1/me/diary/00000000-0000-4000-8000-000000000000')
      .set('X-Multiverse-Environment', 'production')
      .send({})
      .expect(409)
      .expect({ code: 'ENVIRONMENT_MISMATCH' });
    await request(app.getHttpServer())
      .get('/api/v1/health')
      .set('X-Multiverse-Environment', 'test')
      .expect(200);
  });

  it('returns 404 for unknown routes', async () => {
    await request(app.getHttpServer()).get('/api/v1/missing').expect(404);
  });
});
