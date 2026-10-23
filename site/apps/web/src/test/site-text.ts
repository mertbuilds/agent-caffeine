// Every text of the site people read, keyed by its path from site/: the app's
// source, its articles and messages, and the site's README and notices.
// Generated files and tests are left out.
const files = import.meta.glob<string>(
  [
    '/src/**/*.{ts,tsx,css}',
    '!/src/paraglide/**',
    '!/src/routeTree.gen.ts',
    '!/src/**/*.test.{ts,tsx}',
    '/content/**/*.md',
    '/messages/en.json',
    '/public/_headers',
    '../../../../{README,TRADEMARKS,THIRD_PARTY_NOTICES}.md',
  ],
  { eager: true, import: 'default', query: '?raw' },
);

export const siteText: ReadonlyArray<readonly [file: string, text: string]> = Object.entries(
  files,
).map(([key, text]) => [
  key.startsWith('/') ? `apps/web${key}` : key.replace(/^(?:\.\.\/)+/u, ''),
  text,
]);
