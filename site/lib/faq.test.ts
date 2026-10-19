import assert from "node:assert/strict";
import { test } from "node:test";
import { answerText, faqItems } from "./faq";

test("every question has its own id for the count, and an answer in plain text", () => {
  const items = faqItems();
  assert.equal(new Set(items.map((item) => item.id)).size, items.length);
  for (const item of items) {
    assert.match(item.id, /^[a-z]+$/);
    assert.ok(answerText(item.answer).trim().length > 0);
  }
});
