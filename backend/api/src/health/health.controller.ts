import { Public } from '../auth/firebase-auth.guard.js';
import { Controller, Get } from '@nestjs/common';

@Public()
@Controller('health')
export class HealthController {
  @Get()
  getHealth(): { status: string; service: string } {
    return { status: 'ok', service: 'multiverse-api' };
  }
}
