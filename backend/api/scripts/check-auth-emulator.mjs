import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { ConfigService } from '@nestjs/config';
import { getApps, deleteApp } from 'firebase-admin/app';
import { FirebaseTokenVerifier } from '../dist/auth/firebase-token-verifier.js';

const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const project = process.env.GCLOUD_PROJECT;
if (
  !host ||
  !/^127\.0\.0\.1:\d+$/.test(host) ||
  project !== 'demo-multiverse-local'
)
  throw new Error(
    'Run through Firebase Auth emulator with the demo-multiverse-local project.',
  );
const verifier = new FirebaseTokenVerifier(
  new ConfigService({ FIREBASE_PROJECT_ID: project }),
);
let uid;
try {
  const response = await fetch(
    `http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: `fixture-${randomUUID()}@example.invalid`,
        password: randomUUID(),
        returnSecureToken: true,
      }),
    },
  );
  assert.equal(response.status, 200);
  const account = await response.json();
  uid = account.localId;
  const identity = await verifier.verify(account.idToken);
  assert.equal(identity.uid, uid);
  assert.equal(identity.aud, project);
  console.log(
    'Real Firebase Admin adapter accepted an isolated Auth emulator account.',
  );
} finally {
  if (uid) await verifier.deleteUser(uid);
  await Promise.all(
    getApps()
      .filter((app) => app.name === `multiverse-api-${project}`)
      .map(deleteApp),
  );
}
