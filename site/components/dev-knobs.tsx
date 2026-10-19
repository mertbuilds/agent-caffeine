"use client";

import dynamic from "next/dynamic";

// Dev-only: the knobs panel (scheme, motion, device width) and grab (hold cmd+C on an element).
const Knobs =
  process.env.NODE_ENV === "development"
    ? dynamic(() => import("devknobs/react").then((m) => m.DevKnobs), { ssr: false })
    : null;

export function DevKnobs() {
  return Knobs ? <Knobs /> : null;
}
