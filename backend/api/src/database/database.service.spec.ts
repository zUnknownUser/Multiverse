import { ConflictException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from './database.service.js';

const pool = vi.hoisted(() => ({
  query: vi.fn(),
  connect: vi.fn(),
  on: vi.fn(),
  end: vi.fn(),
}));
vi.mock('pg', () => ({
  Pool: class {
    query = pool.query;
    connect = pool.connect;
    on = pool.on;
    end = pool.end;
  },
}));

describe('Database transactions', () => {
  const client = { query: vi.fn(), release: vi.fn() };
  let database: DatabaseService;
  beforeEach(() => {
    vi.resetAllMocks();
    pool.connect.mockResolvedValue(client);
    client.query.mockResolvedValue({ rows: [], rowCount: 0 });
    database = new DatabaseService(
      new ConfigService({ DATABASE_URL: 'postgresql://localhost/test' }),
    );
  });

  it('commits before returning the result and releases the connection once', async () => {
    await expect(database.transaction(async () => 'saved')).resolves.toBe(
      'saved',
    );
    expect(client.query.mock.calls.map(([sql]) => sql)).toEqual([
      'BEGIN',
      'COMMIT',
    ]);
    expect(client.release).toHaveBeenCalledOnce();
    expect(client.release).not.toHaveBeenCalledWith(true);
  });

  it('rolls back domain failures and keeps a healthy connection reusable', async () => {
    const conflict = new ConflictException({ code: 'STALE_ONBOARDING' });
    await expect(
      database.transaction(async () => {
        throw conflict;
      }),
    ).rejects.toBe(conflict);
    expect(client.query.mock.calls.map(([sql]) => sql)).toEqual([
      'BEGIN',
      'ROLLBACK',
    ]);
    expect(client.release).toHaveBeenCalledOnce();
    expect(client.release).not.toHaveBeenCalledWith(true);
  });

  it('discards a connection when rollback fails instead of returning an open transaction to the pool', async () => {
    const conflict = new ConflictException({ code: 'STALE_ONBOARDING' });
    client.query.mockImplementation(async (sql: string) => {
      if (sql === 'ROLLBACK') throw new Error('connection no longer usable');
      return { rows: [], rowCount: 0 };
    });
    await expect(
      database.transaction(async () => {
        throw conflict;
      }),
    ).rejects.toBe(conflict);
    expect(client.release).toHaveBeenCalledExactlyOnceWith(true);
  });
});

describe('Database readiness', () => {
  const client = { query: vi.fn(), release: vi.fn() };
  let database: DatabaseService;
  beforeEach(() => {
    vi.resetAllMocks();
    pool.connect.mockResolvedValue(client);
    database = new DatabaseService(
      new ConfigService({
        DATABASE_URL: 'postgresql://localhost/test',
        APP_ENV: 'local',
        FIREBASE_PROJECT_ID: 'demo-multiverse-local',
      }),
    );
  });

  it('accepts only the expected deployment identity', async () => {
    client.query.mockResolvedValue({
      rows: [
        {
          environment: 'local',
          firebase_project_id: 'demo-multiverse-local',
        },
      ],
    });
    expect(await database.isReady()).toBe(true);
    expect(client.release).toHaveBeenCalledExactlyOnceWith(false);
    client.query.mockResolvedValue({
      rows: [
        {
          environment: 'production',
          firebase_project_id: 'multiverse-7f87c',
        },
      ],
    });
    expect(await database.isReady()).toBe(false);
    client.query.mockResolvedValue({ rows: [] });
    expect(await database.isReady()).toBe(false);
  });

  it('discards failed or timed-out clients and does not expose the failure', async () => {
    client.query.mockRejectedValue(new Error('secret connection failure'));
    expect(await database.isReady()).toBe(false);
    expect(client.release).toHaveBeenCalledExactlyOnceWith(true);
  });

  it('handles an exhausted or unavailable pool', async () => {
    pool.connect.mockRejectedValue(new Error('private connection string'));
    expect(await database.isReady()).toBe(false);
    expect(client.query).not.toHaveBeenCalled();
    expect(client.release).not.toHaveBeenCalled();
  });

  it('reports missing configuration without creating a connection', async () => {
    expect(await new DatabaseService(new ConfigService()).isReady()).toBe(
      false,
    );
    expect(pool.connect).not.toHaveBeenCalled();
  });
});
