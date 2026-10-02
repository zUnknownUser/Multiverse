const { test } = require('node:test');
const assert = require('node:assert/strict');
const { verificationEmail } = require('../lib/verificationEmail');

test('keeps leading zeros and provides Portuguese HTML and plain text', () => {
  const email = verificationEmail('001234', 'pt-BR');
  assert.match(email.html, /001234/);
  assert.match(email.text, /001234/);
  assert.match(email.html, /lang="pt-BR"/);
  assert.match(email.text, /10 minutos/);
  assert.doesNotMatch(email.html, /<script|<img|https?:\/\//);
});
test('uses English for English variants and Portuguese for unsupported input', () => {
  for (const locale of ['en', 'en-US', 'en_GB']) {
    const email = verificationEmail('123456', locale);
    assert.match(email.html, /lang="en"/);
    assert.match(email.text, /10 minutes/);
  }
  for (const locale of [undefined, {}, 'fr', '<script>']) {
    assert.match(verificationEmail('123456', locale).html, /lang="pt-BR"/);
  }
});
test('rejects invalid codes rather than interpolating arbitrary HTML', () => {
  for (const code of ['12345', '1234567', '<img/>', '123456\n']) {
    assert.throws(() => verificationEmail(code, 'pt-BR'));
  }
});
