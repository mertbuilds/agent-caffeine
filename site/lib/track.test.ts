import assert from "node:assert/strict";
import { test } from "node:test";
import { isLiveHost, rememberedUtm, track } from "./track";

test("only the two live hosts count", () => {
  assert.equal(isLiveHost("caffeinagent.com"), true);
  assert.equal(isLiveHost("www.caffeinagent.com"), true);
  assert.equal(isLiveHost("caffeinagent.local"), false);
  assert.equal(isLiveHost("localhost"), false);
  assert.equal(isLiveHost("caffeinagent-site-git-feat-aa-look.vercel.app"), false);
  assert.equal(isLiveHost("caffeinagent.com.example.org"), false);
});

test("with no window, nothing is sent and nothing is read", () => {
  assert.doesNotThrow(() => track("download_click", { placement: "hero" }));
  assert.equal(rememberedUtm(), null);
});
