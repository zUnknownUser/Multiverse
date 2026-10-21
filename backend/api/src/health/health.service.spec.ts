import { DatabaseService } from '../database/database.service.js';
import { HealthService } from './health.service.js';

describe('Readiness probe coordination', () => {
  const database = { isReady: vi.fn<() => Promise<boolean>>() };
  let service: HealthService;

  beforeEach(() => {
    vi.useFakeTimers();
    database.isReady.mockReset();
    service = new HealthService(database as unknown as DatabaseService);
  });
  afterEach(() => vi.useRealTimers());

  it('shares concurrent probes and expires a successful cached result', async () => {
    database.isReady.mockResolvedValue(true);
    expect(await Promise.all([service.isReady(), service.isReady()])).toEqual([
      true,
      true,
    ]);
    expect(database.isReady).toHaveBeenCalledOnce();
    database.isReady.mockResolvedValue(false);
    await vi.advanceTimersByTimeAsync(4999);
    expect(await service.isReady()).toBe(true);
    await vi.advanceTimersByTimeAsync(1);
    expect(await service.isReady()).toBe(false);
    expect(database.isReady).toHaveBeenCalledTimes(2);
  });

  it('fails within two seconds without adding waiters while a probe is stuck', async () => {
    let finish!: (ready: boolean) => void;
    database.isReady.mockReturnValue(
      new Promise<boolean>((resolve) => {
        finish = resolve;
      }),
    );
    const first = service.isReady();
    await vi.advanceTimersByTimeAsync(2000);
    expect(await first).toBe(false);
    await vi.advanceTimersByTimeAsync(5000);
    const second = service.isReady();
    await vi.advanceTimersByTimeAsync(2000);
    expect(await second).toBe(false);
    expect(database.isReady).toHaveBeenCalledOnce();
    finish(true);
    await vi.advanceTimersByTimeAsync(5000);
    database.isReady.mockResolvedValue(true);
    expect(await service.isReady()).toBe(true);
    expect(database.isReady).toHaveBeenCalledTimes(2);
  });

  it('caches failures and recovers without propagating database error text', async () => {
    database.isReady.mockRejectedValue(new Error('private connection details'));
    expect(await service.isReady()).toBe(false);
    expect(await service.isReady()).toBe(false);
    expect(database.isReady).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(5000);
    database.isReady.mockResolvedValue(true);
    expect(await service.isReady()).toBe(true);
  });
});
