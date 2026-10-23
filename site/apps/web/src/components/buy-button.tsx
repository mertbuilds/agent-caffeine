import { colors, motion, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { useSyncExternalStore, type ReactNode } from 'react';
import { checkoutUrlWith } from '../lib/attribution.ts';
import { CHECKOUT_URL, PRICE_NOW } from '../lib/pricing.ts';
import { rememberedUtm, track, type Placement } from '../lib/track.ts';
import { pill } from './pill.ts';

const subscribe = () => () => {};

function onServer(): null {
  return null;
}

const styles = create({
  text: {
    color: { ':hover': colors.fg, default: colors.muted },
    flexShrink: 0,
    fontSize: text.sm,
    lineHeight: text.smLeading,
    textDecorationLine: 'none',
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      '@media (prefers-reduced-motion: reduce)': 'none',
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
    },
    transitionTimingFunction: motion.easeSmoothOut,
  },
});

const SIZES = { compact: pill.compact, large: pill.large, small: pill.small };

const LOOKS = {
  brand: [pill.onBrand, pill.brand],
  brandOutline: [pill.onBrand, pill.brandOutline],
  solid: [pill.base, pill.ink],
};

/**
 * A link to the checkout. The click is counted with the price and where the
 * link sits. The server's link is the plain checkout link; on the live site
 * the browser then adds the visitor's source to it.
 */
export function BuyButton({
  children,
  placement,
  size = 'large',
  variant = 'solid',
}: {
  children: ReactNode;
  placement: Placement;
  size?: keyof typeof SIZES;
  variant?: keyof typeof LOOKS | 'text';
}) {
  const utm = useSyncExternalStore(subscribe, rememberedUtm, onServer);
  return (
    <a
      href={utm === null ? CHECKOUT_URL : checkoutUrlWith(CHECKOUT_URL, utm)}
      onClick={() => track('buy_click', { placement, price: PRICE_NOW })}
      {...props(variant === 'text' ? styles.text : [LOOKS[variant], SIZES[size]])}
    >
      {children}
    </a>
  );
}
