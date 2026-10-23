/** `code`, or [text](href). */
const MARK = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/gu;

export type RichPart =
  | { kind: 'code'; text: string }
  | { href: string; kind: 'link'; text: string }
  | { kind: 'text'; text: string };

/**
 * A message's text cut at its marks: `code` in backticks and links written as
 * [text](href), the two pieces of Markdown the site's copy uses.
 * `components/rich.tsx` renders them.
 */
export function richParts(text: string): ReadonlyArray<RichPart> {
  const parts: Array<RichPart> = [];
  let last = 0;
  for (const match of text.matchAll(MARK)) {
    if (match.index > last) {
      parts.push({ kind: 'text', text: text.slice(last, match.index) });
    }
    const [whole, code, label, href] = match;
    parts.push(
      code === undefined
        ? { href: href ?? '', kind: 'link', text: label ?? '' }
        : { kind: 'code', text: code },
    );
    last = match.index + whole.length;
  }
  if (last < text.length) {
    parts.push({ kind: 'text', text: text.slice(last) });
  }
  return parts;
}
