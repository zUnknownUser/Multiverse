const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createChallenge, confirmChallenge, hashCode, TTL_MS, MAX_ATTEMPTS } = require('../lib/verificationPolicy');
const values = { uid: 'u1', email: 'test@example.com', code: '001234', generation: 'g1', secret: 'test-only-secret', now: 1_000_000 };
const active = () => ({ ...createChallenge(undefined, values), status: 'active' });

test('six-digit code supports leading zeros and never stores plaintext', () => {
  const c = active();
  assert.equal(JSON.stringify(c).includes(values.code), false);
  assert.equal(confirmChallenge(c, values).accepted, true);
});
test('wrong guesses consume attempts and fifth failure locks challenge', () => {
  let c = active();
  for (let n = 1; n <= MAX_ATTEMPTS; n++) {
    const result = confirmChallenge(c, { ...values, code: '999999' });
    assert.equal(result.accepted, false);
    c = result.challenge;
    assert.equal(c.attempts, n);
  }
  assert.throws(() => confirmChallenge(c, values), { code: 'resource-exhausted' });
});
test('expired challenge is rejected even with correct code', () => {
  assert.throws(() => confirmChallenge(active(), { ...values, now: values.now + TTL_MS }), { code: 'deadline-exceeded' });
});
test('resend respects cooldown and hourly limit', () => {
  let c = active();
  assert.throws(() => createChallenge(c, { ...values, now: values.now + 59_999 }), { code: 'resource-exhausted' });
  for (let n = 1; n < 5; n++) c = createChallenge(c, { ...values, now: values.now + n * 60_000 });
  assert.throws(() => createChallenge(c, { ...values, now: values.now + 300_000 }), { code: 'resource-exhausted' });
  assert.equal(createChallenge(c, { ...values, now: values.now + 3_600_000 }).hourlySends, 1);
});
test('resend invalidates previous code', () => {
  const c = { ...createChallenge(active(), { ...values, code: '567890', generation: 'g2', now: values.now + 60_000 }), status: 'active' };
  assert.equal(confirmChallenge(c, values).accepted, false);
});
test('another user or changed email cannot confirm', () => {
  assert.throws(() => confirmChallenge(active(), { ...values, uid: 'u2' }), { code: 'failed-precondition' });
  assert.throws(() => confirmChallenge(active(), { ...values, email: 'other@example.com' }), { code: 'failed-precondition' });
  assert.notEqual(hashCode(values.secret, 'u2', values.email, values.generation, values.code), active().hash);
});
test('failed delivery, pending delivery and consumed codes are rejected', () => {
  for (const status of ['sending', 'failed', 'verified']) {
    assert.throws(() => confirmChallenge({ ...active(), status }, values), { code: 'failed-precondition' });
  }
});
test('accepted challenge can retry an interrupted Admin update', () => {
  const result = confirmChallenge(active(), values);
  assert.equal(confirmChallenge(result.challenge, values).accepted, true);
});
