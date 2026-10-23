import type { StorybookConfig } from '@storybook/react-vite';
import { unplugin as stylex } from '@stylexjs/unplugin';

const config: StorybookConfig = {
  addons: ['@storybook/addon-vitest'],
  framework: '@storybook/react-vite',
  // The dev server (storybook dev, story tests) serves StyleX CSS at this
  // path. `storybook build` has no such route: the plugin appends the CSS to
  // the preview's CSS asset instead, so the link would only 404 there.
  previewHead: (head, { configType }) =>
    configType === 'PRODUCTION'
      ? (head ?? '')
      : `${head ?? ''}<link rel="stylesheet" href="/virtual:stylex.css" />`,
  stories: ['../src/**/*.stories.tsx'],
  viteFinal: (viteConfig) => {
    viteConfig.plugins = [
      stylex.vite({ useCSSLayers: { before: ['base'] } }),
      ...(viteConfig.plugins ?? []),
    ];
    return viteConfig;
  },
};

export default config;
