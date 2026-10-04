import type { Ref } from "react";
import { stretch, usePlayhead } from "@/lib/playhead";
import { BASE_BOTTOM, crop } from "../parts";

type Span = readonly [from: number, to: number];

/** What every step's drawing takes: whether it plays, and the ref its turn is seen by. */
export type StepProps = { play: boolean; ref?: Ref<SVGSVGElement> | undefined };

/**
 * The clock of a step that plays once over `seconds` each time `play` turns
 * on. `span` reads how far the part played between `from` and `to` seconds
 * has got.
 */
export function useStep(play: boolean, seconds: number) {
  const at = usePlayhead(play, seconds);
  const span = ([from, to]: Span, ease?: (share: number) => number) =>
    stretch(at, from / seconds, to / seconds, ease);
  const lines = (spans: readonly Span[]) => spans.reduce((sum, part) => sum + span(part), 0);
  return { lines, span };
}

/** How far down its box each step's drawing stands, so the three stand on one line. */
const GROUND = 0.84;

/** A step's crop, `width` wide, with the drawing that ends at `bottom` standing on the line. */
export function stepBox(width: number, bottom: number): string {
  return crop(width, bottom, GROUND);
}

/** The crop the laptop steps show, the laptop's base about three quarters of it across. */
export const LAPTOP_BOX = stepBox(196, BASE_BOTTOM);
