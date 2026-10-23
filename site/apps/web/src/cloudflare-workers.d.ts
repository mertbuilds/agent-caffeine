// The Worker bindings declared in cloudflare.config.ts that src reads through `cloudflare:workers`.
declare module 'cloudflare:workers' {
  export const env: {
    MAC_FILES: import('./lib/mac-files.ts').MacFilesBucket;
  };
}
