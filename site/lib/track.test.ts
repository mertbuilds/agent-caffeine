import assert from "node:assert/strict";
import { afterEach, test } from "node:test";
import { isLiveHost, rememberUtm, rememberedUtm, track } from "./track";

test("only the two live hosts count", () => {
  assert.equal(isLiveHost("caffeinagent.com"), true);
  assert.equal(isLiveHost("www.caffeinagent.com"), true);
  assert.equal(isLiveHost("caffeinagent.local"), false);
  assert.equal(isLiveHost("localhost"), false);
  assert.equal(isLiveHost("caffeinagent-site-git-feat-aa-look.vercel.app"), false);
  assert.equal(isLiveHost("caffeinagent.com.example.org"), false);
  assert.equal(isLiveHost("evilcaffeinagent.com"), false);
  assert.equal(isLiveHost("caffeinagent.com.evil.io"), false);
});

test("with no window, nothing is sent and nothing is read", () => {
  assert.doesNotThrow(() => track("download_click", { placement: "hero" }));
  assert.equal(rememberedUtm(), null);
});

type Call = readonly unknown[];

/** A page on `hostname`, with OpenPanel and a store that note every call. */
function browser(hostname: string): { sent: Call[]; stored: Call[] } {
  const sent: Call[] = [];
  const stored: Call[] = [];
  const kept = new Map<string, string>();
  Object.assign(globalThis, {
    window: { location: { hostname, search: "?utm_source=x" }, op: (...call: Call) => sent.push(call) },
    sessionStorage: {
      getItem: (key: string) => kept.get(key) ?? null,
      setItem: (key: string, value: string) => {
        stored.push([key, value]);
        kept.set(key, value);
      },
    },
  });
  return { sent, stored };
}

afterEach(() => {
  Reflect.deleteProperty(globalThis, "window");
  Reflect.deleteProperty(globalThis, "sessionStorage");
});

test("on a preview host nothing is sent, kept or read", () => {
  const { sent, stored } = browser("x.vercel.app");
  track("download_click", { placement: "hero" });
  rememberUtm();
  assert.equal(rememberedUtm(), null);
  assert.deepEqual(sent, []);
  assert.deepEqual(stored, []);
});

test("on the live host an event is sent once", () => {
  const { sent } = browser("caffeinagent.com");
  track("download_click", { placement: "hero" });
  assert.deepEqual(sent, [["track", "download_click", { placement: "hero" }]]);
});
