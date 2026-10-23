'use client';

import { create, keyframes, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import type { ComponentProps } from 'react';
import { colors, radius } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const pulseKeyframes = keyframes({
  '0%, 100%': {
    opacity: 1,
  },
  '50%': {
    opacity: 0.5,
  },
});

const styles = create({
  skeleton: {
    animationDuration: '2s',
    animationIterationCount: 'infinite',
    animationName: pulseKeyframes,
    animationTimingFunction: 'cubic-bezier(0.4, 0, 0.6, 1)',
    backgroundColor: colors.muted,
    borderRadius: radius.md,
  },
});

export type SkeletonProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const Skeleton = ({ className, style, ...props }: SkeletonProps) => (
  <div
    data-slot="skeleton"
    {...stylexProps(styles.skeleton, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export { Skeleton };
