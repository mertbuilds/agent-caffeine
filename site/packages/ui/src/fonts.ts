import interLatin from '@fontsource-variable/inter/files/inter-latin-wght-normal.woff2?url';

/**
 * The font files the page head preloads, as the URLs the build serves them
 * under: the Suisse Intl files when the checkout has them, else Inter, the
 * fallback. Vite resolves the CSS and these imports to the same asset, so the
 * preload is the one request the CSS then uses. Suisse through a glob rather
 * than imports: the files are gitignored, and a checkout without them builds
 * with Inter instead of failing.
 */
const suisseUrls = Object.values(
  import.meta.glob<string>('../fonts/*.woff2', { eager: true, import: 'default', query: '?url' }),
);

export const fontUrls: ReadonlyArray<string> = suisseUrls.length > 0 ? suisseUrls : [interLatin];
