import assert from "node:assert/strict";
import { test } from "node:test";
import {
  clientIp,
  decideDownload,
  downloadLink,
  downloadUtmFrom,
  hostnameOf,
  isBot,
  isMacBrowser,
  isPrefetch,
  placementFrom,
  trackRequest,
} from "./download";
import type { Release } from "./release";

const SAFARI =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

const CHROME =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36";
const FIREFOX = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0";
/** Safari on an iPad asks for the desktop site, with the user agent of a Mac. */
const IPAD_DESKTOP =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";
const NOT_A_MAC = [
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko)",
  "Homebrew/4.6.15 (Macintosh; arm64 Mac OS X 15.6.1) curl/8.7.1",
  "curl/8.7.1",
  "",
];

const RELEASE: Release = {
  version: "1.0.0",
  build: "14",
  href: "/mac/agent-caffeine-1.0.0-14.dmg",
  filename: "agent-caffeine-1.0.0.dmg",
  size: 9_491_361,
};

test("a placement on the list is kept, any other is other", () => {
  for (const placement of ["header", "menu", "hero", "pricing", "blog", "footer"]) {
    assert.equal(placementFrom(placement), placement);
  }
  assert.equal(placementFrom(null), "other");
  assert.equal(placementFrom(""), "other");
  assert.equal(placementFrom("Hero"), "other");
  assert.equal(placementFrom("<script>"), "other");
});

test("only three tags are kept, each cut at 100 characters", () => {
  const params = new URLSearchParams(
    `utm_source=${"a".repeat(300)}&utm_medium=ad&utm_campaign=%20&utm_term=x&utm_content=y&email=a%40b.c`,
  );
  assert.deepEqual(downloadUtmFrom(params), { utm_source: "a".repeat(100), utm_medium: "ad" });
  assert.deepEqual(downloadUtmFrom(new URLSearchParams("")), {});
});

test("a download link names its place, and the source when there is one", () => {
  assert.equal(downloadLink("hero", null), "/download?from=hero");
  assert.equal(downloadLink("footer", {}), "/download?from=footer");
  assert.equal(
    downloadLink("pricing", { utm_source: "claudemarketplaces", utm_campaign: "launch week", utm_term: "x" }),
    "/download?from=pricing&utm_source=claudemarketplaces&utm_campaign=launch+week",
  );
});

test("no user agent and the known fetchers are bots", () => {
  assert.equal(isBot(null), true);
  assert.equal(isBot(""), true);
  assert.equal(isBot("  "), true);
  for (const userAgent of [
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "curl/8.7.1",
    "Wget/1.21",
    "python-requests/2.32",
    "Mozilla/5.0 (X11; Linux x86_64) HeadlessChrome/126.0",
    "facebookexternalhit/1.1",
    "Slackbot-LinkExpanding 1.0",
    "Twitterbot/1.0",
    "LinkedInBot/1.0",
    "Mozilla/5.0 (compatible; Discordbot/2.0)",
    "Google-PageRenderer Google (+https://developers.google.com/+/web/snippet/) preview",
    "SomeCrawler/1.0",
    "Baiduspider/2.0",
  ]) {
    assert.equal(isBot(userAgent), true, userAgent);
  }
  assert.equal(isBot(SAFARI), false);
});

test("a prefetch is seen in either header", () => {
  assert.equal(isPrefetch(new Headers({ purpose: "prefetch" })), true);
  assert.equal(isPrefetch(new Headers({ "sec-purpose": "prefetch;prerender" })), true);
  assert.equal(isPrefetch(new Headers({ "Sec-Purpose": "Prefetch" })), true);
  assert.equal(isPrefetch(new Headers({ "user-agent": SAFARI })), false);
});

test("a host header loses its port", () => {
  assert.equal(hostnameOf("caffeinagent.com"), "caffeinagent.com");
  assert.equal(hostnameOf("Caffeinagent.com:443"), "caffeinagent.com");
  assert.equal(hostnameOf("localhost:3000"), "localhost");
  assert.equal(hostnameOf(null), "");
});

test("the visitor's address comes from Cloudflare, then the first hop, then the real IP", () => {
  assert.equal(
    clientIp(new Headers({ "cf-connecting-ip": "203.0.113.7", "x-forwarded-for": "198.51.100.1", "x-real-ip": "198.51.100.2" })),
    "203.0.113.7",
  );
  assert.equal(clientIp(new Headers({ "x-forwarded-for": " 203.0.113.7 , 10.0.0.1", "x-real-ip": "198.51.100.2" })), "203.0.113.7");
  assert.equal(clientIp(new Headers({ "x-real-ip": "198.51.100.2" })), "198.51.100.2");
  assert.equal(clientIp(new Headers({ "x-forwarded-for": "" })), null);
  assert.equal(clientIp(new Headers()), null);
});

