export interface Environment {
  APP_ENV: 'local' | 'test' | 'staging' | 'production';
  NODE_ENV: 'development' | 'test' | 'production';
  PORT: number;
  DATABASE_URL?: string;
  FIREBASE_PROJECT_ID: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL: string;
  PUSH_ENABLED: 'true' | 'false';
  VOICE_ENABLED: 'true' | 'false';
  LIVEKIT_URL?: string;
  LIVEKIT_API_KEY?: string;
  LIVEKIT_API_SECRET?: string;
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

  const appEnv =
    config.APP_ENV ??
    (nodeEnv === 'test'
      ? 'test'
      : nodeEnv === 'production'
        ? 'production'
        : 'local');
  if (
    typeof appEnv !== 'string' ||
    !['local', 'test', 'staging', 'production'].includes(appEnv)
  )
    throw new Error('APP_ENV must be local, test, staging or production.');
  if ((nodeEnv === 'test') !== (appEnv === 'test'))
    throw new Error('APP_ENV=test requires NODE_ENV=test and vice versa.');
  if (['staging', 'production'].includes(appEnv) && nodeEnv !== 'production')
    throw new Error('Hosted environments require NODE_ENV=production.');
  if (
    config.RAILWAY_ENVIRONMENT_NAME &&
    config.RAILWAY_ENVIRONMENT_NAME !== appEnv
  )
    throw new Error('APP_ENV must match RAILWAY_ENVIRONMENT_NAME.');

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
  const projectID = config.FIREBASE_PROJECT_ID ?? 'demo-multiverse-local';
  if (
    typeof projectID !== 'string' ||
    !/^[a-z][a-z0-9-]{4,62}$/.test(projectID)
  )
    throw new Error('Invalid FIREBASE_PROJECT_ID');
  if (appEnv !== 'production' && projectID === 'multiverse-7f87c')
    throw new Error(
      'Production Firebase is forbidden outside APP_ENV=production.',
    );
  if (appEnv === 'production' && projectID !== 'multiverse-7f87c')
    throw new Error('Production requires the production Firebase project.');
  if (appEnv === 'staging' && projectID !== 'multiverse-staging-7f87c')
    throw new Error('Staging requires the staging Firebase project.');
  if (
    config.FIREBASE_AUTH_EMULATOR_HOST &&
    (appEnv !== 'local' || !projectID.startsWith('demo-'))
  )
    throw new Error(
      'Auth emulator requires APP_ENV=local and a demo- Firebase project.',
    );
  if (config.FIREBASE_SERVICE_ACCOUNT_JSON) {
    try {
      if (typeof config.FIREBASE_SERVICE_ACCOUNT_JSON !== 'string')
        throw new Error();
      const account = JSON.parse(config.FIREBASE_SERVICE_ACCOUNT_JSON) as {
        project_id?: string;
      };
      if (account.project_id !== projectID) throw new Error();
    } catch {
      throw new Error(
        'Firebase credential project does not match FIREBASE_PROJECT_ID.',
      );
    }
  }
  const openAIKey = config.OPENAI_API_KEY;
  if (openAIKey !== undefined && typeof openAIKey !== 'string')
    throw new Error('OPENAI_API_KEY must be a string.');
  const openAIModel = config.OPENAI_MODEL ?? 'gpt-4.1-mini';
  if (
    typeof openAIModel !== 'string' ||
    !/^[a-zA-Z0-9._:-]{1,200}$/.test(openAIModel)
  )
    throw new Error('Invalid OPENAI_MODEL.');
  const pushEnabled = config.PUSH_ENABLED ?? 'false';
  if (pushEnabled !== 'true' && pushEnabled !== 'false')
    throw new Error('PUSH_ENABLED must be true or false.');
  const voiceEnabled = config.VOICE_ENABLED ?? 'false';
  if (voiceEnabled !== 'true' && voiceEnabled !== 'false')
    throw new Error('VOICE_ENABLED must be true or false.');
  const livekit = ['LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET'].map(
    (key) => {
      const value = config[key];
      if (value !== undefined && typeof value !== 'string')
        throw new Error(key + ' must be a string.');
      return typeof value === 'string' ? value.trim() || undefined : undefined;
    },
  );
  if (voiceEnabled === 'true') {
    if (livekit.some((value) => !value))
      throw new Error(
        'Voice requires LIVEKIT_URL, LIVEKIT_API_KEY and LIVEKIT_API_SECRET.',
      );
    const url = new URL(livekit[0]!);
    if (
      url.protocol !== 'wss:' ||
      !url.hostname.endsWith('.livekit.cloud') ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.pathname !== '/'
    )
      throw new Error('Voice requires a LiveKit Cloud wss URL.');
  }
  return {
    APP_ENV: appEnv as Environment['APP_ENV'],
    NODE_ENV: nodeEnv,
    VOICE_ENABLED: voiceEnabled,
    LIVEKIT_URL: livekit[0],
    LIVEKIT_API_KEY: livekit[1],
    LIVEKIT_API_SECRET: livekit[2],
    PUSH_ENABLED: pushEnabled,
    PORT: port,
    DATABASE_URL: databaseURL as string | undefined,
    FIREBASE_PROJECT_ID: projectID,
    OPENAI_API_KEY:
      typeof openAIKey === 'string' ? openAIKey.trim() || undefined : undefined,
    OPENAI_MODEL: openAIModel,
  };
}
