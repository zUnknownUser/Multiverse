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
