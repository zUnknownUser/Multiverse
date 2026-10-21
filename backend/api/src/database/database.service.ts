import {
  Inject,
  Injectable,
  ServiceUnavailableException,
  type OnModuleDestroy,
  type OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Client, Pool, type PoolClient, type QueryResultRow } from 'pg';

@Injectable()
export class DatabaseService implements OnModuleDestroy, OnModuleInit {
  private readonly connectionString: string | undefined;
  private readonly pool: Pool | undefined;
  constructor(@Inject(ConfigService) private readonly config: ConfigService) {
    const connectionString = config.get<string>('DATABASE_URL');
    this.connectionString = connectionString;
    if (connectionString) {
      this.pool = new Pool({
        connectionString,
        max: 10,
        connectionTimeoutMillis: 5000,
        idleTimeoutMillis: 30000,
        statement_timeout: 10000,
      });
      this.pool.on('error', () => {
        /* Requests report availability without logging connection secrets. */
      });
    }
  }
  async onModuleInit() {
    const environment = this.config.get<string>('APP_ENV');
    // Test fixtures inject their own schemas; real servers must use a bound database.
    if (!environment || environment === 'test' || !this.pool) return;
    try {
      const identity = await this.pool.query<{
        environment: string;
        firebase_project_id: string;
      }>(
        'SELECT environment, firebase_project_id FROM deployment_identity WHERE singleton = true',
      );
      if (
        identity.rows.length !== 1 ||
        identity.rows[0].environment !== environment ||
        identity.rows[0].firebase_project_id !==
          this.config.get<string>('FIREBASE_PROJECT_ID')
      ) {
        throw new Error('Mismatch');
      }
    } catch {
      throw new Error(
        'Database environment mismatch or missing identity. Run migrations for the intended environment.',
      );
    }
  }
  async isReady(): Promise<boolean> {
    if (!this.pool) return false;
    let client: PoolClient | undefined;
    let discardClient = false;
    try {
      client = await this.pool.connect();
      // pg supports a per-query timeout; @types/pg currently only declares the
      // connection-level option. Keep the probe deadline off application queries.
      const probe = {
        text: 'SELECT environment, firebase_project_id FROM deployment_identity WHERE singleton = true',
        query_timeout: 1000,
      };
      const identity = await client.query<{
        environment: string;
        firebase_project_id: string;
      }>(probe);
      return (
        identity.rows.length === 1 &&
        identity.rows[0].environment === this.config.get<string>('APP_ENV') &&
        identity.rows[0].firebase_project_id ===
          this.config.get<string>('FIREBASE_PROJECT_ID')
      );
    } catch {
      // A client-side timeout must not return a still-running query to the pool.
      discardClient = true;
      return false;
    } finally {
      client?.release(discardClient);
    }
  }
  async roomListener() {
    if (!this.connectionString)
      throw new ServiceUnavailableException({ code: 'DATABASE_UNAVAILABLE' });
    const client = new Client({
      connectionString: this.connectionString,
      connectionTimeoutMillis: 5000,
      keepAlive: true,
    });
    client.on('error', () => {});
    try {
      await client.connect();
      return client;
    } catch (error) {
      await client.end().catch(() => {});
      throw this.mapError(error);
    }
  }
  async query<T extends QueryResultRow>(sql: string, values: unknown[] = []) {
    if (!this.pool)
      throw new ServiceUnavailableException({ code: 'DATABASE_UNAVAILABLE' });
    try {
      return await this.pool.query<T>(sql, values);
    } catch (error) {
      throw this.mapError(error);
    }
  }
  async transaction<T>(
    operation: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    if (!this.pool)
      throw new ServiceUnavailableException({ code: 'DATABASE_UNAVAILABLE' });
    let client: PoolClient | undefined;
    let discardClient = false;
    try {
      client = await this.pool.connect();
      await client.query('BEGIN');
      const result = await operation(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      if (client) {
        try {
          await client.query('ROLLBACK');
        } catch {
          discardClient = true;
        }
      }
      throw this.mapError(error);
    } finally {
      client?.release(discardClient);
    }
  }
  private mapError(error: unknown): unknown {
    // Domain errors and unique conflicts are handled by the account service.
    if (error instanceof Error && 'getStatus' in error) return error;
    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23505'
    )
      return error;
    return new ServiceUnavailableException({ code: 'DATABASE_UNAVAILABLE' });
  }
  async onModuleDestroy() {
    await this.pool?.end();
  }
}
