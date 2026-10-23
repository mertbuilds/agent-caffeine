'use client';

import { create, props as stylexProps } from '@stylexjs/stylex';
import { InfoIcon } from 'lucide-react';
import type { ReactNode } from 'react';
import { colors, radius } from '../lib/tokens.stylex.ts';
import { Tip, type TipProps } from './tip.tsx';

// Every size keeps a 24px press. Negative margins give the extra back to the
// line, so the button takes only its icon's room in the layout.
const HIT = 24;
const ICON = { large: 20, small: 14 } as const;

const styles = create({
  button: {
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: radius.full,
    borderStyle: 'none',
    boxShadow: {
      ':focus-visible': `0 0 0 3px color-mix(in oklab, ${colors.ring} 50%, transparent)`,
      default: null,
    },
    color: {
      ':focus-visible': colors.foreground,
      ':hover': colors.foreground,
      default: colors.mutedForeground,
    },
    cursor: 'pointer',
    display: 'inline-flex',
    flexShrink: 0,
    fontFamily: 'inherit',
    height: HIT,
    justifyContent: 'center',
    outline: 'none',
    padding: 0,
    transitionDuration: '150ms',
    transitionProperty: 'color, box-shadow',
    transitionTimingFunction: 'cubic-bezier(0.2, 0, 0, 1)',
    verticalAlign: 'middle',
    width: HIT,
  },
  large: {
    margin: (ICON.large - HIT) / 2,
  },
  small: {
    margin: (ICON.small - HIT) / 2,
  },
});

export type InfoTipProps = {
  /** The explanation behind the icon. */
  children: ReactNode;
  /** Accessible name of the sheet's close button on a phone. */
  closeLabel: string;
  /** Accessible name of the button, and the heading of its popover or sheet. */
  label: string;
  onOpenChange?: TipProps['onOpenChange'];
  /** `large` beside a heading, `small` (default) beside body text or a caption. */
  size?: 'large' | 'small' | undefined;
};

/** A circled "i" beside a line, with the explanation behind it in a Tip. */
const InfoTip = ({ children, closeLabel, label, onOpenChange, size = 'small' }: InfoTipProps) => (
  <Tip
    closeLabel={closeLabel}
    onOpenChange={onOpenChange}
    title={label}
    trigger={
      <button aria-label={label} type="button" {...stylexProps(styles.button, styles[size])}>
        <InfoIcon size={ICON[size]} />
      </button>
    }
  >
    {children}
  </Tip>
);

export { InfoTip };
