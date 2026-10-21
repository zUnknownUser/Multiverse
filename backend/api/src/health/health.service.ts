import { Inject, Injectable } from '@nestjs/common';
import { DatabaseService } from '../database/database.service.js';

@Injectable()
export class HealthService {
  private activeProbe?: Promise<boolean>;
  private response?: Promise<boolean>;
  private cached?: { ready: boolean; expiresAt: number };

  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  async isReady(): Promise<boolean> {
    if (this.cached && this.cached.expiresAt > Date.now())
      return this.cached.ready;
    if (this.response) return this.response;
    // Keep tracking the underlying probe after the HTTP deadline. A stuck pool
    // must not acquire another waiter for each request or after every cache miss.
    if (!this.activeProbe) {
      this.activeProbe = this.db
        .isReady()
        .catch(() => false)
        .finally(() => {
          this.activeProbe = undefined;
        });
    }
    const probe = this.activeProbe;
    this.response = this.waitForProbe(probe).finally(() => {
      this.response = undefined;
    });
    return this.response;
  }

  private async waitForProbe(probe: Promise<boolean>): Promise<boolean> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const ready = await Promise.race([
        probe,
        new Promise<false>((resolve) => {
          timer = setTimeout(() => resolve(false), 2000);
          timer.unref();
        }),
      ]);
      this.cached = { ready, expiresAt: Date.now() + 5000 };
      return ready;
    } finally {
      clearTimeout(timer);
    }
  }
}
