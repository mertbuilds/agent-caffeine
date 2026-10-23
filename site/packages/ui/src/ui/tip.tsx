'use client';

import type { Drawer } from '@base-ui/react/drawer';
import { Popover } from '@base-ui/react/popover';
import { create, props as stylexProps } from '@stylexjs/stylex';
import type { ReactElement, ReactNode } from 'react';
import { colors, radius } from '../lib/tokens.stylex.ts';
import { useIsMobile } from '../lib/use-is-mobile.ts';
import { Sheet } from './sheet.tsx';

// As long as a Base UI tooltip waits, so a pointer passing over the trigger on
// its way elsewhere opens nothing.
const HOVER_DELAY = 600;

const styles = create({
  // Spaced like the popup, so content in several parts keeps its gaps.
  description: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.25rem',
  },
  popup: {
    backgroundColor: colors.popover,
    borderRadius: radius.md,
    boxShadow: `0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -2px rgba(0, 0, 0, 0.1), 0 0 0 1px color-mix(in oklab, ${colors.foreground} 10%, transparent)`,
    color: colors.mutedForeground,
    display: 'flex',
    flexDirection: 'column',
    fontSize: '0.875rem',
    gap: '0.25rem',
    lineHeight: '1.25rem',
    // Never wider than the viewport, so nothing scrolls sideways.
    maxWidth: 'min(16rem, calc(100vw - 2rem))',
    opacity: {
      ':is([data-starting-style], [data-ending-style])': 0,
      default: 1,
    },
    outline: 'none',
    paddingBlock: '0.5rem',
    paddingInline: '0.75rem',
    transform: {
      ':is([data-starting-style], [data-ending-style])': 'scale(0.95)',
      default: 'scale(1)',
    },
    // It grows out of the side it opens on, toward its trigger.
    transformOrigin: 'var(--transform-origin)',
    transitionDuration: '100ms',
    transitionProperty: 'opacity, transform',
    transitionTimingFunction: 'cubic-bezier(0, 0, 0.2, 1)',
  },
  positioner: {
    zIndex: 50,
  },
  sheetBody: {
    color: colors.mutedForeground,
    display: 'flex',
    flexDirection: 'column',
    gap: '0.75rem',
  },
  // Popover.Title is an h2; this drops the browser's heading size and margins.
  title: {
    color: colors.popoverForeground,
    fontSize: 'inherit',
    fontWeight: 500,
    lineHeight: 'inherit',
    margin: 0,
  },
});

export type TipProps = {
  /** The explanation, in the popover or the sheet. */
  children: ReactNode;
  /** Accessible name of the sheet's close button. */
  closeLabel: string;
  /**
   * Called each time the popover, or the sheet on a phone, opens or closes,
   * with Base UI's details of why (`eventDetails.reason`).
   */
  onOpenChange?:
    | ((
        open: boolean,
        eventDetails: Popover.Root.ChangeEventDetails | Drawer.Root.ChangeEventDetails,
      ) => void)
    | undefined;
  /** Which side of the trigger the popover opens on. */
  side?: Popover.Positioner.Props['side'];
  /** Heading of the popover and of the sheet. */
  title: string;
  /** The element that opens it: a button with its own accessible name. */
  trigger: ReactElement<Record<string, unknown>>;
};

/**
 * A popover where the reader can hover, a bottom sheet where they cannot. On a
 * pointer device it opens when the pointer rests on its trigger, and on a
 * click or Enter, as a dialog named by its title and described by its
 * content. Opened by hover, it closes when the pointer leaves, and the pointer
 * may cross into it on the way; opened any other way, it takes focus and
 * stays until Escape, a press outside or focus leaving. On a phone, where
 * nothing hovers and a popup pinned to its trigger would run off the edge, a
 * tap on the trigger opens a sheet with the same title and content.
 */
const Tip = ({ children, closeLabel, onOpenChange, side = 'top', title, trigger }: TipProps) => {
  const isMobile = useIsMobile();

  if (isMobile) {
    return (
      <Sheet closeLabel={closeLabel} onOpenChange={onOpenChange} title={title} trigger={trigger}>
        <div {...stylexProps(styles.sheetBody)}>{children}</div>
      </Sheet>
    );
  }

  return (
    <Popover.Root onOpenChange={onOpenChange}>
      <Popover.Trigger delay={HOVER_DELAY} openOnHover render={trigger} />
      <Popover.Portal>
        <Popover.Positioner side={side} sideOffset={8} {...stylexProps(styles.positioner)}>
          <Popover.Popup data-slot="tip" {...stylexProps(styles.popup)}>
            <Popover.Title {...stylexProps(styles.title)}>{title}</Popover.Title>
            {/* A div, not the default p: the content may hold blocks of its own. */}
            <Popover.Description render={<div />} {...stylexProps(styles.description)}>
              {children}
            </Popover.Description>
          </Popover.Popup>
        </Popover.Positioner>
      </Popover.Portal>
    </Popover.Root>
  );
};

export { Tip };
