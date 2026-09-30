import {
  ForbiddenException,
  Inject,
  Injectable,
  ServiceUnavailableException,
  type OnModuleDestroy,
  type OnModuleInit,
} from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DatabaseService } from '../database/database.service.js';
import { FirebaseTokenVerifier } from '../auth/firebase-token-verifier.js';

@Injectable()
export class AccountLifecycleService implements OnModuleInit, OnModuleDestroy {
  private timer?: ReturnType<typeof setInterval>;
  private reconciling = false;
  constructor(
    @Inject(DatabaseService) private readonly db: DatabaseService,
    @Inject(FirebaseTokenVerifier)
    private readonly firebase: FirebaseTokenVerifier,
  ) {}

  async assertActive(uid: string) {
    const result = await this.db.query(
      'SELECT 1 FROM account_deletions WHERE firebase_uid=$1',
      [uid],
    );
    if (result.rowCount)
      throw new ForbiddenException({ code: 'ACCOUNT_DELETING' });
  }

  // Profile creation and deletion acquire the same transaction lock even when
  // no profile row exists yet. Hash collisions only serialize unrelated accounts.
  private async lock(client: PoolClient, uid: string) {
    await client.query(
      'SELECT pg_advisory_xact_lock(1297502531, hashtext($1))',
      [uid],
    );
  }

  async withActiveAccount<T>(
    uid: string,
    operation: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    return this.db.transaction(async (client) => {
      await this.lock(client, uid);
      const deleted = await client.query(
        'SELECT 1 FROM account_deletions WHERE firebase_uid=$1',
        [uid],
      );
      if (deleted.rowCount)
        throw new ForbiddenException({ code: 'ACCOUNT_DELETING' });
      return operation(client);
    });
  }

  async deleteAccount(uid: string, authTime: number) {
    if (!Number.isFinite(authTime) || Date.now() / 1000 - authTime > 300)
      throw new ForbiddenException({ code: 'RECENT_LOGIN_REQUIRED' });
    await this.db.transaction(async (client) => {
      await this.lock(client, uid);
      await client.query(
        'INSERT INTO account_deletions(firebase_uid) VALUES($1) ON CONFLICT DO NOTHING',
        [uid],
      );
      await client.query(
        'UPDATE profiles SET deletion_requested_at=COALESCE(deletion_requested_at,now()) WHERE firebase_uid=$1',
        [uid],
      );
    });
    try {
      await this.finishDeletion(uid);
    } catch {
      throw new ServiceUnavailableException({ code: 'DELETION_PENDING' });
    }
    return { deleted: true };
  }

  private async finishDeletion(uid: string) {
    // Record failures as attempts too, so a broken identity cannot occupy the
    // first batch forever. Completed deletions need no further external calls.
    const pending = await this.db.query(
      'UPDATE account_deletions SET last_attempt_at=now() WHERE firebase_uid=$1 AND completed_at IS NULL RETURNING firebase_uid',
      [uid],
    );
    if (!pending.rowCount) return;
    await this.firebase.deleteUser(uid);
    await this.db.transaction(async (client) => {
      await this.lock(client, uid);
      await client.query(
        'UPDATE onboarding SET followed_user_ids=array_remove(followed_user_ids,$1),version=version+1 WHERE $1=ANY(followed_user_ids)',
        [uid],
      );
      await client.query('DELETE FROM profiles WHERE firebase_uid=$1', [uid]);
      await client.query(
        'UPDATE account_deletions SET completed_at=COALESCE(completed_at,now()) WHERE firebase_uid=$1',
        [uid],
      );
    });
  }

  onModuleInit() {
    this.timer = setInterval(() => {
      void this.reconcileDeletions();
    }, 60000);
    this.timer.unref();
  }
  async reconcileDeletions() {
    if (this.reconciling) return;
    this.reconciling = true;
    try {
      const pending = await this.db.query<{ firebase_uid: string }>(
        'SELECT firebase_uid FROM account_deletions WHERE completed_at IS NULL ORDER BY last_attempt_at NULLS FIRST, requested_at, firebase_uid LIMIT 25',
      );
      for (const row of pending.rows) {
        try {
          await this.finishDeletion(row.firebase_uid);
        } catch {
          /* A failed deletion cannot prevent processing other accounts. */
        }
      }
    } catch {
      /* Retry durable pending records on the next pass. */
    } finally {
      this.reconciling = false;
    }
  }
  onModuleDestroy() {
    clearInterval(this.timer);
  }
}
