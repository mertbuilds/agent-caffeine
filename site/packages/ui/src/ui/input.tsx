'use client';

import { Input as InputPrimitive } from '@base-ui/react/input';
import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import type { ComponentProps } from 'react';
import { colors, controlHeight, radius } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const styles = create({
  ariaInvalid: {
    borderColor: colors.destructive,
    boxShadow: `0 0 0 3px color-mix(in oklab, ${colors.destructive} 20%, transparent)`,
  },
  root: {
    '::file-selector-button': {
      backgroundColor: 'transparent',
      borderWidth: 0,
      color: colors.foreground,
      display: 'inline-flex',
      fontSize: '0.875rem',
      fontWeight: 500,
      height: '1.5rem',
    },
    '::placeholder': {
      color: colors.mutedForeground,
    },
    // iOS Safari otherwise paints its own inner shadow on text inputs.
    appearance: 'none',
    backgroundColor: {
      ':disabled': `color-mix(in oklab, ${colors.input} 50%, transparent)`,
      default: 'transparent',
    },
    borderColor: {
      ':focus-visible': colors.ring,
      default: colors.input,
    },
    borderRadius: radius.full,
    borderStyle: 'solid',
    borderWidth: '1px',
    boxShadow: {
      ':focus-visible': `0 0 0 3px color-mix(in oklab, ${colors.ring} 50%, transparent)`,
      default: 'none',
    },
    color: colors.foreground,
    cursor: {
      ':disabled': 'not-allowed',
      default: 'auto',
    },
    fontFamily: 'inherit',
    fontSize: '0.875rem',
    height: controlHeight.default,
    lineHeight: '1.25rem',
    minWidth: 0,
    opacity: {
      ':disabled': 0.5,
      default: 1,
    },
    outline: 'none',
    paddingBlock: '0.25rem',
    paddingInline: '1rem',
    pointerEvents: {
      ':disabled': 'none',
      default: null,
    },
    transitionDuration: '150ms',
    transitionProperty: 'color, background-color, border-color, box-shadow',
    transitionTimingFunction: 'cubic-bezier(0.2, 0, 0, 1)',
    width: '100%',
  },
});

export type InputProps = Omit<ComponentProps<'input'>, 'style'> & {
  style?: StyleXStyles;
};

const Input = ({ 'aria-invalid': ariaInvalid, className, style, type, ...props }: InputProps) => (
  <InputPrimitive
    aria-invalid={ariaInvalid}
    data-slot="input"
    type={type}
    {...stylexProps(
      styles.root,
      ariaInvalid && ariaInvalid !== 'false' && styles.ariaInvalid,
      customClassName(className),
      style as StyleXStyles,
    )}
    {...props}
  />
);

export { Input };
