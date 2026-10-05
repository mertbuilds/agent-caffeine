"use client";

import { useRef, useSyncExternalStore, type KeyboardEvent, type ReactNode } from "react";
import {
  applyTheme,
  readTheme,
  serverTheme,
  subscribeTheme,
  THEME_CHOICES,
  type ThemeChoice,
} from "@/lib/theme";

const ICON_PROPS = {
  width: 14,
  height: 14,
  viewBox: "0 0 14 14",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.25,
  strokeLinecap: "round",
  strokeLinejoin: "round",
  "aria-hidden": true,
} as const;

const OPTIONS: Record<ThemeChoice, { label: string; icon: ReactNode }> = {
  system: {
    label: "System theme",
    icon: (
      <svg {...ICON_PROPS}>
        <rect x="1.5" y="2" width="11" height="7.5" rx="1.5" />
        <path d="M7 9.5v2.5M4.5 12h5" />
      </svg>
    ),
  },
  light: {
    label: "Light theme",
    icon: (
      <svg {...ICON_PROPS}>
        <circle cx="7" cy="7" r="2.5" />
        <path d="M7 1v1.25M7 11.75V13M1 7h1.25M11.75 7H13M2.76 2.76l.88.88M10.36 10.36l.88.88M2.76 11.24l.88-.88M10.36 3.64l.88-.88" />
      </svg>
    ),
  },
  dark: {
    label: "Dark theme",
    icon: (
      <svg {...ICON_PROPS}>
        <path d="M11.75 8.6A5 5 0 0 1 5.4 2.25a5 5 0 1 0 6.35 6.35Z" />
      </svg>
    ),
  },
};

/**
 * The picked segment is drawn by `.theme-pick` in globals.css from `data-theme` on `<html>`,
 * so it is right from the first paint; `aria-checked` and the tab stop follow after hydration.
 */
export function ThemeSwitch() {
  const theme = useSyncExternalStore(subscribeTheme, readTheme, serverTheme);
  const buttons = useRef<(HTMLButtonElement | null)[]>([]);

  function onKeyDown(event: KeyboardEvent, index: number) {
    const count = THEME_CHOICES.length;
    let next: number;
    switch (event.key) {
      case "ArrowRight":
      case "ArrowDown":
        next = (index + 1) % count;
        break;
      case "ArrowLeft":
      case "ArrowUp":
        next = (index - 1 + count) % count;
        break;
      case "Home":
        next = 0;
        break;
      case "End":
        next = count - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    applyTheme(THEME_CHOICES[next]);
    buttons.current[next]?.focus();
  }

  return (
    <div
      role="radiogroup"
      aria-label="Theme"
      className="flex h-7 shrink-0 items-center gap-0.5 rounded-full border border-border p-px"
    >
      {THEME_CHOICES.map((choice, index) => (
        <button
          key={choice}
          ref={(button) => {
            buttons.current[index] = button;
          }}
          type="button"
          role="radio"
          aria-checked={choice === theme}
          aria-label={OPTIONS[choice].label}
          title={OPTIONS[choice].label}
          tabIndex={choice === theme ? 0 : -1}
          data-theme-pick={choice}
          onClick={() => applyTheme(choice)}
          onKeyDown={(event) => onKeyDown(event, index)}
          className="theme-pick relative flex size-6 items-center justify-center rounded-full text-muted transition-colors duration-quick ease-smooth-out before:absolute before:inset-x-0 before:-inset-y-2.5 before:content-[''] hover:text-fg motion-reduce:transition-none"
        >
          {OPTIONS[choice].icon}
        </button>
      ))}
    </div>
  );
}
