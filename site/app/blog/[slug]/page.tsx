import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { BuyButton } from "@/components/buy-button";
import { Footer } from "@/components/footer";
import { Header } from "@/components/header";
import { JsonLd } from "@/components/json-ld";
import { formatDate, getPost, getPosts } from "@/lib/blog";
import { AUTHOR, ORGANIZATION, SITE_URL } from "@/lib/site";

type Props = { params: Promise<{ slug: string }> };

export const dynamicParams = false;

export function generateStaticParams() {
  return getPosts().map((post) => ({ slug: post.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const post = getPost((await params).slug);
  if (post === undefined) return {};
  const url = `/blog/${post.slug}`;
  return {
    title: post.title,
    description: post.description,
    alternates: { canonical: url },
    openGraph: {
      title: post.title,
      description: post.description,
      type: "article",
      url,
      publishedTime: post.date,
      modifiedTime: post.updated,
      authors: [AUTHOR.url],
      images: ["/og.png"],
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description: post.description,
      images: ["/og.png"],
    },
  };
}

export default async function BlogPost({ params }: Props) {
  const post = getPost((await params).slug);
  if (post === undefined) notFound();

  const url = `${SITE_URL}/blog/${post.slug}`;
  const structuredData = {
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "BlogPosting",
        headline: post.title,
        description: post.description,
        datePublished: post.date,
        dateModified: post.updated,
        author: AUTHOR,
        publisher: ORGANIZATION,
        mainEntityOfPage: { "@type": "WebPage", "@id": url },
        url,
        image: `${SITE_URL}/og.png`,
      },
      ...(post.faq.length === 0
        ? []
        : [
            {
              "@type": "FAQPage",
              mainEntity: post.faq.map((item) => ({
                "@type": "Question",
                name: item.q,
                acceptedAnswer: { "@type": "Answer", text: item.text },
              })),
            },
          ]),
    ],
  };

  return (
    <main className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 md:px-6">
      <Header />
      <article className="mx-auto flex w-full min-w-0 max-w-[680px] flex-col gap-10">
        <header className="flex flex-col gap-4">
          <Link href="/blog" className="text-sm text-muted no-underline hover:text-fg">
            Blog
          </Link>
          <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
            {post.title}
          </h1>
          <p className="text-sm text-muted">
            <time dateTime={post.date}>{formatDate(post.date)}</time> · By{" "}
            <a href="https://mertbuilds.com/?utm_source=caffeinagent.com&utm_medium=referral&utm_campaign=blog">
              Mert Duzgun
            </a>
          </p>
        </header>
        <div className="article">
          <div dangerouslySetInnerHTML={{ __html: post.html[0] }} />
          {post.faq.length === 0 ? null : (
            <section>
              <h2>Questions</h2>
              {post.faq.map((item) => (
                <div key={item.q}>
                  <h3>{item.q}</h3>
                  <p dangerouslySetInnerHTML={{ __html: item.html }} />
                </div>
              ))}
            </section>
          )}
          <div dangerouslySetInnerHTML={{ __html: post.html[1] }} />
        </div>
        <aside className="flex flex-col items-start gap-5 rounded-lg border border-border bg-surface px-6 py-8 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-pretty leading-relaxed">
            We built agent caffeine to keep a Mac awake while coding agents work, also with
            the lid closed. $9 once, macOS 13 or later.
          </p>
          <BuyButton placement="blog" size="small">
            Buy · $9
          </BuyButton>
        </aside>
      </article>
      <Footer />
      <JsonLd data={structuredData} />
    </main>
  );
}
