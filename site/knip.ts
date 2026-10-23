import type { KnipConfig } from 'knip';

export default {
  workspaces: {
    '.': {
      entry: ['scripts/**/*.ts'],
      // portless runs from mprocs.yaml, which knip does not read.
      ignoreDependencies: ['portless'],
    },
    'apps/web': {
      // Generated src/paraglide and routeTree.gen.ts need no ignore: knip skips gitignored files.
      entry: ['src/routes/**/*.{ts,tsx}', 'cloudflare.config.ts'],
      // project.inlang/settings.json loads it from node_modules by path.
      ignoreDependencies: ['@inlang/plugin-message-format'],
      // The plugin calls the config with command "build" and mode "development", which
      // vite.config.ts refuses on purpose. It stays an entry via tsconfig.node.json.
      vite: false,
    },
    'packages/ui': {
      // Registry copies (shadcn-cssinjs) keep upstream's export surface so they diff
      // cleanly against the registry; src/index.ts picks what the package exposes.
      ignoreIssues: { 'src/ui/*.tsx': ['exports', 'types'] },
    },
  },
} satisfies KnipConfig;
