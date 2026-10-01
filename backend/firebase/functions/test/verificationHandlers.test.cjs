const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { createRequire } = require('node:module');
const { runInNewContext } = require('node:vm');
const { createChallenge } = require('../lib/verificationPolicy');

const uid = 'verification-test-user';
const email = 'verified-address@example.test';
const secret = 'test-only-code-secret';
const code = '012345';

// Exercises the callable with isolated SDK boundaries; no network or live accounts.
function fixture({ changeBeforeUpdate = false, changeBeforeRecheck = false, disableBeforeRecheck = false, failUpdateOnce = false } = {}) {
  let user = { uid, email, emailVerified: false, disabled: false, providerData: [{ providerId: 'password' }] };
  let challenge = { ...createChallenge(undefined, { uid, email, secret, code, generation: 'test-generation', now: Date.now() }), status: 'active' };
  let reads = 0;
  let failUpdate = failUpdateOnce;
  const updates = [];
  const auth = {
    async getUser(requestedUID) {
      assert.equal(requestedUID, uid);
      reads += 1;
      if (reads === 2 && changeBeforeRecheck) user.email = 'changed-address@example.test';
      if (reads === 2 && disableBeforeRecheck) user.disabled = true;
      return structuredClone(user);
    },
    async updateUser(requestedUID, input) {
      assert.equal(requestedUID, uid);
      updates.push(input);
      if (failUpdate) { failUpdate = false; throw new Error('simulated Firebase outage'); }
      // Change the email after the final read but before the privileged write.
      if (changeBeforeUpdate) user.email = 'unproved-address@example.test';
      Object.assign(user, input);
      return structuredClone(user);
    },
  };
  const firestore = {
    collection(name) {
      assert.equal(name, 'emailVerificationChallenges');
      return { doc(value) { assert.equal(value, uid); return {}; } };
    },
    async runTransaction(callback) {
      const writes = [];
      const result = await callback({
        async get() { return { data: () => structuredClone(challenge) }; },
        update(_ref, value) { writes.push(() => Object.assign(challenge, value)); },
        set(_ref, value) { writes.push(() => { challenge = value; }); },
      });
      for (const apply of writes) apply();
      return result;
    },
  };
  class HttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const sdk = {
    'firebase-admin/app': { initializeApp() {} },
    'firebase-admin/auth': { getAuth: () => auth },
    'firebase-admin/firestore': { getFirestore: () => firestore, Timestamp: { fromMillis: value => value } },
    'firebase-functions/params': { defineSecret: () => ({ value: () => secret }), defineString: () => ({ value: () => 'Test <sender@example.test>' }) },
    'firebase-functions/v2/https': { onCall: (_options, handler) => handler, HttpsError },
  };
  const filename = require.resolve('../lib/index');
  const localRequire = createRequire(filename);
  const exported = {};
  runInNewContext(readFileSync(filename, 'utf8'), {
    exports: exported,
    require: name => sdk[name] ?? localRequire(name),
    AbortSignal,
    fetch: () => { throw new Error('Unexpected email delivery'); },
  }, { filename });
  return { handlers: exported, updates, user: () => user, challenge: () => challenge };
}
const request = { auth: { uid }, data: { code } };

test('a change between the final read and Admin write cannot verify an unproved email', async () => {
  const f = fixture({ changeBeforeUpdate: true });
  assert.equal((await f.handlers.confirmEmailVerificationCode(request)).verified, true);
  assert.equal(f.user().emailVerified, true);
  assert.equal(f.user().email, email);
  assert.equal(f.challenge().status, 'verified');
  assert.equal(f.challenge().hash, '');
});
test('a changed email or disabled account is rejected before the Admin write', async () => {
  for (const options of [{ changeBeforeRecheck: true }, { disableBeforeRecheck: true }]) {
    const f = fixture(options);
    await assert.rejects(() => f.handlers.confirmEmailVerificationCode(request), { code: 'failed-precondition' });
    assert.equal(f.updates.length, 0);
    assert.equal(f.user().emailVerified, false);
  }
});
test('an interrupted Admin update can be retried without accepting a different code', async () => {
  const f = fixture({ failUpdateOnce: true });
  await assert.rejects(() => f.handlers.confirmEmailVerificationCode(request), { code: 'unavailable' });
  assert.equal(f.challenge().status, 'accepted');
  assert.equal(f.user().emailVerified, false);
  await assert.rejects(() => f.handlers.confirmEmailVerificationCode({ ...request, data: { code: '999999' } }), { code: 'invalid-argument' });
  assert.equal(f.updates.length, 1);
  assert.equal((await f.handlers.confirmEmailVerificationCode(request)).verified, true);
  assert.equal(f.user().email, email);
  assert.equal(f.challenge().status, 'verified');
});
