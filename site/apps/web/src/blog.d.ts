// The virtual modules of vite-plugin-blog.ts: content/blog/*.md, read at build time.
declare module 'virtual:blog/index' {
  const index: ReadonlyArray<{
    date: string;
    description: string;
    slug: string;
    title: string;
    updated: string;
  }>;
  export default index;
}

declare module 'virtual:blog/posts' {
  const posts: Readonly<
    Record<
      string,
      {
        faq: ReadonlyArray<{ html: string; q: string; text: string }>;
        html: readonly [string, string];
      }
    >
  >;
  export default posts;
}
