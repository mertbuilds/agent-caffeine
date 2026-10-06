import assert from "node:assert/strict";
import { test } from "node:test";
import { lidBrightness, lidDegrees } from "./geometry";

const near = (value: number, wanted: number) => assert.ok(Math.abs(value - wanted) < 0.01, `${value} is not near ${wanted}`);

test("the drawn lid is 105 degrees open and 0 degrees shut", () => {
  assert.equal(lidDegrees(0), 105);
  assert.equal(lidDegrees(1), 0);
});

test("the display dims with the lid angle as the app sets it", () => {
  assert.equal(lidBrightness(105), 1);
  assert.equal(lidBrightness(45), 1);
  near(lidBrightness(30), 0.71);
  near(lidBrightness(24), 0.5);
  near(lidBrightness(15), 0.2);
  assert.equal(lidBrightness(3), 0);
  assert.equal(lidBrightness(0), 0);
});
