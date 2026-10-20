import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";
import { ThemeSwitch } from "@/components/theme-switch";
import { GitHubMark } from "@/components/github-mark";
import { DownloadCta, GitHubCta } from "@/components/track";
import { getPosts } from "@/lib/blog";
import { getLatestRelease } from "@/lib/release";
import { CONTACT_EMAIL } from "@/lib/site";

const LINK =
  "text-muted no-underline transition-colors duration-quick ease-smooth-out hover:text-fg motion-reduce:transition-none";

/** A five-pointed star on a 16-unit grid. */
const STAR = "M8 1.5l1.9 4.1 4.5.5-3.35 3 .95 4.4L8 11.25 4 13.5l.95-4.4-3.35-3 4.5-.5z";

function Column({ title, className = "", children }: { title: string; className?: string; children: ReactNode }) {
  return (
    <nav aria-label={title} className={`flex flex-col gap-4 ${className}`}>
      <h2>{title}</h2>
      <ul className="flex flex-col gap-3">{children}</ul>
    </nav>
  );
}

export async function Footer() {
  const release = await getLatestRelease();
  const posts = getPosts();
  return (
    <footer className="mx-auto flex w-full max-w-[1120px] flex-col gap-14 border-t border-border pb-10 pt-12 text-sm md:pt-16">
      <div className="grid grid-flow-row-dense grid-cols-2 gap-x-8 gap-y-10 sm:grid-flow-row sm:grid-cols-3 md:grid-cols-[minmax(0,1.4fr)_repeat(3,minmax(0,1fr))]">
        <div className="col-span-2 flex flex-col gap-3 sm:col-span-3 md:col-span-1">
          <Link href="/" className="flex w-fit items-center gap-2 text-base font-medium no-underline">
            <Image src="/icon.png" alt="" width={28} height={28} />
            <span>Agent Caffeine</span>
          </Link>
          <p className="text-pretty text-muted">Keeps your Mac awake while your agents work</p>
          <ul className="flex flex-col gap-3 pt-1">
            <li>
              <GitHubCta placement="footer" className={`${LINK} inline-flex items-center gap-2`}>
                <GitHubMark size={14} />
                GitHub
              </GitHubCta>
            </li>
            <li>
              <GitHubCta placement="footer" className={`${LINK} group inline-flex items-center gap-2`}>
                {/* The star fills in while the link is pointed at, where a pointer can point. */}
                <span className="relative flex shrink-0">
                  <svg aria-hidden="true" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.25" strokeLinejoin="round">
                    <path d={STAR} />
                  </svg>
                  <svg
                    aria-hidden="true"
                    width="14"
                    height="14"
                    viewBox="0 0 16 16"
                    fill="currentColor"
                    stroke="currentColor"
                    strokeWidth="1.25"
                    strokeLinejoin="round"
                    className="absolute inset-0 opacity-0 transition-opacity duration-quick ease-smooth-out motion-reduce:transition-none [@media(hover:hover)]:group-hover:opacity-100"
                  >
                    <path d={STAR} />
                  </svg>
                </span>
                Give us a star
              </GitHubCta>
            </li>
          </ul>
        </div>
        <Column title="Product">
          <li>
            <Link href="/#examples" className={LINK}>
              Examples
            </Link>
          </li>
          <li>
            <Link href="/#agents" className={LINK}>
              Agents
            </Link>
          </li>
          <li>
            <Link href="/#features" className={LINK}>
              Features
            </Link>
          </li>
          <li>
            <Link href="/#demo" className={LINK}>
              Demo
            </Link>
          </li>
          {release === null ? null : (
            <li>
              <DownloadCta href={release.href} filename={release.filename} placement="footer" className={LINK}>
                Download for macOS
              </DownloadCta>
            </li>
          )}
          <li>
            <Link href="/#faq" className={LINK}>
              FAQ
            </Link>
          </li>
          <li>
            <Link href="/compare" className={LINK}>
              Compare
            </Link>
          </li>
          <li>
            <Link href="/#support" className={LINK}>
              Support
            </Link>
          </li>
        </Column>
        <Column title="Read" className="col-span-2 sm:col-span-1">
          <li>
            <Link href="/blog" className={LINK}>
              Blog
            </Link>
          </li>
          {posts.map((post) => (
            <li key={post.slug}>
              <Link href={`/blog/${post.slug}`} className={`${LINK} text-pretty`}>
                {post.title}
              </Link>
            </li>
          ))}
        </Column>
        <Column title="Legal">
          <li>
            <Link href="/privacy" className={LINK}>
              Privacy
            </Link>
          </li>
          <li>
            <Link href="/terms" className={LINK}>
              Terms
            </Link>
          </li>
          <li>
            <a href={`mailto:${CONTACT_EMAIL}`} className={LINK}>
              Contact
            </a>
          </li>
        </Column>
      </div>
      <div className="flex items-center justify-between gap-4">
        <p className="text-muted">
          a{" "}
          <a href="https://mertbuilds.com/?utm_source=caffeinagent.com&utm_medium=referral&utm_campaign=footer">
            mertbuilds.com
          </a>{" "}
          utility
        </p>
        <ThemeSwitch />
      </div>
    </footer>
  );
}
