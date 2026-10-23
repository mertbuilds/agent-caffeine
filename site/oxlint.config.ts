import nkzw from '@nkzw/oxlint-config';
import { defineConfig } from 'oxlint';

// Type-aware linting and TS compiler errors are enabled via CLI flags in the
// root `lint` script: `oxlint --type-aware --type-check` (powered by tsgolint).
export default defineConfig({
  extends: [nkzw],
  ignorePatterns: [
    'node_modules',
    'dist',
    '.output',
    '.turbo',
    'storybook-static',
    '.cloudflare',
    '.wrangler',
    'apps/web/src/paraglide',
    'apps/web/src/routeTree.gen.ts',
    '.claude/skills',
  ],
  overrides: [
    {
      files: [
        '**/*.test.*',
        '**/*.stories.*',
        '**/test/**',
        '**/scripts/**',
        'packages/ui/.storybook/**',
      ],
      rules: {
        'react/jsx-no-literals': 'off',
      },
    },
    {
      // Web src runs in the browser and a Cloudflare Worker, not Node. The
      // typecheck cannot catch these: type references from dependencies can pull
      // @types/node into the web program.
      files: ['apps/web/src/**'],
      rules: {
        'no-restricted-globals': [
          'error',
          {
            message:
              'Not available in web src. Use import.meta.env (Vite) or the Worker env binding (cloudflare:workers).',
            name: 'process',
          },
          { message: 'Not available in web src. Use Uint8Array or TextEncoder.', name: 'Buffer' },
          { message: 'Not available in web src. Use import.meta.url.', name: '__dirname' },
          { message: 'Not available in web src. Use import.meta.url.', name: '__filename' },
        ],
      },
    },
  ],
  rules: {
    // All user-facing strings go through Paraglide (`m.*()`). This catches
    // hardcoded JSX text and text-bearing attributes; disable inline only
    // with a justification comment.
    'react/jsx-no-literals': [
      'error',
      {
        allowedStrings: ['•', '·', '/', '%', '×', '+'],
        restrictedAttributes: [
          'label',
          'placeholder',
          'title',
          'alt',
          'aria-label',
          'aria-description',
        ],
      },
    ],
  },
});
