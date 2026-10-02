import { json } from 'express';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import helmet from 'helmet';

export function configureApp(app: INestApplication): void {
  app.setGlobalPrefix('api/v1');
  app.use(helmet());
  app.use('/api/v1/posts/:id/images/:imageID', json({ limit: '3mb' }));
  app.use(json({ limit: '100kb' }));
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );
  app.enableShutdownHooks();
}
