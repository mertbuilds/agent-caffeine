import { paraglideVitePlugin } from '@inlang/paraglide-js';
import { unplugin as stylex } from '@stylexjs/unplugin';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';
import { blog } from './vite-plugin-blog.ts';

// Unit tests only: no Cloudflare/Start plugins here. Paraglide compiles
// messages on demand; StyleX transforms component styles for jsdom renders.
export default defineConfig({
  plugins: [
    blog(),
    react(),
    stylex.vite({ useCSSLayers: { before: ['base'] } }),
    paraglideVitePlugin({
      cookieName: 'PARAGLIDE_LOCALE',
      outdir: './src/paraglide',
      project: './project.inlang',
      strategy: ['cookie', 'preferredLanguage', 'baseLocale'],
    }),
  ],
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['./src/test/setup.ts'],
  },
});
