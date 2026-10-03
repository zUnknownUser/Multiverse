import { Inject, Injectable, type OnModuleDestroy } from '@nestjs/common';
import type { Client } from 'pg';
import { DatabaseService } from '../database/database.service.js';

/** One database listener per API instance; no connection is held per viewer. */
@Injectable()
export class RoomEventsService implements OnModuleDestroy {
  private client?: Client;
  private connecting?: Promise<void>;
  private stopped = false;
  private readonly waiters = new Map<string, Set<() => void>>();
  constructor(@Inject(DatabaseService) private readonly db: DatabaseService) {}

  private async connect() {
    if (this.connecting) return this.connecting;
    if (this.client || this.stopped) return;
    this.connecting ??= (async () => {
      const client = await this.db.roomListener();
      if (this.stopped) {
        await client.end();
        return;
      }
      this.client = client;
      const disconnected = () => {
        if (this.client !== client) return;
        this.client = undefined;
        void client.end().catch(() => {});
        for (const group of this.waiters.values())
          for (const wake of group) wake();
      };
      client.on('error', disconnected);
      client.on('end', disconnected);
      client.on('notification', ({ channel, payload }) => {
        if (channel === 'multiverse_room_changed' && payload) {
          for (const wake of this.waiters.get(payload) ?? []) wake();
        }
      });
      try {
        await client.query('LISTEN multiverse_room_changed');
      } catch (error) {
        disconnected();
        throw error;
      }
    })().finally(() => {
      this.connecting = undefined;
    });
    await this.connecting;
  }

  async watch(item: string, signal: AbortSignal) {
    await this.connect();
    let finish = () => {};
    const changed = new Promise<void>((resolve) => {
      const group = this.waiters.get(item) ?? new Set<() => void>();
      this.waiters.set(item, group);
      const timer = setTimeout(() => finish(), 20_000);
      finish = () => {
        clearTimeout(timer);
        signal.removeEventListener('abort', finish);
        group.delete(finish);
        if (!group.size) this.waiters.delete(item);
        resolve();
      };
      group.add(finish);
      signal.addEventListener('abort', finish, { once: true });
      if (signal.aborted) finish();
    });
    return { changed, dispose: finish };
  }
  async onModuleDestroy() {
    this.stopped = true;
    for (const group of this.waiters.values()) for (const wake of group) wake();
    await this.client?.end();
  }
}
