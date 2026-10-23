import { colors, motion, radius, spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { useRef, useSyncExternalStore, type KeyboardEvent, type ReactNode } from 'react';
import {
  applyTheme,
  readTheme,
  serverTheme,
  subscribeTheme,
  THEME_CHOICES,
  type ThemeChoice,
} from '../lib/theme.ts';
import { m } from '../paraglide/messages.js';

const ICON_PROPS = {
  'aria-hidden': true,
  fill: 'none',
  height: 14,
  stroke: 'currentColor',
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
  strokeWidth: 1.25,
  viewBox: '0 0 14 14',
  width: 14,
} as const;

const OPTIONS: Record<ThemeChoice, { icon: ReactNode; label: () => string }> = {
  dark: {
    icon: (
      <svg {...ICON_PROPS}>
        <path d="M11.75 8.6A5 5 0 0 1 5.4 2.25a5 5 0 1 0 6.35 6.35Z" />
      </svg>
    ),
    label: () => m.theme_dark(),
  },
  light: {
    icon: (
      <svg {...ICON_PROPS}>
        <circle cx="7" cy="7" r="2.5" />
        <path d="M7 1v1.25M7 11.75V13M1 7h1.25M11.75 7H13M2.76 2.76l.88.88M10.36 10.36l.88.88M2.76 11.24l.88-.88M10.36 3.64l.88-.88" />
      </svg>
    ),
    label: () => m.theme_light(),
  },
  system: {
    icon: (
      <svg {...ICON_PROPS}>
        <rect height="7.5" rx="1.5" width="11" x="1.5" y="2" />
        <path d="M7 9.5v2.5M4.5 12h5" />
      </svg>
    ),
    label: () => m.theme_system(),
  },
};

const styles = create({
  choice: {
    // A taller hit area than the 24px button, as tall as the row it sits in.
    '::before': {
      bottom: `calc(-1 * ${spacing.s2_5})`,
      content: "''",
      left: 0,
      position: 'absolute',
      right: 0,
      top: `calc(-1 * ${spacing.s2_5})`,
    },
    alignItems: 'center',
    borderRadius: radius.full,
    color: { ':hover': colors.fg, default: colors.muted },
    display: 'flex',
    height: spacing.s6,
    justifyContent: 'center',
    position: 'relative',
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      '@media (prefers-reduced-motion: reduce)': 'none',
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
    },
    transitionTimingFunction: motion.easeSmoothOut,
    width: spacing.s6,
  },
  group: {
    alignItems: 'center',
    borderColor: colors.border,
    borderRadius: radius.full,
    borderStyle: 'solid',
    borderWidth: '1px',
    display: 'flex',
    flexShrink: 0,
    gap: spacing.s0_5,
    height: spacing.s7,
    padding: '1px',
  },
});

/**
 * The picked segment is drawn by `.theme-pick` in styles/scenes.css from
 * `data-theme` on `<html>`, so it is right from the first paint;
 * `aria-checked` and the tab stop follow after hydration.
 */
export function ThemeSwitch() {
  const theme = useSyncExternalStore(subscribeTheme, readTheme, serverTheme);
  const buttons = useRef<Array<HTMLButtonElement | null>>([]);

  function onKeyDown(event: KeyboardEvent, index: number) {
    const count = THEME_CHOICES.length;
    let next: number;
    switch (event.key) {
      case 'ArrowRight':
      case 'ArrowDown':
        next = (index + 1) % count;
        break;
      case 'ArrowLeft':
      case 'ArrowUp':
        next = (index - 1 + count) % count;
        break;
      case 'Home':
        next = 0;
        break;
      case 'End':
        next = count - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    const choice = THEME_CHOICES[next];
    if (choice !== undefined) {
      applyTheme(choice);
    }
    buttons.current[next]?.focus();
  }

  return (
    <div aria-label={m.theme_label()} role="radiogroup" {...props(styles.group)}>
      {THEME_CHOICES.map((choice, index) => (
        <button
          aria-checked={choice === theme}
          aria-label={OPTIONS[choice].label()}
          className={`theme-pick ${props(styles.choice).className ?? ''}`}
          data-theme-pick={choice}
          key={choice}
          onClick={() => applyTheme(choice)}
          onKeyDown={(event) => onKeyDown(event, index)}
          ref={(button) => {
            buttons.current[index] = button;
          }}
          role="radio"
          tabIndex={choice === theme ? 0 : -1}
          title={OPTIONS[choice].label()}
          type="button"
        >
          {OPTIONS[choice].icon}
        </button>
      ))}
    </div>
  );
}
