import { useRef } from "react";
import { drawing } from "@/lib/motion";
import { stretch, useLoop } from "@/lib/playhead";
import { useSeen } from "@/lib/use-seen";
import { useTabHidden } from "@/lib/use-tab-hidden";
import { crop } from "./parts";

type Span = readonly [from: number, to: number];

/**
 * The first seconds both drawings share, so they read as one scene: lines of
 * work come in on the open laptop, the lid closes, and the display lifts off
 * into a floating panel.
 */
export const OPENING = {
  close: [2.7, 3.8],
  handoff: [2.7, 3.0],
  lift: [2.8, 3.9],
  lines: [
    [0.3, 1.0],
    [1.1, 1.7],
    [1.8, 2.4],
  ],
  live: [0.2, 0.5],
} as const satisfies Record<string, Span | readonly Span[]>;

/** How far above the display the floating panel comes to rest. */
export const LIFT = 20;

/** The crop both drawings show: the laptop's base takes four fifths of it across. */
export const SCENE = crop(180, 24);

/**
 * The clock of a drawing that loops over `seconds` while it is on screen and
 * the tab is in front. `span` reads how far the part played between `from`
 * and `to` seconds has got.
 */
export function useScene(seconds: number) {
  const ref = useRef<SVGSVGElement>(null);
  const seen = useSeen(ref);
  const hidden = useTabHidden();
  const at = useLoop(seen && !hidden, seconds, drawing.rest);
  const span = ([from, to]: Span, ease?: (share: number) => number) =>
    stretch(at, from / seconds, to / seconds, ease);
  const lines = (spans: readonly Span[]) => spans.reduce((sum, part) => sum + span(part), 0);
  return { lines, ref, span };
}
