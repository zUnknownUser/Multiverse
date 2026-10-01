import { Module } from '@nestjs/common';
import { OpenAIService } from './openai.service.js';

@Module({ providers: [OpenAIService], exports: [OpenAIService] })
export class AIModule {}
