"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { DownloadButton, WithAppleMark } from "@/components/download-button";
import { SiteMenu } from "@/components/site-menu";
import { morph } from "@/lib/morph";
import type { Release } from "@/lib/release";

/**
 * How far down the page the pill takes over, and how far back up the open
 * header returns. The gap between them keeps a page resting near one line
 * from flipping between the two.
 */
const PILL_FROM = 48;
const OPEN_FROM = 16;

/** The home page's sections in the order they stand. `ids` are the sections a link stands for. */
const SECTIONS = [
  { hash: "#examples", ids: ["examples"], label: "Examples", name: "header-examples" },
  { hash: "#agents", ids: ["agents"], label: "Agents", name: "header-agents" },
  { hash: "#features", ids: ["features", "small-things"], label: "Features", name: "header-features" },
  { hash: "#demo", ids: ["demo"], label: "Demo", name: "header-demo" },
  { hash: "#faq", ids: ["faq"], label: "FAQ", name: "header-faq" },
] as const;

/** The line across the window that a section must lie on to be the one in view: 30% of the way down. */
const VIEW_LINE = "-30% 0px -70% 0px";

/** An item the morph carries, by the name a view transition knows it by. */
function morphName(name: string) {
  return { "data-morph": name, style: { viewTransitionName: name } };
}

/**
 * The name and the way home at the left, the home page's sections in the
 * middle, and the download at the right. The link of the section in
 * view takes the text's own colour. Once the page has
 * run a little way under it, the items gather into a pill in the middle, the
 * mark alone for the name, and open back out near the top. A window too
 * narrow for the links keeps the name and the download, and has the
 * menu's button at the far edge with the links in the menu it opens.
 *
 * The blur sits on a ground of its own behind the items, never on the header
 * or anything around the page, which Safari on iOS can draw wrong.
 */
export function SiteHeader({ release }: { release: Release | null }) {
  const [pill, setPill] = useState(false);
  const bar = useRef<HTMLDivElement>(null);
  const surface = useRef<HTMLSpanElement>(null);
  const mark = useRef<HTMLSpanElement>(null);
  const [inView, setInView] = useState<string | null>(null);
  const pathname = usePathname();
  const links = SECTIONS.map((section) => ({
    current: pathname === "/" && section.hash === inView,
    href: `/${section.hash}`,
    label: section.label,
    name: section.name,
  }));

  // One observer for every section. Between two sections the last one stays
  // in view; above the first there is none.
  useEffect(() => {
    if (pathname !== "/") return;
    const hashes = new Map<Element, string>();
    for (const section of SECTIONS) {
      for (const id of section.ids) {
        const element = document.getElementById(id);
        if (element !== null) hashes.set(element, section.hash);
      }
    }
    const first = document.getElementById(SECTIONS[0].ids[0]);
    const on = new Set<Element>();
    const observer = new IntersectionObserver(
      (entries) => {
        let above = false;
        for (const entry of entries) {
          if (entry.isIntersecting) on.add(entry.target);
          else on.delete(entry.target);
          if (entry.target === first) {
            above = !entry.isIntersecting && entry.boundingClientRect.top > (entry.rootBounds?.top ?? 0);
          }
        }
        const [element] = on;
        if (element !== undefined) setInView(hashes.get(element) ?? null);
        else if (above) setInView(null);
      },
      { rootMargin: VIEW_LINE },
    );
    for (const element of hashes.keys()) observer.observe(element);
    return () => observer.disconnect();
  }, [pathname]);

  // Only a change between the two lines moves anything; the page as it first
  // loads is drawn as it is.
  useEffect(() => {
    let current = false;
    function update(first: boolean) {
      const next = window.scrollY > (current ? OPEN_FROM : PILL_FROM);
      if (next === current) return;
      current = next;
      const root = bar.current;
      const ground = surface.current;
      if (first || root === null || ground === null) {
        setPill(next);
        return;
      }
      morph({
        gather: next,
        live: mark.current === null ? [] : [mark.current],
        root,
        surface: ground,
        update: () => flushSync(() => setPill(next)),
      });
    }
    update(true);
    const onScroll = () => update(false);
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className="pointer-events-none sticky top-0 z-30 -mb-14 grid h-14">
      <div
        ref={bar}
        className={`pointer-events-auto relative box-border items-center ${
          pill
            ? "flex h-10 gap-3 self-center justify-self-center p-1.5 md:gap-6"
            : "grid grid-flow-col auto-cols-auto grid-cols-[minmax(0,1fr)_auto] gap-x-4 px-4 md:grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)]"
        }`}
      >
        {/* The ground behind the row: nothing while the header is open, and the pill once it gathers. */}
        <span
          ref={surface}
          aria-hidden="true"
          className={`pointer-events-none absolute inset-0 box-border border border-[color:color-mix(in_srgb,var(--fg)_10%,transparent)] bg-[color:color-mix(in_srgb,var(--bg)_65%,transparent)] shadow-[0_8px_32px_var(--shadow)] backdrop-blur-[16px] backdrop-saturate-[1.4] [@media(prefers-reduced-transparency:reduce)]:bg-bg [@media(prefers-reduced-transparency:reduce)]:backdrop-filter-none ${
            pill ? "rounded-[20px] opacity-100" : "rounded-none opacity-0"
          }`}
        />
        <Link
          href="/"
          aria-label="Agent Caffeine"
          className={`relative inline-flex min-w-0 max-w-full items-center gap-2 justify-self-start text-sm text-muted no-underline hover:text-fg ${
            pill ? "rounded-full" : ""
          }`}
        >
          <span ref={mark} className={`flex shrink-0 overflow-hidden ${pill ? "rounded-full" : "rounded-[12.5%]"}`}>
            <Image src="/icon.png" alt="" width={28} height={28} priority className={pill ? "size-7" : "size-6"} />
          </span>
          <span {...morphName("header-name")} className={`truncate ${pill ? "hidden" : ""}`}>
            Agent Caffeine
          </span>
        </Link>
        <nav aria-label="Site" className="relative hidden items-center gap-6 md:flex">
          {links.map((link) => (
            <Link
              key={link.name}
              href={link.href}
              aria-current={link.current ? "location" : undefined}
              {...morphName(link.name)}
              className="whitespace-nowrap text-sm text-muted no-underline transition-colors duration-quick ease-[ease-out] hover:text-fg aria-[current=location]:text-fg motion-reduce:transition-none"
            >
              {link.label}
            </Link>
          ))}
        </nav>
        <span className="inline-flex items-center gap-2 justify-self-end">
          {release === null ? null : (
            <span {...morphName("header-primary")} className="inline-flex">
              <DownloadButton release={release} placement="header" size="compact">
                <WithAppleMark>Download</WithAppleMark>
              </DownloadButton>
            </span>
          )}
        </span>
        <SiteMenu anchor={bar} links={links} morph="header-menu" release={release} />
      </div>
    </header>
  );
}
