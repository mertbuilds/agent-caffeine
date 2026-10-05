import type { Metadata } from "next";
import type { ReactNode } from "react";
import { Footer } from "@/components/footer";
import { formatDate } from "@/lib/blog";

export function legalMetadata(title: string, description: string, path: string): Metadata {
  const fullTitle = `${title} · agent caffeine`;
  return {
    title: fullTitle,
    description,
    alternates: { canonical: path },
    openGraph: { title: fullTitle, description, type: "website", url: path, images: ["/og.png"] },
    twitter: { card: "summary_large_image", title: fullTitle, description, images: ["/og.png"] },
  };
}

export function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
  return (
    <main className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 pt-[6.5rem] md:px-6">
      <article className="mx-auto flex w-full min-w-0 max-w-[680px] flex-1 flex-col gap-10">
        <header className="flex flex-col gap-4">
          <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
            {title}
          </h1>
          <p className="text-sm text-muted">
            Last updated <time dateTime={updated}>{formatDate(updated)}</time>
          </p>
        </header>
        <div className="article">
          <div>{children}</div>
        </div>
      </article>
      <Footer />
    </main>
  );
}
