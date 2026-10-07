"use client";

import { useEffect } from "react";

const INPUTS = ["wheel", "touchstart", "keydown", "pointerdown"] as const;

/** Puts the section the address names at the top, under the header, with no glide. */
function jump() {
  const id = window.location.hash.slice(1);
  if (id === "") return;
  document.getElementById(id)?.scrollIntoView({ behavior: "instant", block: "start" });
}

/**
 * A page opened at a section, as the app's buy and help links open it, lands
 * there at once. A glide on load is stopped half way when the page hydrates,
 * so jumps are eased (app/globals.css) only from here on. The page can still
 * grow above the section while fonts and pictures land, so the jump is made
 * once more when they have, unless the reader has moved by then. A reload or
 * a step back keeps the place the reader was at, so only a new visit jumps.
 */
export function HashScroll() {
  useEffect(() => {
    document.documentElement.dataset.smoothScroll = "";
    const [entry] = performance.getEntriesByType("navigation") as PerformanceNavigationTiming[];
    if (entry?.type !== "navigate") return;
    jump();
    let live = true;
    const stop = () => {
      live = false;
    };
    for (const input of INPUTS) window.addEventListener(input, stop, { once: true, passive: true });
    const loaded = new Promise<void>((resolve) => {
      if (document.readyState === "complete") resolve();
      else window.addEventListener("load", () => resolve(), { once: true });
    });
    void Promise.all([document.fonts.ready, loaded]).then(() => {
      requestAnimationFrame(() => {
        if (live) jump();
      });
    });
    return () => {
      stop();
      for (const input of INPUTS) window.removeEventListener(input, stop);
    };
  }, []);
  return null;
}
