import { useId } from "react";
import type { IconLook } from "@/lib/simulator";

const AWAKE: IconLook = { eyes: "happy", opacity: 1 };
const ASLEEP: IconLook = { eyes: "closed", opacity: 1 };

const FADE = "transition-opacity duration-fast ease-smooth-out motion-reduce:transition-none";
const EYES = [6, 12];

type MenuIconProps = {
  className?: string;
  /** Whether the Mac is held awake. */
  held?: boolean;
  /** The state to draw, in place of `held`. */
  look?: IconLook;
};

/**
 * The app's menu bar icon, the robot's head on a 21 x 20 canvas, with the
 * measures of `UI/MenuBarIcon.swift`: an outline head whose eyes tell the
 * state, grey when the app is off or paused, red crosses in trouble. Every
 * state is in the drawing, so a change crossfades.
 */
export function MenuIcon({ className, held = true, look }: MenuIconProps) {
  const id = `menu-icon-${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const shown = look ?? (held ? AWAKE : ASLEEP);
  const eyes = (kind: IconLook["eyes"]) => ({ className: FADE, opacity: shown.eyes === kind ? 1 : 0 });
  return (
    <svg aria-hidden="true" className={className} fill="currentColor" viewBox="0 0 21 20">
      <mask id={`${id}-ears`}>
        <rect fill="#fff" height="20" width="21" />
        <rect fill="#000" height="14" rx="6" width="17" x="2" y="4" />
      </mask>
      <g className={FADE} opacity={shown.opacity}>
        <circle cx="10.5" cy="1.5" r="1.5" />
        <rect height="3" width="1" x="10" y="1.5" />
        <g mask={`url(#${id}-ears)`}>
          <rect height="5" rx="1.5" width="3" x="0" y="8.5" />
          <rect height="5" rx="1.5" width="3" x="18" y="8.5" />
        </g>
        {/* `MenuBarIcon.outlineAlways`: the head is an outline in every state. */}
        <rect fill="none" height="13" rx="5.5" stroke="currentColor" width="16" x="2.5" y="4.5" />
        <g fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.2" {...eyes("happy")}>
          {EYES.map((x) => (
            <path key={x} d={`M${x} 12Q${x + 1.5} 8.6 ${x + 3} 12`} />
          ))}
        </g>
        <g {...eyes("open")}>
          {EYES.map((x) => (
            <circle key={x} cx={x + 1.5} cy="11" r="1.25" />
          ))}
        </g>
        <g {...eyes("closed")}>
          {EYES.map((x) => (
            <rect key={x} height="1" width="3" x={x} y="10.5" />
          ))}
        </g>
        <g fill="none" strokeLinecap="round" strokeWidth="1.1" style={{ stroke: "light-dark(#ff3b30, #ff453a)" }} {...eyes("dead")}>
          {EYES.map((x) => (
            <path key={x} d={`M${x + 0.25} 9.75l2.5 2.5M${x + 2.75} 9.75l-2.5 2.5`} />
          ))}
        </g>
      </g>
    </svg>
  );
}
