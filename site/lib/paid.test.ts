import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const FOLDERS = ["app", "components", "content", "lib"];
const TEXT = /\.(tsx?|md|mdx|json|txt|css)$/;

/** The words of the free, open source app. None may come back into the site of the paid one. */
const FREE = {
  agpl: /\bAGPL\b/i,
  repo: /github\.com\/(mertbuilds|sponsors)/i,
  support: /#support/,
  free: /free and open source/i,
};

/** The files that tell about other tools, which may be free and open source. */
function allowed(file: string): boolean {
  return (
    file === "lib/compare.ts" ||
    file === "app/compare/page.tsx" ||
    file === "THIRD_PARTY_NOTICES.md" ||
    file.startsWith("content/blog/")
  );
}

function textFiles(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return textFiles(path);
    return TEXT.test(entry.name) && !entry.name.endsWith(".test.ts") ? [path] : [];
  });
}

function freeWords(file: string, text: string): string[] {
  if (allowed(file)) return [];
  return text.split("\n").flatMap((line, index) =>
    (Object.keys(FREE) as (keyof typeof FREE)[])
      .filter((word) => FREE[word].test(line))
      .map((word) => `${file}:${index + 1}: ${word}: ${line.trim()}`),
  );
}

test("no text of the site calls the app free and open source, or links to its code or to support", () => {
  const files = [
    join(ROOT, "README.md"),
    join(ROOT, "TRADEMARKS.md"),
    join(ROOT, "THIRD_PARTY_NOTICES.md"),
    ...FOLDERS.flatMap((folder) => textFiles(join(ROOT, folder))),
  ];
  assert.ok(files.length > 50);
  assert.deepEqual(
    files.flatMap((file) => freeWords(relative(ROOT, file), readFileSync(file, "utf8"))),
    [],
  );
});

test("the check finds each word of the free app, and lets a page about other tools say them", () => {
  assert.equal(freeWords("components/hero.tsx", "Free and open source\nUnder the AGPL-3.0").length, 2);
  assert.equal(freeWords("lib/faq.tsx", "https://github.com/mertbuilds/agent-caffeine").length, 1);
  assert.equal(freeWords("components/footer.tsx", "https://github.com/sponsors/mertbuilds").length, 1);
  assert.equal(freeWords("components/footer.tsx", '<a href="/#support">').length, 1);
  assert.equal(freeWords("app/compare/page.tsx", "Adrafinil is free and open source (MIT)").length, 0);
  assert.equal(freeWords("content/blog/caffeine-mac.md", "Free and open source").length, 0);
  assert.equal(freeWords("components/hero.tsx", "Free for 7 days, then $9 once").length, 0);
});
