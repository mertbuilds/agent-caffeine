declare module 'virtual:stylex:runtime';

/** The Worker's bindings. Typed where they are read (lib/release.ts). */
declare module 'cloudflare:workers' {
  export const env: Record<string, unknown>;
}

declare module '*.css' {
  const css: string;
  export default css;
}

interface ImportMetaEnv {
  /** "1" shows a sample release in local dev, where no Mac files are bound. */
  readonly VITE_FAKE_RELEASE?: string;
  /** The OpenPanel project that counts page views. Public: it ships in the page. */
  readonly VITE_OPENPANEL_CLIENT_ID?: string;
}

interface Window {
  op?: (...args: Array<unknown>) => void;
}
