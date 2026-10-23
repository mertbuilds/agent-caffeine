import { createFileRoute } from '@tanstack/react-router';
import { openPanelProxy } from '../../../lib/openpanel-proxy.ts';

export const Route = createFileRoute('/api/op/$')({
  server: {
    handlers: {
      GET: ({ request }) => openPanelProxy(request),
      POST: ({ request }) => openPanelProxy(request),
    },
  },
});
