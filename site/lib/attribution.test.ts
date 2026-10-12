import assert from "node:assert/strict";
import { test } from "node:test";
import { parseUtm, utmFrom } from "./attribution";

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

test("stored tags are read back, and anything else in the store is dropped", () => {
  assert.deepEqual(parseUtm('{"utm_source":"x","other":"y","utm_medium":3}'), { utm_source: "x" });
  assert.deepEqual(parseUtm("{}"), {});
  assert.equal(parseUtm(null), null);
  assert.equal(parseUtm("not json"), null);
  assert.equal(parseUtm('"text"'), null);
});
