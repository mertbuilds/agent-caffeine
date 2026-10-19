import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const FOLDERS = ["app", "components", "content", "lib"];
const TEXT = /\.(tsx?|md|mdx|json|txt|css)$/;

/** The words of a paid app. None may come back into a text people read. */
const PAID = {
  price: /\$\d/,
  trial: /\btrial\b/i,
  buy: /\bbuy(s|ing)?\b/i,
  key: /licen[sc]e key/i,
  purchase: /purchas/i,
};

type Word = keyof typeof PAID;

/** The files that may say such a word, because they tell what another tool costs or what happens to an earlier payment. */
const ALLOWED: Record<string, readonly Word[]> = {
  "lib/compare.ts": ["price", "trial"],
  "app/compare/page.tsx": ["price", "trial", "purchase"],
  "content/blog/amphetamine-mac.md": ["purchase"],
  "lib/faq.tsx": ["purchase"],
  "app/privacy/page.tsx": ["purchase"],
  "app/terms/page.tsx": ["purchase"],
};

function textFiles(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return textFiles(path);
    return TEXT.test(entry.name) && !entry.name.endsWith(".test.ts") ? [path] : [];
  });
}

function paidWords(file: string, text: string): string[] {
  const allowed = ALLOWED[file] ?? [];
  return text.split("\n").flatMap((line, index) =>
    (Object.keys(PAID) as Word[])
      .filter((word) => !allowed.includes(word) && PAID[word].test(line))
      .map((word) => `${file}:${index + 1}: ${word}: ${line.trim()}`),
  );
}

test("no text people read names a price, a trial, a key or a way to buy the app", () => {
  const files = [join(ROOT, "README.md"), ...FOLDERS.flatMap((folder) => textFiles(join(ROOT, folder)))];
  assert.ok(files.length > 50);
  assert.deepEqual(
    files.flatMap((file) => paidWords(relative(ROOT, file), readFileSync(file, "utf8"))),
    [],
  );
});

test("the check finds each word of a paid app, and lets a file on the list say its own", () => {
  assert.equal(paidWords("components/hero.tsx", "Free for 7 days\nThen $19 once\nBuy for less").length, 2);
  assert.equal(paidWords("components/hero.tsx", "A 7-day free trial, then a license key").length, 2);
  assert.equal(paidWords("lib/faq.tsx", "Every purchase is refunded").length, 0);
  assert.equal(paidWords("lib/faq.tsx", "Buy a key for $19").length, 2);
  assert.equal(paidWords("components/hero.tsx", "Free and open source").length, 0);
});
