import { motion } from '@caffeinagent/ui/tokens.stylex';
import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import { useId } from 'react';
import type { IconLook } from '../lib/simulator.ts';

const EYES = [6, 12];

const styles = create({
  fade: {
    transitionDuration: motion.durationFast,
    transitionProperty: { '@media (prefers-reduced-motion: reduce)': 'none', default: 'opacity' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
});

type MenuIconProps = {
  /** The state to draw. */
  look: IconLook;
  style: StyleXStyles;
};

/**
 * The app's menu bar icon, the robot's head on a 21 x 20 canvas, with the
 * measures of `UI/MenuBarIcon.swift`: an outline head whose eyes tell the
 * state, grey when the app is off or paused, red crosses in trouble. Every
 * state is in the drawing, so a change crossfades.
 */
export function MenuIcon({ look: shown, style }: MenuIconProps) {
  const id = `menu-icon-${useId().replaceAll(/[^a-zA-Z0-9]/g, '')}`;
  const eyes = (kind: IconLook['eyes']) => ({
    ...props(styles.fade),
    opacity: shown.eyes === kind ? 1 : 0,
  });
  return (
    <svg aria-hidden="true" fill="currentColor" viewBox="0 0 21 20" {...props(style)}>
      <mask id={`${id}-ears`}>
        <rect fill="#fff" height="20" width="21" />
        <rect fill="#000" height="14" rx="6" width="17" x="2" y="4" />
      </mask>
      <g {...props(styles.fade)} opacity={shown.opacity}>
        <circle cx="10.5" cy="1.5" r="1.5" />
        <rect height="3" width="1" x="10" y="1.5" />
        <g mask={`url(#${id}-ears)`}>
          <rect height="5" rx="1.5" width="3" x="0" y="8.5" />
          <rect height="5" rx="1.5" width="3" x="18" y="8.5" />
        </g>
        {/* `MenuBarIcon.outlineAlways`: the head is an outline in every state. */}
        <rect fill="none" height="13" rx="5.5" stroke="currentColor" width="16" x="2.5" y="4.5" />
        <g
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeWidth="1.2"
          {...eyes('happy')}
        >
          {EYES.map((x) => (
            <path d={`M${x} 12Q${x + 1.5} 8.6 ${x + 3} 12`} key={x} />
          ))}
        </g>
        <g {...eyes('open')}>
          {EYES.map((x) => (
            <circle cx={x + 1.5} cy="11" key={x} r="1.25" />
          ))}
        </g>
        <g {...eyes('closed')}>
          {EYES.map((x) => (
            <rect height="1" key={x} width="3" x={x} y="10.5" />
          ))}
        </g>
        <g
          {...eyes('dead')}
          fill="none"
          strokeLinecap="round"
          strokeWidth="1.1"
          style={{ stroke: 'light-dark(#ff3b30, #ff453a)' }}
        >
          {EYES.map((x) => (
            <path d={`M${x + 0.25} 9.75l2.5 2.5M${x + 2.75} 9.75l-2.5 2.5`} key={x} />
          ))}
        </g>
      </g>
    </svg>
  );
}
