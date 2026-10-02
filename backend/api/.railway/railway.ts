import { defineRailway, preserve, project, service } from 'railway/iac';

// Last resort for a per-service CaC repo. Prefer one .railway file for the
// project and drop this if you later combine services into that file.
export const partial = 'api';

export default defineRailway(() => {
  const api = service('api', {
    healthcheck: '/api/v1/health',
    healthcheckTimeout: 120,
    preDeploy: 'npm run db:migrate',
    env: {
      NODE_ENV: 'production',
      PORT: '3000',
      FIREBASE_PROJECT_ID: 'multiverse-7f87c',
      DATABASE_URL: preserve(),
      FIREBASE_SERVICE_ACCOUNT_JSON: preserve(),
      OPENAI_API_KEY: preserve(),
      OPENAI_MODEL: preserve(),
    },
    // dockerfilePath from CaC: "Dockerfile"
    // builder from CaC: "DOCKERFILE"
  });
  return project('multiverse', {
    resources: [api],
  });
});
