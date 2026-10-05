import { useId } from "react";

const EYES = "M5.5 11.1q1.25-2.1 2.5 0M10 11.1q1.25-2.1 2.5 0";

type MenuIconProps = {
  className?: string;
  /** Whether the Mac is held awake; a number from 0 to 1 crossfades the two states. */
  held: boolean | number;
};

/** The app's menu bar icon, a robot head: solid while it holds the Mac awake, an outline asleep. */
export function MenuIcon({ className, held }: MenuIconProps) {
  const mask = `menu-icon-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const level = typeof held === "number" ? held : held ? 1 : 0;
  return (
    <svg aria-hidden="true" className={className} fill="currentColor" viewBox="0 0 18 18">
      {level > 0 && (
        <>
          <mask id={mask}>
            <rect fill="#fff" height="18" width="18" />
            <path d={EYES} fill="none" stroke="#000" strokeLinecap="round" strokeWidth={1.35} />
          </mask>
          <g mask={`url(#${mask})`} opacity={level}>
            <circle cx="9" cy="2.3" r="1.35" />
            <rect height="2.6" width="1.2" x="8.4" y="3" />
            <rect height="10.3" rx="4.6" width="12.8" x="2.6" y="5.2" />
            <rect height="3.4" rx="1" width="2" x="0.9" y="8.6" />
            <rect height="3.4" rx="1" width="2" x="15.1" y="8.6" />
          </g>
        </>
      )}
      {level < 1 && (
        <g fill="none" opacity={1 - level} stroke="currentColor" strokeLinecap="round">
          <circle cx="9" cy="2.3" r="0.9" strokeWidth={1.1} />
          <path d="M9 3.3v2" strokeLinecap="butt" strokeWidth={1.1} />
          <rect height="9.1" rx="4" strokeWidth={1.25} width="11.6" x="3.2" y="5.8" />
          <path d="M1.6 9v2.6M16.4 9v2.6" strokeWidth={1.25} />
          <path d="M5.5 10.6h2.5M10 10.6h2.5" strokeWidth={1.3} />
        </g>
      )}
    </svg>
  );
}
