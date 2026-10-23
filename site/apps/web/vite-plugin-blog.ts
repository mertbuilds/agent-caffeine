import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import matter from 'gray-matter';
import { marked } from 'marked';
import type { Plugin } from 'vite';

/**
 * The blog's articles in content/blog/*.md, read and rendered at build time, so
 * the Worker reads no files and the browser parses no Markdown. Two virtual
 * modules: `virtual:blog/index` (what a list of posts shows, small enough for
 * every page) and `virtual:blog/posts` (each body as HTML, for the post page).
 * Their types are in src/blog.d.ts.
 */
const INDEX_ID = 'virtual:blog/index';
const POSTS_ID = 'virtual:blog/posts';
const DIR = join(import.meta.dirname, 'content/blog');

function text(data: Record<string, unknown>, key: string, file: string): string {
  const value = data[key];
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`${file}: missing ${key}`);
  }
  return value;
}

/** YAML reads a bare 2026-10-05 as a Date; keep every date as that plain day. */
function day(value: unknown, key: string, file: string): string {
  if (typeof value === 'object' && value !== null && 'toISOString' in value) {
    return String(Reflect.apply(Date.prototype.toISOString, value, [])).slice(0, 10);
  }
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/u.test(value)) {
    return value;
  }
  throw new Error(`${file}: ${key} must be a YYYY-MM-DD date`);
}

function faq(value: unknown, file: string): Array<{ a: string; q: string }> {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new Error(`${file}: faq must be a list`);
  }
  return value.map((item: unknown, index) => {
    if (typeof item !== 'object' || item === null) {
      throw new Error(`${file}: faq[${index}] must have q and a`);
    }
    const entry = { ...item };
    return {
      a: text(entry, 'a', `${file} faq[${index}]`),
      q: text(entry, 'q', `${file} faq[${index}]`),
    };
  });
}

function split(html: string, file: string): [string, string] {
  const parts = html.split('<!-- faq -->');
  if (parts.length > 2) {
    throw new Error(`${file}: more than one <!-- faq --> marker`);
  }
  return [parts[0] ?? '', parts[1] ?? ''];
}

/** A table gets a box of its own, so a wide one scrolls inside it and not the page. */
function scrollTables(html: string): string {
  return html
    .replaceAll(
      '<table>',
      '<div class="table-scroll" tabindex="0" role="region" aria-label="Table"><table>',
    )
    .replaceAll('</table>', '</table></div>');
}

/** Inline HTML to the plain text a reader sees, for structured data. */
function plain(html: string): string {
  return html
    .replaceAll(/<[^>]+>/gu, '')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');
}

function readPosts() {
  return readdirSync(DIR)
    .filter((file) => file.endsWith('.md'))
    .map((file) => {
      const { content, data } = matter(readFileSync(join(DIR, file), 'utf8'));
      return {
        date: day(data['date'], 'date', file),
        description: text(data, 'description', file),
        faq: faq(data['faq'], file).map(({ a, q }) => {
          const html = marked.parseInline(a, { async: false });
          return { html, q, text: plain(html) };
        }),
        html: split(scrollTables(marked.parse(content, { async: false })), file),
        slug: file.replace(/\.md$/u, ''),
        title: text(data, 'title', file),
        updated: day(data['updated'] ?? data['date'], 'updated', file),
      };
    })
    .toSorted((a, b) => b.date.localeCompare(a.date));
}

export function blog(): Plugin {
  return {
    load(id) {
      if (id !== `\0${INDEX_ID}` && id !== `\0${POSTS_ID}`) {
        return null;
      }
      for (const file of readdirSync(DIR)) {
        this.addWatchFile(join(DIR, file));
      }
      const posts = readPosts();
      if (id === `\0${INDEX_ID}`) {
        const index = posts.map(({ date, description, slug, title, updated }) => ({
          date,
          description,
          slug,
          title,
          updated,
        }));
        return `export default ${JSON.stringify(index)};`;
      }
      const bodies = Object.fromEntries(posts.map(({ faq, html, slug }) => [slug, { faq, html }]));
      return `export default ${JSON.stringify(bodies)};`;
    },
    name: 'caffeinagent:blog',
    resolveId(id) {
      return id === INDEX_ID || id === POSTS_ID ? `\0${id}` : null;
    },
  };
}
