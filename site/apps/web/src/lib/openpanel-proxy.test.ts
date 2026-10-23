import { describe, expect, it } from 'vitest';
import { openPanelProxy, type Send } from './openpanel-proxy.ts';

type Sent = { init: RequestInit | undefined; input: string };

/** A fetch that notes each request and answers with `response`. */
function upstream(response: () => Response): { calls: Array<Sent>; send: Send } {
  const calls: Array<Sent> = [];
  return {
    calls,
    send: (input, init) => {
      calls.push({ init, input });
      return Promise.resolve(response());
    },
  };
}

describe('openPanelProxy', () => {
  it('serves the tracker from OpenPanel, kept a day', async () => {
    const { calls, send } = upstream(() => new Response('script'));
    const response = await openPanelProxy(
      new Request('https://caffeinagent.com/api/op/op1.js?v=1'),
      send,
    );
    expect(calls.map((call) => call.input)).toEqual(['https://openpanel.dev/op1.js?v=1']);
    expect(await response.text()).toBe('script');
    expect(response.headers.get('content-type')).toBe('text/javascript');
    expect(response.headers.get('cache-control')).toContain('max-age=86400');
  });

  it('serves the session recorder the same way', async () => {
    const { calls, send } = upstream(() => new Response('replay'));
    await openPanelProxy(new Request('https://caffeinagent.com/api/op/op1-replay.js'), send);
    expect(calls.map((call) => call.input)).toEqual(['https://openpanel.dev/op1-replay.js']);
  });

  it('answers 502 when OpenPanel does not give the script', async () => {
    const { send } = upstream(() => new Response('gone', { status: 404 }));
    const response = await openPanelProxy(
      new Request('https://caffeinagent.com/api/op/op1.js'),
      send,
    );
    expect(response.status).toBe(502);
  });

  it('sends an event on to the OpenPanel server with the visitor it came from', async () => {
    const { calls, send } = upstream(() => Response.json({ ok: true }, { status: 202 }));
    const response = await openPanelProxy(
      new Request('https://caffeinagent.com/api/op/track', {
        body: '{"type":"track"}',
        headers: {
          'cf-connecting-ip': '203.0.113.7',
          'openpanel-client-id': 'client',
          origin: 'https://caffeinagent.com',
          'user-agent': 'Safari',
        },
        method: 'POST',
      }),
      send,
    );
    expect(response.status).toBe(202);
    expect(await response.json()).toEqual({ ok: true });
    const [call] = calls;
    expect(call?.input).toBe('https://analytics.vinena.studio/api/track');
    expect(call?.init?.method).toBe('POST');
    expect(call?.init?.body).toBe('{"type":"track"}');
    const headers = new Headers(call?.init?.headers);
    expect(headers.get('openpanel-client-id')).toBe('client');
    expect(headers.get('openpanel-client-ip')).toBe('203.0.113.7');
    expect(headers.get('origin')).toBe('https://caffeinagent.com');
    expect(headers.get('user-agent')).toBe('Safari');
  });

  it('answers 404 for any other path, and asks nothing upstream', async () => {
    const { calls, send } = upstream(() => new Response('x'));
    const response = await openPanelProxy(
      new Request('https://caffeinagent.com/api/op/anything'),
      send,
    );
    expect(response.status).toBe(404);
    expect(calls).toEqual([]);
  });
});
