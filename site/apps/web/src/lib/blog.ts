import index from 'virtual:blog/index';
import { PRICE } from './pricing.ts';

/** What a list of posts shows: newest first. */
export type PostSummary = (typeof index)[number];

export type Post = PostSummary & {
  faq: ReadonlyArray<{ html: string; q: string; text: string }>;
  /** The body split where `<!-- faq -->` stands, so the questions render from the frontmatter. */
  html: readonly [string, string];
};

/** A post names the price as {{price}}, so it follows lib/pricing.ts. */
function withPrice(text: string): string {
  return text.replaceAll('{{price}}', PRICE);
}

function summary(post: PostSummary): PostSummary {
  return { ...post, description: withPrice(post.description), title: withPrice(post.title) };
}

export function getPosts(): ReadonlyArray<PostSummary> {
  return index.map(summary);
}

/** One post with its body. The bodies load on their own, so a page that only lists posts never carries them. */
export async function getPost(slug: string): Promise<Post | undefined> {
  const post = index.find((entry) => entry.slug === slug);
  if (post === undefined) {
    return undefined;
  }
  const { default: bodies } = await import('virtual:blog/posts');
  const body = bodies[slug];
  if (body === undefined) {
    return undefined;
  }
  return {
    ...summary(post),
    faq: body.faq.map((item) => ({
      html: withPrice(item.html),
      q: withPrice(item.q),
      text: withPrice(item.text),
    })),
    html: [withPrice(body.html[0]), withPrice(body.html[1])],
  };
}

export function formatDate(date: string): string {
  return new Date(`${date}T00:00:00Z`).toLocaleDateString('en-US', {
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
    year: 'numeric',
  });
}
