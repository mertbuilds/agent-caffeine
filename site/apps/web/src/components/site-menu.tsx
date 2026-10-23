import {
  breakpoints,
  colors,
  motion as tokens,
  radius,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { AnimatePresence, motion } from 'motion/react';
import { useEffect, useId, useRef, useState, type FocusEvent, type RefObject } from 'react';
import type { Release } from '../lib/latest-release.ts';
import { distance, duration, easing, scale } from '../lib/motion.ts';
import { useLessMotion } from '../lib/use-less-motion.ts';
import { m } from '../paraglide/messages.js';
import { DownloadLink, TryFree } from './download-button.tsx';

export type MenuLink = { current: boolean; href: string; label: string };

/** How far the page may run under an open menu before the menu closes, in pixels. */
const SCROLL_CLOSE = 24;
/** The width the header's own links come back at, and the menu goes. */
const WIDE_QUERY = '(min-width: 768px)';
const PANEL_OFFSET = 8;
const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';

function isNode(target: EventTarget | null): target is Node {
  return target !== null && 'nodeType' in target;
}

const styles = create({
  button: {
    '::before': {
      content: "''",
      inset: `calc(-1 * ${spacing.s2})`,
      position: 'absolute',
    },
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: radius.full,
    borderWidth: 0,
    color: { ':hover': colors.fg, default: colors.muted },
    cursor: 'pointer',
    display: { [breakpoints.md]: 'none', default: 'flex' },
    flexShrink: 0,
    height: spacing.s7,
    justifyContent: 'center',
    justifySelf: 'end',
    padding: 0,
    position: 'relative',
    width: spacing.s7,
  },
  buttonOpen: {
    color: colors.fg,
  },
  divider: {
    backgroundColor: colors.border,
    height: '1px',
    marginBlock: spacing.s2,
  },
  // The two lines of the button: apart while closed, crossed while open.
  line: {
    backgroundColor: 'currentColor',
    borderRadius: '1px',
    height: '1.5px',
    position: 'absolute',
    transitionDuration: { default: tokens.durationQuick, [LESS_MOTION]: '0s' },
    transitionProperty: 'transform',
    transitionTimingFunction: tokens.easeSmoothOut,
    width: spacing.s4,
  },
  lineBottom: {
    transform: 'translate(0, 3.5px) rotate(0deg)',
  },
  lineBottomOpen: {
    transform: 'translate(0, 0) rotate(-45deg)',
  },
  lineOpen: {
    transitionDuration: { default: tokens.durationFast, [LESS_MOTION]: '0s' },
  },
  lineTop: {
    transform: 'translate(0, -3.5px) rotate(0deg)',
  },
  lineTopOpen: {
    transform: 'translate(0, 0) rotate(45deg)',
  },
  links: {
    display: 'flex',
    flexDirection: 'column',
  },
  panel: {
    backgroundColor: colors.bg,
    borderColor: `color-mix(in srgb, ${colors.fg} 10%, transparent)`,
    borderRadius: radius.xl2,
    borderStyle: 'solid',
    borderWidth: '1px',
    boxShadow: `0 8px 32px ${colors.shadow}`,
    boxSizing: 'border-box',
    color: colors.fg,
    display: { [breakpoints.md]: 'none', default: 'flex' },
    flexDirection: 'column',
    left: spacing.s4,
    outline: 'none',
    overflowY: 'auto',
    overscrollBehavior: 'contain',
    paddingBottom: spacing.s4,
    paddingInline: spacing.s4,
    paddingTop: spacing.s2,
    pointerEvents: 'auto',
    position: 'fixed',
    right: spacing.s4,
    zIndex: 40,
  },
  // One row of the menu, tall enough for a thumb.
  row: {
    alignItems: 'center',
    color: colors.fg,
    display: 'flex',
    fontSize: text.base,
    gap: spacing.s2,
    lineHeight: text.baseLeading,
    minHeight: '2.75rem',
    outlineOffset: { ':focus-visible': '-2px', default: null },
    textDecorationLine: 'none',
  },
});

/**
 * The header's menu on a narrow window: the button of two lines at the
 * header's far edge, and the panel it opens under the header, in the open
 * strip and in the pill alike. The lines cross as it opens, the panel comes
 * down from the button and its items follow a step apart; it closes quicker
 * than it opens. A link, Escape, a press outside it, focus leaving it, the
 * page running on under it or a wider window all close it. Focus goes into
 * the panel, and back to the button on Escape or a link. The page behind
 * stays free to scroll: this is a panel, not a sheet.
 */
export function SiteMenu({
  anchor,
  links,
  morph,
  release,
}: {
  /** The header's row, which the panel hangs under. */
  anchor: RefObject<HTMLElement | null>;
  links: ReadonlyArray<MenuLink>;
  /** The name the header's morph carries the button by. */
  morph: string;
  /** The release the menu's last row downloads. Without one the menu has only its links. */
  release: Release | null;
}) {
  const [top, setTop] = useState<number | null>(null);
  const open = top !== null;
  const button = useRef<HTMLButtonElement>(null);
  const panel = useRef<HTMLDivElement>(null);
  const id = useId();
  const lessMotion = useLessMotion();

  function close(refocus: boolean) {
    setTop(null);
    if (refocus) {
      button.current?.focus({ preventScroll: true });
    }
  }

  function toggle() {
    if (open) {
      close(false);
      return;
    }
    const row = anchor.current?.getBoundingClientRect();
    setTop((row?.bottom ?? 0) + PANEL_OFFSET);
  }

  useEffect(() => {
    if (!open) {
      return;
    }
    panel.current?.focus({ preventScroll: true });
    const from = window.scrollY;
    const shut = () => setTop(null);
    const onScroll = () => {
      if (Math.abs(window.scrollY - from) > SCROLL_CLOSE) {
        shut();
      }
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        shut();
        button.current?.focus({ preventScroll: true });
      }
    };
    const onPress = (event: PointerEvent) => {
      const target = event.target;
      if (!isNode(target)) {
        return;
      }
      if (panel.current?.contains(target) || button.current?.contains(target)) {
        return;
      }
      shut();
    };
    const wide = window.matchMedia(WIDE_QUERY);
    window.addEventListener('scroll', onScroll, { passive: true });
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onPress);
    wide.addEventListener('change', shut);
    return () => {
      window.removeEventListener('scroll', onScroll);
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onPress);
      wide.removeEventListener('change', shut);
    };
  }, [open]);

  function onBlur(event: FocusEvent<HTMLDivElement>) {
    const next = event.relatedTarget;
    if (!isNode(next)) {
      return;
    }
    if (panel.current?.contains(next) || button.current?.contains(next)) {
      return;
    }
    close(false);
  }

  const ease = easing.smoothOut;
  const line = [styles.line, open && styles.lineOpen];

  return (
    <>
      <button
        aria-controls={open ? id : undefined}
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-label={open ? m.menu_close() : m.menu_open()}
        data-morph={morph}
        onClick={toggle}
        ref={button}
        type="button"
        {...props(styles.button, open && styles.buttonOpen)}
        style={{ viewTransitionName: morph }}
      >
        <span aria-hidden="true" {...props(line, open ? styles.lineTopOpen : styles.lineTop)} />
        <span
          aria-hidden="true"
          {...props(line, open ? styles.lineBottomOpen : styles.lineBottom)}
        />
      </button>
      <AnimatePresence>
        {top === null ? null : (
          <motion.div
            animate={{
              opacity: 1,
              scale: 1,
              transition: { duration: lessMotion ? 0 : duration.fast, ease },
              y: 0,
            }}
            aria-label={m.menu_label()}
            className={props(styles.panel).className}
            exit={{
              opacity: 0,
              scale: scale.tiny,
              transition: { duration: lessMotion ? 0 : duration.quick, ease },
            }}
            id={id}
            initial={{ opacity: 0, scale: scale.medium, y: -distance.base }}
            onBlur={onBlur}
            ref={panel}
            role="dialog"
            style={{
              maxHeight: `calc(100dvh - ${top + PANEL_OFFSET}px)`,
              top,
              transformOrigin: 'top right',
            }}
            tabIndex={-1}
          >
            <nav aria-label={m.menu_label()} {...props(styles.links)}>
              {links.map((link, place) => (
                <a
                  aria-current={link.current ? 'location' : undefined}
                  className={`menu-item-in ${props(styles.row).className ?? ''}`}
                  href={link.href}
                  key={link.href}
                  onClick={() => close(true)}
                  style={{ animationDelay: `${place * duration.stagger}s` }}
                >
                  {link.label}
                </a>
              ))}
            </nav>
            {release === null ? null : (
              <>
                <div aria-hidden="true" {...props(styles.divider)} />
                <div
                  className="menu-item-in"
                  onClick={() => close(false)}
                  style={{ animationDelay: `${links.length * duration.stagger}s` }}
                >
                  <DownloadLink placement="header" release={release} style={styles.row}>
                    <TryFree />
                  </DownloadLink>
                </div>
              </>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
}
