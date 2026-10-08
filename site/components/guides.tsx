import Link from "next/link";
import { getPosts } from "@/lib/blog";

/** Every guide of the blog, one click from the home page. */
export function Guides() {
  return (
    <section aria-labelledby="guides" className="mx-auto flex w-full max-w-[640px] flex-col gap-6">
      <h2 id="guides" className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
        Guides
      </h2>
      <ul>
        {getPosts().map((post) => (
          <li key={post.slug} className="border-t border-border first:border-t-0">
            <Link
              href={`/blog/${post.slug}`}
              className="block py-4 text-pretty leading-normal no-underline transition-colors duration-quick ease-smooth-out hover:text-muted motion-reduce:transition-none"
            >
              {post.title}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
