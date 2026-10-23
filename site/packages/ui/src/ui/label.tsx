'use client';

import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import type { ComponentProps } from 'react';
import { customClassName } from '../lib/utils.stylex.ts';

const styles = create({
  disabled: {
    cursor: 'not-allowed',
    opacity: 0.5,
  },
  root: {
    alignItems: 'center',
    color: 'inherit',
    display: 'flex',
    fontSize: '0.875rem',
    fontWeight: 500,
    gap: '0.5rem',
    lineHeight: 1,
    userSelect: 'none',
  },
});

export type LabelProps = Omit<ComponentProps<'label'>, 'style'> & {
  'data-disabled'?: boolean | string;
  style?: StyleXStyles;
};

const Label = ({ className, style, ...props }: LabelProps) => {
  const isDisabled =
    props['data-disabled'] === true ||
    props['data-disabled'] === '' ||
    props['data-disabled'] === 'true' ||
    props['aria-disabled'] === true ||
    props['aria-disabled'] === 'true';

  return (
    <label
      data-slot="label"
      {...stylexProps(
        styles.root,
        isDisabled && styles.disabled,
        customClassName(className),
        style,
      )}
      {...props}
    />
  );
};

export { Label };
