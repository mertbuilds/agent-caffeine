"use client";

import { AnimatePresence, motion } from "motion/react";
import Link from "next/link";
import { useEffect, useId, useRef, useState, type FocusEvent, type RefObject } from "react";
import { DownloadForMac } from "@/components/download-button";
import { GitHubMark } from "@/components/github-mark";
import { DownloadCta, GitHubCta } from "@/components/track";
import { distance, duration, easing, scale } from "@/lib/motion";
import type { Release } from "@/lib/release";
import { useLessMotion } from "@/lib/use-less-motion";

export type MenuLink = { current: boolean; href: string; label: string; onClick?: () => void };

/** How far the page may run under an open menu before the menu closes, in pixels. */
const SCROLL_CLOSE = 24;
/** The width the header's own links come back at, and the menu goes. */
const WIDE_QUERY = "(min-width: 768px)";
const PANEL_OFFSET = 8;

/** One row of the menu, tall enough for a thumb. */
const ROW = "flex min-h-11 items-center gap-2 text-base text-fg no-underline focus-visible:outline-offset-[-2px]";

/**
 * The header's menu on a narrow window: the button of two lines at the
 * header's far edge, and the panel it opens under the header, in the open
 * strip and in the pill alike. The lines cross as it opens, the panel comes
 * down from the button and its items follow a step apart; it closes quicker
 * than it opens. A link, Escape, a press outside it, focus leaving it, the
 * page running on under it or a wider window all close it. Focus goes into
 * the panel, and back to the button on Escape or a link. The page behind
 * stays free to scroll: this is a panel, not a sheet.
 */
export function SiteMenu({
  anchor,
  links,
  morph,
  release,
}: {
  /** The header's row, which the panel hangs under. */
  anchor: RefObject<HTMLElement | null>;
  links: ReadonlyArray<MenuLink>;
  /** The name the header's morph carries the button by. */
  morph: string;
  /** The release the menu's last row downloads. Without one the menu has only its links and GitHub. */
  release: Release | null;
}) {
  const [top, setTop] = useState<number | null>(null);
  const open = top !== null;
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const id = useId();
  const lessMotion = useLessMotion();

  function close(refocus: boolean) {
    setTop(null);
    if (refocus) button.current?.focus({ preventScroll: true });
  }

  function toggle() {
    if (open) {
      close(false);
      return;
    }
    const row = anchor.current?.getBoundingClientRect();
    setTop((row?.bottom ?? 0) + PANEL_OFFSET);
  }

  useEffect(() => {
    if (!open) return;
    panel.current?.focus({ preventScroll: true });
    const from = window.scrollY;
    const onScroll = () => {
      if (Math.abs(window.scrollY - from) > SCROLL_CLOSE) close(false);
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") close(true);
    };
    const onPress = (event: PointerEvent) => {
      const target = event.target;
      if (!(target instanceof Node)) return;
      if (panel.current?.contains(target) || button.current?.contains(target)) return;
      close(false);
    };
    const onWide = () => close(false);
    const wide = window.matchMedia(WIDE_QUERY);
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPress);
    wide.addEventListener("change", onWide);
    return () => {
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPress);
      wide.removeEventListener("change", onWide);
    };
  }, [open]);

  function onBlur(event: FocusEvent<HTMLDivElement>) {
    const next = event.relatedTarget;
    if (!(next instanceof Node)) return;
    if (panel.current?.contains(next) || button.current?.contains(next)) return;
    close(false);
  }

  const ease = easing.smoothOut;
  const line = `absolute h-[1.5px] w-4 rounded-[1px] bg-current transition-transform ease-smooth-out motion-reduce:duration-0 ${
    open ? "duration-fast" : "duration-quick"
  }`;

  return (
    <>
      <button
        ref={button}
        type="button"
        aria-controls={open ? id : undefined}
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-label={open ? "Close menu" : "Open menu"}
        data-morph={morph}
        onClick={toggle}
        style={{ viewTransitionName: morph }}
        className={`relative flex size-7 shrink-0 cursor-pointer items-center justify-center justify-self-end rounded-full border-0 bg-transparent p-0 before:absolute before:-inset-2 before:content-[''] hover:text-fg md:hidden ${
          open ? "text-fg" : "text-muted"
        }`}
      >
        <span aria-hidden="true" className={`${line} ${open ? "rotate-45" : "-translate-y-[3.5px]"}`} />
        <span aria-hidden="true" className={`${line} ${open ? "-rotate-45" : "translate-y-[3.5px]"}`} />
      </button>
      <AnimatePresence>
        {top === null ? null : (
          <motion.div
            ref={panel}
            id={id}
            role="dialog"
            aria-label="Menu"
            tabIndex={-1}
            onBlur={onBlur}
            initial={{ opacity: 0, y: -distance.base, scale: scale.medium }}
            animate={{ opacity: 1, y: 0, scale: 1, transition: { duration: lessMotion ? 0 : duration.fast, ease } }}
            exit={{ opacity: 0, scale: scale.tiny, transition: { duration: lessMotion ? 0 : duration.quick, ease } }}
            style={{ top, maxHeight: `calc(100dvh - ${top + PANEL_OFFSET}px)`, transformOrigin: "top right" }}
            className="pointer-events-auto fixed inset-x-4 z-40 box-border flex flex-col overflow-y-auto overscroll-contain rounded-2xl border border-[color:color-mix(in_srgb,var(--fg)_10%,transparent)] bg-bg px-4 pb-4 pt-2 text-fg shadow-[0_8px_32px_var(--shadow)] outline-none md:hidden"
          >
            <nav aria-label="Menu" className="flex flex-col">
              {links.map((link, place) => (
                <Link
                  key={link.href}
                  href={link.href}
                  aria-current={link.current ? "location" : undefined}
                  onClick={() => {
                    link.onClick?.();
                    close(true);
                  }}
                  className={`menu-item-in ${ROW}`}
                  style={{ animationDelay: `${place * duration.stagger}s` }}
                >
                  {link.label}
                </Link>
              ))}
              <div
                className="menu-item-in"
                onClick={() => close(false)}
                style={{ animationDelay: `${links.length * duration.stagger}s` }}
              >
                <GitHubCta placement="menu" className={ROW}>
                  <GitHubMark size={16} />
                  GitHub
                </GitHubCta>
              </div>
            </nav>
            {release !== null ? (
              <>
                <div aria-hidden="true" className="my-2 h-px bg-border" />
                <div
                  className="menu-item-in"
                  onClick={() => close(false)}
                  style={{ animationDelay: `${(links.length + 1) * duration.stagger}s` }}
                >
                  <DownloadCta href={release.href} filename={release.filename} placement="header" className={ROW}>
                    <DownloadForMac />
                  </DownloadCta>
                </div>
              </>
            ) : null}
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
