import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { test } from "node:test";

const ROOT = join(import.meta.dirname, "..");
const FOLDERS = ["app", "components", "content", "lib", "public", "scripts"];
const TEXT = /\.(tsx?|md|mdx|json|txt|xml|svg|html|css|sh|webmanifest)$/;

/**
 * The bundle of the app is `Agent Caffeine.app` from 1.0.2. It was
 * `agent caffeine.app` in 1.0.0 and 1.0.1, and an update keeps that name,
 * so a text may still name the earlier bundle.
 */
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

test("both names of the bundle pass, and the lowercase brand does not", () => {
  const rest = (line: string) => MACHINE_NAMES.reduce((text, name) => text.replaceAll(name, ""), line).replaceAll("Agent Caffeine", "");
  assert.equal(/agent\s+caffeine/i.test(rest("ls /Applications/Agent Caffeine.app /Applications/agent caffeine.app")), false);
  assert.equal(/agent\s+caffeine/i.test(rest("open agent caffeine from Applications")), true);
});
