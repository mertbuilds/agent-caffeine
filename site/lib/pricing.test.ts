import assert from "node:assert/strict";
import { test } from "node:test";
import { CHECKOUT_URL, FULL_PRICE, LAUNCH_PRICE, LAUNCH_PRICE_ACTIVE, PORTAL_URL, PRICE, PRICE_NOW } from "./pricing";

test("the launch price is below the full price", () => {
  assert.ok(LAUNCH_PRICE < FULL_PRICE);
});

test("the price a buyer pays today follows the launch switch", () => {
  assert.equal(PRICE_NOW, LAUNCH_PRICE_ACTIVE ? LAUNCH_PRICE : FULL_PRICE);
  assert.equal(PRICE, `$${PRICE_NOW}`);
});

test("the checkout and the purchases page are on Polar", () => {
  assert.equal(new URL(CHECKOUT_URL).hostname, "buy.polar.sh");
  assert.equal(new URL(PORTAL_URL).hostname, "polar.sh");
});
