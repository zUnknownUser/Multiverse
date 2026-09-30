import {
  Inject,
  Injectable,
  ServiceUnavailableException,
  type OnModuleDestroy,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool, type PoolClient, type QueryResultRow } from 'pg';

@Injectable()
export class DatabaseService implements OnModuleDestroy {
  private readonly pool: Pool | undefined;
  constructor(@Inject(ConfigService) config: ConfigService) {
    const connectionString = config.get<string>('DATABASE_URL');
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
