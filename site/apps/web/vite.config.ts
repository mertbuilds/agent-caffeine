import { cloudflare } from '@cloudflare/vite-plugin';
import { paraglideVitePlugin } from '@inlang/paraglide-js';
import { unplugin as stylex } from '@stylexjs/unplugin';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { blog } from './vite-plugin-blog.ts';

export default defineConfig(({ command, mode }) => {
  // The repo-root .env sets NODE_ENV=development and Vite applies it whenever NODE_ENV
  // is unset. `import.meta.env.DEV` follows NODE_ENV, not mode, so a bare `vite build`
  // ships dev-only code (devknobs, the JSX dev runtime). The package `build`
  // script pins NODE_ENV=production; this refuses any build that does not.
  if (command === 'build' && (mode !== 'production' || process.env.NODE_ENV !== 'production')) {
    throw new Error(
      `Refusing to build with mode="${mode}" and NODE_ENV="${process.env.NODE_ENV ?? 'unset'}". ` +
        'Both must be "production", or dev-only code ships. Run the package `build` script ' +
        '(`pnpm --filter @caffeinagent/web build`) instead of a bare `vite build`.',
    );
  }

  return {
    build: {
      rolldownOptions: {
        // Rolldown only warns on an import with no matching export and still exits 0.
        // If paraglide compiles no messages, every `m.*()` import is one and every page
        // throws at render, so fail the build on any in our own code. Vite's handler
        // only logs errors, hence the throw.
        onLog(level, log, handler) {
          if (log.code === 'IMPORT_IS_UNDEFINED' && !log.id?.includes('/node_modules/')) {
            throw new Error(log.message);
          }
          handler(level, log);
        },
      },
    },
    // VITE_* vars live in the repo-root .env (single env file for the whole monorepo).
    envDir: '../..',
    plugins: [
      blog(),
      cloudflare({ viteEnvironment: { name: 'ssr' } }),
      // nodenext needs extensions on relative imports; without them routeTree.gen.ts
      // resolves every route to `any` (the file is @ts-nocheck, so nothing reports it).
      tanstackStart({ router: { addExtensions: true } }),
      react({ compiler: true }),
      // debug:false, StyleX's dev `data-style-src` attribute embeds file:line, and the
      // React Compiler (client-only) shifts line numbers vs the SSR transform, causing a
      // hydration attribute mismatch that detaches React's event tree (dead forms).
      // cssInjectionTarget: the default target is a file named index.css, else the first CSS
      // asset. Hashed names never match, so the rules landed in the font stylesheet, which
      // is linked first and so decides the cascade layer order (flipped without `before`).
      stylex.vite({
        cssInjectionTarget: (fileName) => !fileName.includes('fonts-optional'),
        debug: false,
        useCSSLayers: { before: ['base'] },
      }),
      paraglideVitePlugin({
        cookieName: 'PARAGLIDE_LOCALE',
        outdir: './src/paraglide',
        project: './project.inlang',
        strategy: ['cookie', 'preferredLanguage', 'baseLocale'],
      }),
    ],
    server: {
      // Vite ignores PORT by default; portless assigns one when proxying https://caffeinagent.localhost.
      port: process.env.PORT ? Number(process.env.PORT) : 3000,
    },
  };
});