/** A person's click on the live site, changed by `over`. */
function decide(over: Partial<Parameters<typeof decideDownload>[0]> = {}) {
  return decideDownload({
    host: "caffeinagent.com",
    method: "GET",
    headers: new Headers({ "user-agent": SAFARI, "x-forwarded-for": "203.0.113.7" }),
    search: "?from=hero&utm_source=x",
    release: RELEASE,
    secretSet: true,
    ...over,
  });
}

test("a person's click on the live site is counted and goes to the dmg", () => {
  assert.deepEqual(decide(), {
    redirectTo: "/mac/agent-caffeine-1.0.0-14.dmg",
    event: {
      name: "download",
      properties: { version: "1.0.0", build: "14", placement: "hero", utm_source: "x" },
      ip: "203.0.113.7",
      userAgent: SAFARI,
    },
  });
  assert.equal(decide({ host: "www.caffeinagent.com:443" }).event?.name, "download");
  assert.equal(decide({ search: "" }).event?.properties.placement, "other");
});

test("a release with no build number is counted without one", () => {
  const { build: _build, ...release } = RELEASE;
  assert.deepEqual(decide({ release }).event?.properties, { version: "1.0.0", placement: "hero", utm_source: "x" });
});

test("off the live site the request goes to the dmg and nothing is counted", () => {
  for (const host of ["caffeinagent.local", "localhost:3000", "x.vercel.app", "caffeinagent.com.evil.io", null]) {
    assert.deepEqual(decide({ host }), { redirectTo: RELEASE.href, event: null });
  }
});

test("without the secret nothing is counted", () => {
  assert.deepEqual(decide({ secretSet: false }), { redirectTo: RELEASE.href, event: null });
});

test("a HEAD, a bot and a prefetch get the redirect and are not counted", () => {
  const expected = { redirectTo: RELEASE.href, event: null };
  assert.deepEqual(decide({ method: "HEAD" }), expected);
  assert.deepEqual(decide({ headers: new Headers() }), expected);
  assert.deepEqual(decide({ headers: new Headers({ "user-agent": "curl/8.7.1" }) }), expected);
  assert.deepEqual(decide({ headers: new Headers({ "user-agent": SAFARI, "sec-purpose": "prefetch" }) }), expected);
});

test("only a browser on a Mac is a Mac browser", () => {
  for (const userAgent of [SAFARI, CHROME, FIREFOX, IPAD_DESKTOP]) assert.equal(isMacBrowser(userAgent), true, userAgent);
  for (const userAgent of NOT_A_MAC.filter((entry) => !entry.startsWith("Homebrew"))) {
    assert.equal(isMacBrowser(userAgent), false, userAgent);
  }
  assert.equal(isMacBrowser(null), false);
});

test("Safari, Chrome and Firefox on a Mac are counted, and an iPad that asks for the desktop site with them", () => {
  for (const userAgent of [SAFARI, CHROME, FIREFOX, IPAD_DESKTOP]) {
    assert.equal(decide({ headers: new Headers({ "user-agent": userAgent }) }).event?.userAgent, userAgent, userAgent);
  }
});

test("a phone, a tablet, Windows, Linux, a bare WebKit, Homebrew, curl and no user agent get the redirect and are not counted", () => {
  for (const userAgent of NOT_A_MAC) {
    assert.deepEqual(decide({ headers: new Headers({ "user-agent": userAgent }) }), { redirectTo: RELEASE.href, event: null }, userAgent);
  }
});

test("with no release, or a release with no file, the request goes to the home page", () => {
  assert.deepEqual(decide({ release: null }), { redirectTo: "/", event: null });
  assert.deepEqual(decide({ release: { ...RELEASE, href: "#" } }), { redirectTo: "/", event: null });
});

test("the count goes to OpenPanel with the secret and the visitor's address and browser", () => {
  const { event } = decide();
  assert.ok(event);
  const { url, init } = trackRequest(event, "client-id", "client-secret");
  assert.equal(url, "https://analytics.vinena.studio/api/track");
  assert.equal(init.method, "POST");
  assert.deepEqual(init.headers, {
    "Content-Type": "application/json",
    "openpanel-client-id": "client-id",
    "openpanel-client-secret": "client-secret",
    "user-agent": SAFARI,
    "openpanel-client-ip": "203.0.113.7",
    "x-client-ip": "203.0.113.7",
  });
  assert.deepEqual(JSON.parse(init.body), {
    type: "track",
    payload: { name: "download", properties: { version: "1.0.0", build: "14", placement: "hero", utm_source: "x" } },
  });
});

test("with no address the count carries no IP header", () => {
  const { event } = decide({ headers: new Headers({ "user-agent": SAFARI }) });
  assert.ok(event);
  const { headers } = trackRequest(event, "client-id", "client-secret").init;
  assert.equal("openpanel-client-ip" in headers, false);
  assert.equal("x-client-ip" in headers, false);
});
