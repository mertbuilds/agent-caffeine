import { useId } from "react";

const BODY = "M1 1.5 H8 V4.5 Q8 7.5 4.5 7.5 Q1 7.5 1 4.5 Z";
const HANDLE = "M8 2.5 H9 Q10.5 2.5 10.5 4 Q10.5 5.5 9 5.5 H8";
const SAUCER = "M0 9.5 H11";
const LINE = { strokeWidth: 1.5, vectorEffect: "non-scaling-stroke" } as const;

/** The menu bar cup, drawn in the current colour and filled with the accent as far as `full`. */
export function Cup({ className, full }: { className?: string; full: number }) {
  const clip = `cup-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const level = 6 * full;
  return (
    <svg
      aria-hidden="true"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeLinecap="round"
      strokeLinejoin="round"
      viewBox="-0.5 0 12 10.5"
    >
      <clipPath id={clip}>
        <path d={BODY} />
      </clipPath>
      <rect
        clipPath={`url(#${clip})`}
        fill="var(--accent)"
        height={level}
        stroke="none"
        width={7}
        x={1}
        y={7.5 - level}
      />
      <path d={BODY} {...LINE} />
      <path d={HANDLE} {...LINE} />
      <path d={SAUCER} {...LINE} />
    </svg>
  );
}
