"use client";

import { clamp, cubicBezier, easeInOut } from "motion/react";
import { drawing, easing } from "@/lib/motion";
import { HAIRLINE } from "../parts";
import { type StepProps, stepBox, useStep } from "./use-step";

const smoothOut = cubicBezier(...easing.smoothOut);

/** The process list's window, the bar along its top, and the three buttons in it. */
const WINDOW = { height: 132, radius: 6, width: 168, x: 36, y: 24 };
const TITLE_BAR = 14;
const BUTTONS = { left: 10, pitch: 8, radius: 2 };
/** One row per process: how far one stands from the next, its name as a bar, and its load at the right. */
const PITCH = 21;
const BAR = 3;
const ROWS = [
  { load: 10, name: 40 },
  { agent: "claude", load: 14, name: 30 },
  { load: 8, name: 52 },
  { agent: "codex", load: 16, name: 34 },
  { load: 12, name: 46 },
];
const DOT_X = WINDOW.x + 12;
const NAME_X = WINDOW.x + 20;
const LOAD_RIGHT = WINDOW.x + WINDOW.width - 12;
const LABEL_GAP = 6;
const LIST_TOP = WINDOW.y + TITLE_BAR + (WINDOW.height - TITLE_BAR - ROWS.length * PITCH) / 2;
/** The highlight runs down the list, coming in before and going out after. */
const SCAN = [0.3, 2.6] as const;
const SCAN_IN = [0.1, 0.4] as const;
const SCAN_OUT = [2.5, 2.9] as const;
const SCAN_OPACITY = 0.12;
/** Cropped wider than the laptop steps, so the window weighs about as much as a laptop. */
const BOX = stepBox(256, WINDOW.y + WINDOW.height);

/** The middle of row `row` from the top of the box. */
function rowY(row: number): number {
  return LIST_TOP + PITCH * (row + 0.5);
}

/** How far an agent's row is marked once the highlight stands `scan` rows down, a little after it has reached it. */
function marked(scan: number, row: number, after: number): number {
  return smoothOut(clamp(0, 1, (scan - row + 0.25 - after) / 0.75));
}

/**
 * A process list, and a highlight that runs down it. The two rows that are
 * agents get an accent dot and turn to the page's colour as it reaches them;
 * the rest stay muted.
 */
export function SeesDrawing({ play, ref }: StepProps) {
  const { span } = useStep(play, drawing.stepSees);
  const scan = span(SCAN, easeInOut) * (ROWS.length - 1);
  const band = span(SCAN_IN) * (1 - span(SCAN_OUT));

  return (
    <svg
      ref={ref}
      aria-label="A list of running processes. Two of them, Claude and Codex, are marked as agents"
      className="block aspect-[4/3] h-auto w-full"
      role="img"
      viewBox={BOX}
    >
      <rect
        height={WINDOW.height}
        rx={WINDOW.radius}
        width={WINDOW.width}
        x={WINDOW.x}
        y={WINDOW.y}
        {...HAIRLINE}
      />
      <path
        d={`M${WINDOW.x} ${WINDOW.y + TITLE_BAR} H${WINDOW.x + WINDOW.width}`}
        opacity={0.5}
        {...HAIRLINE}
      />
      {[0, 1, 2].map((button) => (
        <circle
          key={button}
          cx={WINDOW.x + BUTTONS.left + button * BUTTONS.pitch}
          cy={WINDOW.y + TITLE_BAR / 2}
          opacity={0.5}
          r={BUTTONS.radius}
          {...HAIRLINE}
        />
      ))}
      <rect
        fill="var(--hairline)"
        height={PITCH - 4}
        opacity={SCAN_OPACITY * band}
        rx={3}
        width={WINDOW.width - 8}
        x={WINDOW.x + 4}
        y={LIST_TOP + PITCH * scan + 2}
      />
      {ROWS.map((row, index) => {
        const y = rowY(index);
        const mark = row.agent === undefined ? 0 : marked(scan, index, 0);
        const label = row.agent === undefined ? 0 : marked(scan, index, 0.2);
        return (
          <g key={index}>
            <rect
              fill="var(--hairline)"
              fillOpacity={0.5}
              height={BAR}
              rx={BAR / 2}
              width={row.name}
              x={NAME_X}
              y={y - BAR / 2}
            />
            <rect
              fill="var(--hairline)"
              fillOpacity={0.5}
              height={BAR}
              rx={BAR / 2}
              width={row.load}
              x={LOAD_RIGHT - row.load}
              y={y - BAR / 2}
            />
            {row.agent === undefined ? null : (
              <>
                <rect
                  fill="var(--fg)"
                  height={BAR}
                  opacity={mark}
                  rx={BAR / 2}
                  width={row.name}
                  x={NAME_X}
                  y={y - BAR / 2}
                />
                <circle
                  cx={DOT_X}
                  cy={y}
                  fill="var(--accent)"
                  opacity={mark}
                  r={1.8 * (0.4 + 0.6 * mark)}
                />
                <text
                  fill="var(--fg)"
                  fontSize={7}
                  fontWeight={500}
                  opacity={label}
                  x={NAME_X + row.name + LABEL_GAP - 2 * (1 - label)}
                  y={y + 2.5}
                >
                  {row.agent}
                </text>
              </>
            )}
          </g>
        );
      })}
    </svg>
  );
}
