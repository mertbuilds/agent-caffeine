import fs from "node:fs";
import path from "node:path";
import matter from "gray-matter";
import { marked } from "marked";
import { PRICE } from "@/lib/pricing";

export type Post = {
  slug: string;
  title: string;
  description: string;
  date: string;
  updated: string;
  faq: { q: string; a: string; html: string; text: string }[];
  /** The body split where `<!-- faq -->` stands, so the questions render from the frontmatter. */
  html: [string, string];
};

const DIR = path.join(process.cwd(), "content/blog");

function text(data: Record<string, unknown>, key: string, file: string): string {
  const value = data[key];
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${file}: missing ${key}`);
  return value;
}

/** YAML reads a bare 2026-10-05 as a Date; keep every date as that plain day. */
function day(value: unknown, key: string, file: string): string {
  if (value instanceof Date) return value.toISOString().slice(0, 10);
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  throw new Error(`${file}: ${key} must be a YYYY-MM-DD date`);
}

function faq(value: unknown, file: string): { q: string; a: string }[] {
  if (value === undefined) return [];
  if (!Array.isArray(value)) throw new Error(`${file}: faq must be a list`);
  return value.map((item: unknown, i) => {
    if (typeof item !== "object" || item === null) throw new Error(`${file}: faq[${i}] must have q and a`);
    const entry = { ...item };
    return { q: text(entry, "q", `${file} faq[${i}]`), a: text(entry, "a", `${file} faq[${i}]`) };
  });
}

function split(html: string, file: string): [string, string] {
  const parts = html.split("<!-- faq -->");
  if (parts.length > 2) throw new Error(`${file}: more than one <!-- faq --> marker`);
  return [parts[0], parts[1] ?? ""];
}

/** A table gets a box of its own, so a wide one scrolls inside it and not the page. */
function scrollTables(html: string): string {
  return html.replaceAll("<table>", '<div class="table-scroll" tabindex="0" role="region" aria-label="Table"><table>').replaceAll("</table>", "</table></div>");
}

/** Inline HTML to the plain text a reader sees, for structured data. */
function plain(html: string): string {
  return html
    .replace(/<[^>]+>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, "&");
}

/** Read once per build. Every blog route is static, so this never runs on a request. */
function readPosts(): Post[] {
  return fs
    .readdirSync(DIR)
    .filter((file) => file.endsWith(".md"))
    .map((file) => {
      // A post names the price as {{price}}, so it follows lib/pricing.ts.
      const { data, content } = matter(fs.readFileSync(path.join(DIR, file), "utf8").replaceAll("{{price}}", PRICE));
      return {
        slug: file.replace(/\.md$/, ""),
        title: text(data, "title", file),
        description: text(data, "description", file),
        date: day(data.date, "date", file),
        updated: day(data.updated ?? data.date, "updated", file),
        faq: faq(data.faq, file).map(({ q, a }) => {
          const html = marked.parseInline(a, { async: false });
          return { q, a, html, text: plain(html) };
        }),
        html: split(scrollTables(marked.parse(content, { async: false })), file),
      };
    })
    .sort((a, b) => b.date.localeCompare(a.date));
}

let cache: Post[] | undefined;

export function getPosts(): Post[] {
  cache ??= readPosts();
  return cache;
}

export function getPost(slug: string): Post | undefined {
  return getPosts().find((post) => post.slug === slug);
}

export function formatDate(date: string): string {
  return new Date(`${date}T00:00:00Z`).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric",
    timeZone: "UTC",
  });
}
