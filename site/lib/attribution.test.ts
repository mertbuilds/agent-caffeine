import assert from "node:assert/strict";
import { test } from "node:test";
import { checkoutUrlWith, parseUtm, utmFrom } from "./attribution";

const LINK = "https://buy.polar.sh/polar_cl_abc";

test("a link from the app gives its three tags", () => {
  assert.deepEqual(utmFrom("?utm_source=agent-caffeine-app&utm_medium=app&utm_campaign=help"), {
    utm_source: "agent-caffeine-app",
    utm_medium: "app",
    utm_campaign: "help",
  });
});

test("other parameters and empty tags are left out", () => {
  assert.deepEqual(utmFrom("?ref=x&utm_source=&utm_term=%20&email=a%40b.c"), {});
  assert.deepEqual(utmFrom(""), {});
});

test("a tag is cut at 100 characters", () => {
  assert.equal(utmFrom(`?utm_source=${"a".repeat(300)}`).utm_source?.length, 100);
});

test("a checkout link carries the visitor's tags", () => {
  assert.equal(
    checkoutUrlWith(LINK, { utm_source: "claudemarketplaces", utm_medium: "ad", utm_campaign: "launch week" }),
    `${LINK}?utm_source=claudemarketplaces&utm_medium=ad&utm_campaign=launch+week`,
  );
});

test("a visitor with no source is counted as the site's own", () => {
  assert.equal(checkoutUrlWith(LINK, {}), `${LINK}?utm_source=caffeinagent.com`);
  assert.equal(checkoutUrlWith(LINK, { utm_medium: "ad" }), `${LINK}?utm_source=caffeinagent.com`);
});

test("a link's own parameters stay, and a tag of the visitor replaces the link's", () => {
  assert.equal(
    checkoutUrlWith(`${LINK}?discount_code=EARLY&utm_source=old`, { utm_source: "x" }),
    `${LINK}?discount_code=EARLY&utm_source=x`,
  );
});

test("a link that cannot be read comes back as it is", () => {
  assert.equal(checkoutUrlWith("#pricing", { utm_source: "x" }), "#pricing");
});

test("stored tags are read back, and anything else in the store is dropped", () => {
  assert.deepEqual(parseUtm('{"utm_source":"x","other":"y","utm_medium":3}'), { utm_source: "x" });
  assert.deepEqual(parseUtm("{}"), {});
  assert.equal(parseUtm(null), null);
  assert.equal(parseUtm("not json"), null);
  assert.equal(parseUtm('"text"'), null);
});
