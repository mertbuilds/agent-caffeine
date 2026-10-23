declare module 'virtual:stylex:runtime';

declare module '*.css' {
  const css: string;
  export default css;
}

interface ImportMetaEnv {
  /** The OpenPanel project that counts page views. Public: it ships in the page. */
  readonly VITE_OPENPANEL_CLIENT_ID?: string;
}

interface Window {
  op?: (...args: Array<unknown>) => void;
}
