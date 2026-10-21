import { json, type Request, type Response, type NextFunction } from 'express';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe, type INestApplication } from '@nestjs/common';
import helmet from 'helmet';

export function configureApp(app: INestApplication): void {
  app.setGlobalPrefix('api/v1');
  app.use(helmet());
  const environment = app.get(ConfigService).get<string>('APP_ENV');
  app.use((req: Request, res: Response, next: NextFunction) => {
    res.setHeader('X-Multiverse-Environment', environment!);
    const requested = req.get('X-Multiverse-Environment');
    if (requested && requested !== environment) {
      res.status(409).json({ code: 'ENVIRONMENT_MISMATCH' });
      return;
    }
    next();
  });
  app.use('/api/v1/posts/:id/images/:imageID', json({ limit: '3mb' }));
  app.use('/api/v1/me/profile/details', json({ limit: '3mb' }));
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
