import { randomUUID } from 'node:crypto';
import { validateDecision, type CurationDecision } from './duel-curation.js';
const sample = (): CurationDecision => ({
  id: randomUUID(),
  candidateID: randomUUID(),
  action: 'create',
  operator: 'editor',
  reason: 'reviewed',
  universe: 'dc',
  category: 'stories',
  translations: {
    'pt-BR': {
      title: 'Qual história?',
      text: 'Converse.',
      optionA: 'Uma aventura',
      optionB: 'Um mistério',
    },
    en: {
      title: 'Which story?',
      text: 'Discuss.',
      optionA: 'An adventure',
      optionB: 'A mystery',
    },
  },
});
it('requires both complete translations and distinct, bounded choices', () => {
  const good = sample();
  expect(() => validateDecision(good)).not.toThrow();
  for (const bad of [
    { ...good, translations: { 'pt-BR': good.translations!['pt-BR'] } },
    {
      ...good,
      translations: {
        ...good.translations,
        en: { ...good.translations!.en, optionB: ' an ADVENTURE ' },
      },
    },
    {
      ...good,
      translations: {
        ...good.translations,
        en: { ...good.translations!.en, title: 'a'.repeat(141) },
      },
    },
    { ...good, universe: 'warcraft' },
    { ...good, scheduledOn: '2026-02-30' },
    { ...good, operator: '' },
  ])
    expect(() => validateDecision(bad as CurationDecision)).toThrow(
      'INVALID_CURATION',
    );
});
