import type { Metadata } from "next";
import Link from "next/link";
import { Footer } from "@/components/footer";
import { Header } from "@/components/header";
import { formatDate, getPosts } from "@/lib/blog";

const title = "Blog · agent caffeine";
const description =
  "Guides on keeping a Mac awake: the caffeinate command, sleep settings, closed-lid use and long runs of AI coding agents.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/blog" },
  openGraph: { title, description, type: "website", url: "/blog", images: ["/og.png"] },
  twitter: { card: "summary_large_image", title, description, images: ["/og.png"] },
};

export default function BlogIndex() {
  const posts = getPosts();
  return (
    <main className="relative isolate flex min-h-screen flex-col gap-16 overflow-x-clip px-4 md:px-6">
      <Header />
      <section className="mx-auto flex w-full max-w-[680px] flex-1 flex-col gap-10">
        <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em]">
          Blog
        </h1>
        <ul className="flex flex-col">
          {posts.map((post) => (
            <li key={post.slug} className="border-t border-border py-6 first:border-t-0 first:pt-0">
              <Link href={`/blog/${post.slug}`} className="group flex flex-col gap-2 no-underline">
                <span className="text-pretty text-xl font-medium leading-snug group-hover:underline">
                  {post.title}
                </span>
                <span className="text-pretty leading-relaxed text-muted">{post.description}</span>
                <time dateTime={post.date} className="text-sm text-muted">
                  {formatDate(post.date)}
                </time>
              </Link>
            </li>
          ))}
        </ul>
      </section>
      <Footer />
    </main>
  );
}
