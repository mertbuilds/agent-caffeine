import Link from "next/link";

export function Footer() {
  return (
    <footer className="mx-auto flex w-full max-w-[1120px] flex-col items-center justify-between gap-2 border-t border-border py-8 text-sm text-muted sm:flex-row">
      <span>agent caffeine · 2026</span>
      <Link href="/blog">Blog</Link>
      <span>
        Made by{" "}
        <a href="https://mertbuilds.com/?utm_source=caffeinagent.com&utm_medium=referral&utm_campaign=footer">
          mertbuilds.com
        </a>
      </span>
    </footer>
  );
}
