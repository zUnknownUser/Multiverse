import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    root: './',
    include: ['**/*.e2e-spec.ts'],
    setupFiles: ['./test/setup-env.ts'],
    globalSetup: ['./test/require-test-database.ts'],
    fileParallelism: false,
    hookTimeout: 60_000,
  },
});
