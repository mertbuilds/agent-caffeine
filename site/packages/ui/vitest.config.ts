import path from 'node:path';
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin';
import { playwright } from '@vitest/browser-playwright';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    projects: [
      {
        extends: true,
        plugins: [
          // No StyleX plugin here: storybookTest applies the whole Storybook Vite
          // config, and `.storybook/main.ts` already prepends it. Adding it again
          // registers the transform twice on the same server, so on a cold cache
          // every module is compiled twice during the slowest phase in CI.
          storybookTest({
            configDir: path.join(import.meta.dirname, '.storybook'),
            storybookScript: 'pnpm storybook --no-open',
          }),
        ],
        test: {
          browser: {
            enabled: true,
            headless: true,
            instances: [{ browser: 'chromium' }],
            provider: playwright(),
          },
          name: 'storybook',
        },
      },
    ],
  },
});
