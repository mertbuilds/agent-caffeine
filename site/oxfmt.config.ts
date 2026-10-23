import { defineConfig } from 'oxfmt';

export default defineConfig({
  experimentalSortImports: { newlinesBetween: false },
  experimentalSortPackageJson: { sortScripts: true },
  ignorePatterns: [
    'node_modules',
    'dist',
    '.output',
    '.turbo',
    'storybook-static',
    'apps/web/src/paraglide',
    'apps/web/src/routeTree.gen.ts',
    // The blog's articles keep the Next site's Markdown as it was.
    'apps/web/content',
    '.cloudflare',
    '.wrangler',
    'pnpm-lock.yaml',
    '.claude/skills',
  ],
  singleQuote: true,
});
