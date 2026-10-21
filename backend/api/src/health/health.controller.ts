import { Public } from '../auth/firebase-auth.guard.js';
import {
  Controller,
  Get,
  Header,
  Inject,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { HealthService } from './health.service.js';

@Public()
@Controller('health')
export class HealthController {
  constructor(
    @Inject(ConfigService) private readonly config: ConfigService,
    @Inject(HealthService) private readonly health: HealthService,
  ) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  getHealth(): { status: string; service: string; environment: string } {
    return {
      status: 'ok',
      service: 'multiverse-api',
      environment: this.config.get<string>('APP_ENV')!,
    };
  }

  @Get('ready')
  @Header('Cache-Control', 'no-store')
  async getReadiness() {
    const ready = await this.health.isReady();
    const result = {
      status: ready ? 'ready' : 'unavailable',
      service: 'multiverse-api',
      environment: this.config.get<string>('APP_ENV')!,
    };
    if (!ready) throw new ServiceUnavailableException(result);
    return result;
  }
}
