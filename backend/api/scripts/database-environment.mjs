const projects = {
  staging: 'multiverse-staging-7f87c',
  production: 'multiverse-7f87c',
};

export function deploymentIdentity(env) {
  // Migrations are writes: unlike runtime compatibility, their target is always explicit.
  const environment = env.APP_ENV;
  const project = env.FIREBASE_PROJECT_ID;
  if (!['local', 'staging', 'production'].includes(environment) || !project)
    throw new Error(
      'Migrations require explicit APP_ENV and FIREBASE_PROJECT_ID.',
    );
  if (projects[environment] && project !== projects[environment])
    throw new Error(
      'Firebase project does not match the migration environment.',
    );
  if (environment === 'local' && project === projects.production)
    throw new Error('Local migrations cannot use production Firebase.');
  if (
    env.RAILWAY_ENVIRONMENT_NAME &&
    env.RAILWAY_ENVIRONMENT_NAME !== environment
  )
    throw new Error('Migration target does not match the Railway environment.');
  return { environment, project };
}

export async function assertDatabaseEnvironment(client, identity) {
  const existing = await client.query(
    "SELECT to_regclass('deployment_identity') AS identity",
  );
  if (existing.rows[0].identity) {
    const result = await client.query(
      'SELECT environment, firebase_project_id FROM deployment_identity WHERE singleton = true',
    );
    const row = result.rows[0];
    if (
      result.rows.length !== 1 ||
      row.environment !== identity.environment ||
      row.firebase_project_id !== identity.project
    )
      throw new Error(
        'Database belongs to another environment or has no bound identity.',
      );
    return;
  }
  const tables = await client.query(
    'SELECT tablename FROM pg_tables WHERE schemaname = current_schema()',
  );
  // Production's first adoption is explicit. Never bind an existing legacy database as staging/local.
  if (tables.rows.length && identity.environment !== 'production')
    throw new Error(
      'Refusing to bind an existing database without an environment identity. Use an empty database.',
    );
}

export async function bindDatabaseEnvironment(client, identity) {
  await client.query(
    'INSERT INTO deployment_identity(singleton, environment, firebase_project_id) VALUES(true,$1,$2) ON CONFLICT(singleton) DO NOTHING',
    [identity.environment, identity.project],
  );
  await assertDatabaseEnvironment(client, identity);
}
