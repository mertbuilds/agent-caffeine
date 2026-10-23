import { createFileRoute } from '@tanstack/react-router';
import { sitemapXml } from '../lib/seo.ts';

export const Route = createFileRoute('/sitemap.xml')({
  server: {
    handlers: {
      GET: () => new Response(sitemapXml(), { headers: { 'content-type': 'application/xml' } }),
    },
  },
});
