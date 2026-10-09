import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const FOLDERS = ["app", "components", "content", "lib", "public", "scripts"];
const TEXT = /\.(tsx?|md|mdx|json|txt|xml|svg|html|css|sh|webmanifest)$/;

/** The path of the app on a Mac, which keeps the lowercase name. */
const MACHINE_NAMES = ["agent caffeine.app"];

function textFiles(folder: string): string[] {
  return readdirSync(folder, { withFileTypes: true }).flatMap((entry) => {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) return textFiles(path);
    return TEXT.test(entry.name) && !entry.name.endsWith(".test.ts") ? [path] : [];
  });
}

test("the brand is written Agent Caffeine in every text people read", () => {
  const files = [join(ROOT, "README.md"), ...FOLDERS.flatMap((folder) => textFiles(join(ROOT, folder)))];
  assert.ok(files.length > 50);
  const wrong: string[] = [];
  for (const file of files) {
    readFileSync(file, "utf8")
      .split("\n")
      .forEach((line, index) => {
        const rest = MACHINE_NAMES.reduce((text, name) => text.replaceAll(name, ""), line).replaceAll("Agent Caffeine", "");
        if (/agent\s+caffeine/i.test(rest)) wrong.push(`${relative(ROOT, file)}:${index + 1}: ${line.trim()}`);
      });
  }
  assert.deepEqual(wrong, []);
});
