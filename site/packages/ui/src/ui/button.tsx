'use client';

import type { Button as ButtonPrimitive } from '@base-ui/react/button';
import { mergeProps } from '@base-ui/react/merge-props';
import { useRender } from '@base-ui/react/use-render';
import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import type { MouseEvent } from 'react';
import { colors, controlHeight, radius } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const styles = create({
  base: {
    // Single size: a pill at the default control height (36px), the same as
    // Input. The ::before pseudo-element extends the hit area to 40px
    // (make-interfaces-feel-better minimum) without visual bulk.
    '::before': {
      content: '',
      inset: '-2px',
      position: 'absolute',
    },
    ':is(svg)': {
      flexShrink: 0,
      height: '1rem',
      pointerEvents: 'none',
      width: '1rem',
    },
    alignItems: 'center',
    backgroundClip: 'padding-box',
    borderRadius: radius.full,
    borderStyle: 'none',
    borderWidth: 0,
    boxShadow: {
      ':focus-visible': `0 0 0 3px color-mix(in oklab, ${colors.ring} 50%, transparent)`,
      default: null,
    },
    cursor: {
      ':disabled': 'not-allowed',
      default: 'pointer',
    },
    display: 'inline-flex',
    flexShrink: 0,
    fontFamily: 'inherit',
    // Same text size and side padding as Input, so a field and its button match.
    fontSize: '0.875rem',
    fontWeight: 500,
    gap: '0.25rem',
    height: controlHeight.default,
    justifyContent: 'center',
    opacity: {
      ':disabled': 0.5,
      default: 1,
    },
    outline: 'none',
    paddingInline: '1rem',
    pointerEvents: {
      ':disabled': 'none',
      default: null,
    },
    position: 'relative',
    // Buttons often render as <a> via the `render` prop — kill the anchor underline.
    textDecorationLine: 'none',
    // Tactile press feedback: 0.96 per interface-polish rules; CSS transition
    // stays interruptible mid-animation.
    scale: {
      ':active': '0.96',
      default: '1',
    },
    transitionDuration: '150ms',
    // Never `all` — list only what actually animates.
    transitionProperty: 'scale, background-color, border-color, color, box-shadow, opacity',
    transitionTimingFunction: 'cubic-bezier(0.2, 0, 0, 1)',
    userSelect: 'none',
    whiteSpace: 'nowrap',
  },
  default: {
    backgroundColor: {
      ':hover': `color-mix(in oklab, ${colors.primary} 80%, transparent)`,
      default: colors.primary,
    },
    color: colors.primaryForeground,
  },
  destructive: {
    // Dark mode follows prefers-color-scheme (theme.css), hence media queries,
    // not a `.dark` class.
    backgroundColor: {
      ':hover': {
        '@media (prefers-color-scheme: dark)': `color-mix(in oklab, ${colors.destructive} 30%, transparent)`,
        default: `color-mix(in oklab, ${colors.destructive} 20%, transparent)`,
      },
      '@media (prefers-color-scheme: dark)': `color-mix(in oklab, ${colors.destructive} 20%, transparent)`,
      default: `color-mix(in oklab, ${colors.destructive} 10%, transparent)`,
    },
    boxShadow: {
      ':focus-visible': {
        '@media (prefers-color-scheme: dark)': `0 0 0 3px color-mix(in oklab, ${colors.destructive} 40%, transparent)`,
        default: `0 0 0 3px color-mix(in oklab, ${colors.destructive} 20%, transparent)`,
      },
      default: null,
    },
    color: colors.destructive,
  },
  // A link-rendered Button has no :disabled state, so it gets the same look
  // from a style applied in render.
  disabledLink: {
    opacity: 0.5,
    pointerEvents: 'none',
  },
  ghost: {
    backgroundColor: {
      ':hover': {
        '@media (prefers-color-scheme: dark)': `color-mix(in oklab, ${colors.muted} 50%, transparent)`,
        default: colors.muted,
      },
      default: 'transparent',
    },
    color: {
      ':hover': colors.foreground,
      default: 'inherit',
    },
  },
  link: {
    backgroundColor: 'transparent',
    color: colors.primary,
    textDecorationLine: {
      ':hover': 'underline',
      default: 'none',
    },
    textUnderlineOffset: '4px',
  },
  outline: {
    backgroundColor: {
      ':hover': {
        '@media (prefers-color-scheme: dark)': `color-mix(in oklab, ${colors.input} 50%, transparent)`,
        default: colors.muted,
      },
      '@media (prefers-color-scheme: dark)': `color-mix(in oklab, ${colors.input} 30%, transparent)`,
      default: colors.background,
    },
    borderColor: {
      '@media (prefers-color-scheme: dark)': colors.input,
      default: colors.border,
    },
    borderStyle: 'solid',
    borderWidth: '1px',
    color: {
      ':hover': colors.foreground,
      default: 'inherit',
    },
  },
  secondary: {
    backgroundColor: {
      ':hover': `color-mix(in oklch, ${colors.secondary}, ${colors.foreground} 5%)`,
      default: colors.secondary,
    },
    color: colors.secondaryForeground,
  },
});

export type ButtonVariant = 'default' | 'destructive' | 'outline' | 'secondary' | 'ghost' | 'link';

const variantStyles: Record<ButtonVariant, StyleXStyles> = {
  default: styles.default,
  destructive: styles.destructive,
  ghost: styles.ghost,
  link: styles.link,
  outline: styles.outline,
  secondary: styles.secondary,
};

export type ButtonProps = Omit<ButtonPrimitive.Props, 'style'> & {
  className?: string;
  style?: StyleXStyles;
  variant?: ButtonVariant;
};

// A link has no native disabled state: take it out of the tab order and cancel
// activation in the capture phase, before any onClick (including a router
// Link's own navigation handler) runs.
const disabledLinkProps = {
  'aria-disabled': true,
  onClickCapture: (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
  },
  tabIndex: -1,
};

const Button = ({
  className,
  disabled = false,
  render,
  // Without a `render` prop this is a <button>; with one, pass
  // `nativeButton` when the rendered element is still a <button>.
  nativeButton = render === undefined,
  style,
  variant = 'default',
  ...restProps
}: ButtonProps) => {
  const styleProps = stylexProps(
    styles.base,
    variantStyles[variant],
    disabled && !nativeButton && styles.disabledLink,
    customClassName(className),
    style,
  );

  let elementProps;
  if (nativeButton) {
    // Never submit a surrounding form by accident, also when `render` swaps in
    // another <button>; an explicit `type` in restProps still wins.
    elementProps = { disabled, type: 'button' as const };
  } else if (disabled) {
    elementProps = disabledLinkProps;
  }

  return useRender({
    defaultTagName: 'button',
    props: mergeProps(
      {
        className: styleProps.className,
        'data-slot': 'button',
        'data-variant': variant,
        style: styleProps.style,
      },
      elementProps,
      restProps,
    ),
    render,
    state: {
      disabled,
      slot: 'button' as const,
      variant,
    },
  });
};

export { Button, styles as buttonStyles };
