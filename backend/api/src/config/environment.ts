export interface Environment {
  NODE_ENV: 'development' | 'test' | 'production';
  PORT: number;
  DATABASE_URL?: string;
  FIREBASE_PROJECT_ID: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL: string;
}

export function validateEnvironment(
  config: Record<string, unknown>,
): Environment {
  const nodeEnv = config.NODE_ENV ?? 'development';
  if (
    nodeEnv !== 'development' &&
    nodeEnv !== 'test' &&
    nodeEnv !== 'production'
  ) {
    throw new Error('NODE_ENV must be development, test or production.');
  }

  const rawPort = config.PORT ?? '3000';
  if (typeof rawPort !== 'string' && typeof rawPort !== 'number') {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }
  const port = Number(rawPort);
  if (
    !/^\d+$/.test(String(rawPort)) ||
    !Number.isInteger(port) ||
    port < 1 ||
    port > 65535
  ) {
    throw new Error('PORT must be an integer between 1 and 65535.');
  }

  const databaseURL = config.DATABASE_URL;
  if (
    databaseURL !== undefined &&
    (typeof databaseURL !== 'string' ||
      !/^postgres(?:ql)?:\/\//.test(databaseURL))
  )
    throw new Error('DATABASE_URL must be a PostgreSQL connection URL.');
  if (
    nodeEnv === 'production' &&
    (!databaseURL ||
      !config.FIREBASE_PROJECT_ID ||
      config.FIREBASE_AUTH_EMULATOR_HOST)
  )
    throw new Error(
      'Production requires DATABASE_URL and FIREBASE_PROJECT_ID; Auth emulator is forbidden.',
    );
  const projectID = config.FIREBASE_PROJECT_ID ?? 'multiverse-7f87c';
  if (
    typeof projectID !== 'string' ||
    !/^[a-z][a-z0-9-]{4,62}$/.test(projectID)
  )
    throw new Error('Invalid FIREBASE_PROJECT_ID');
  const openAIKey = config.OPENAI_API_KEY;
  if (openAIKey !== undefined && typeof openAIKey !== 'string')
    throw new Error('OPENAI_API_KEY must be a string.');
  const openAIModel = config.OPENAI_MODEL ?? 'gpt-4.1-mini';
  if (
    typeof openAIModel !== 'string' ||
    !/^[a-zA-Z0-9._:-]{1,200}$/.test(openAIModel)
  )
    throw new Error('Invalid OPENAI_MODEL.');
  return {
    NODE_ENV: nodeEnv,
    PORT: port,
    DATABASE_URL: databaseURL as string | undefined,
    FIREBASE_PROJECT_ID: projectID,
    OPENAI_API_KEY:
      typeof openAIKey === 'string' ? openAIKey.trim() || undefined : undefined,
    OPENAI_MODEL: openAIModel,
  };
}
