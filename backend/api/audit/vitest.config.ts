import { defineConfig } from 'vitest/config';
import e2e from '../vitest.config.e2e.js';

// Focused entry point for the white-box regressions, also included in regular CI.
export default defineConfig({
  ...e2e,
  test: { ...e2e.test, include: ['test/white-box.e2e-spec.ts'] },
});
