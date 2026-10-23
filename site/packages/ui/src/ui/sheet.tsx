'use client';

import { Drawer } from '@base-ui/react/drawer';
import { create, props as stylexProps } from '@stylexjs/stylex';
import { XIcon } from 'lucide-react';
import type { ReactElement, ReactNode } from 'react';
import { colors, controlHeight, radius } from '../lib/tokens.stylex.ts';
import { Button } from './button.tsx';

// The popup reaches this far below the viewport, so dragging it up past its
// resting place never shows a gap under it.
const BLEED = '3rem';
const EASING = 'cubic-bezier(0.32, 0.72, 0, 1)';

const styles = create({
  backdrop: {
    backdropFilter: 'blur(4px)',
    backgroundColor: 'color-mix(in oklab, black 10%, transparent)',
    inset: 0,
    minHeight: '100dvh',
    // Fades with the swipe, so the page comes back as the sheet goes down.
    opacity: {
      ':is([data-starting-style], [data-ending-style])': 0,
      default: 'calc(1 - var(--drawer-swipe-progress))',
    },
    position: 'fixed',
    transitionDuration: {
      ':is([data-ending-style])': 'calc(var(--drawer-swipe-strength) * 400ms)',
      ':is([data-swiping])': '0ms',
      default: '450ms',
    },
    transitionProperty: 'opacity',
    transitionTimingFunction: EASING,
    WebkitBackdropFilter: 'blur(4px)',
    zIndex: 50,
  },
  close: {
    // Square icon button with a 40px hit area, as on the dialog.
    '::before': {
      inset: '-6px',
    },
    height: controlHeight.sm,
    paddingInline: 0,
    width: controlHeight.sm,
  },
  content: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.75rem',
    marginInline: 'auto',
    maxWidth: '32rem',
    width: '100%',
  },
  // The grabber says the sheet can be swiped down; the whole popup takes the drag.
  handle: {
    backgroundColor: colors.border,
    borderRadius: radius.full,
    flexShrink: 0,
    height: '0.25rem',
    marginInline: 'auto',
    width: '2.25rem',
  },
  header: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.75rem',
    justifyContent: 'space-between',
  },
  popup: {
    backgroundColor: colors.popover,
    borderTopLeftRadius: radius.md,
    borderTopRightRadius: radius.md,
    boxShadow: `0 0 0 1px color-mix(in oklab, ${colors.foreground} 10%, transparent)`,
    color: colors.popoverForeground,
    display: 'flex',
    flexDirection: 'column',
    fontSize: '0.875rem',
    gap: '0.75rem',
    lineHeight: '1.25rem',
    marginBottom: `calc(-1 * ${BLEED})`,
    // Never so tall that the page behind is gone: the rest scrolls inside.
    maxHeight: `calc(80dvh + ${BLEED})`,
    outline: 'none',
    overflowY: 'auto',
    overscrollBehavior: 'contain',
    paddingBottom: `calc(1.5rem + env(safe-area-inset-bottom, 0px) + ${BLEED})`,
    paddingInline: '1rem',
    paddingTop: '0.5rem',
    transform: {
      ':is([data-starting-style], [data-ending-style])': `translateY(calc(100% - ${BLEED} + 2px))`,
      default: 'translateY(var(--drawer-swipe-movement-y))',
    },
    transitionDuration: {
      ':is([data-ending-style])': 'calc(var(--drawer-swipe-strength) * 400ms)',
      ':is([data-swiping])': '0ms',
      default: '450ms',
    },
    transitionProperty: 'transform',
    transitionTimingFunction: EASING,
    userSelect: {
      ':is([data-swiping])': 'none',
      default: null,
    },
    width: '100%',
  },
  title: {
    fontFamily: 'inherit',
    fontSize: '1rem',
    fontWeight: 500,
    lineHeight: '1.5rem',
    margin: 0,
  },
  viewport: {
    alignItems: 'flex-end',
    display: 'flex',
    inset: 0,
    justifyContent: 'center',
    position: 'fixed',
    zIndex: 50,
  },
});

export type SheetProps = {
  children: ReactNode;
  /** Accessible name of the close button. */
  closeLabel: string;
  onOpenChange?:
    | ((open: boolean, eventDetails: Drawer.Root.ChangeEventDetails) => void)
    | undefined;
  title: string;
  /** The button that opens the sheet. */
  trigger: ReactElement<Record<string, unknown>>;
};

/**
 * The phone shape of a popup: it comes up from the bottom edge over a dimmed
 * page, and goes back down on a swipe, the backdrop, Escape or the close
 * button. A popup pinned to a trigger runs off the side of a phone; this
 * cannot.
 */
const Sheet = ({ children, closeLabel, onOpenChange, title, trigger }: SheetProps) => (
  <Drawer.Root onOpenChange={onOpenChange}>
    <Drawer.Trigger render={trigger} />
    <Drawer.Portal>
      <Drawer.Backdrop {...stylexProps(styles.backdrop)} />
      <Drawer.Viewport {...stylexProps(styles.viewport)}>
        <Drawer.Popup data-slot="sheet" {...stylexProps(styles.popup)}>
          <div aria-hidden="true" {...stylexProps(styles.handle)} />
          <Drawer.Content {...stylexProps(styles.content)}>
            <div {...stylexProps(styles.header)}>
              <Drawer.Title {...stylexProps(styles.title)}>{title}</Drawer.Title>
              <Drawer.Close
                aria-label={closeLabel}
                render={<Button style={styles.close} variant="ghost" />}
              >
                <XIcon size={16} />
              </Drawer.Close>
            </div>
            {children}
          </Drawer.Content>
        </Drawer.Popup>
      </Drawer.Viewport>
    </Drawer.Portal>
  </Drawer.Root>
);

export { Sheet };
