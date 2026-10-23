'use client';

import { Separator as SeparatorPrimitive } from '@base-ui/react/separator';
import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import { colors } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const styles = create({
  horizontal: {
    height: '1px',
    width: '100%',
  },
  root: {
    backgroundColor: colors.border,
    flexShrink: 0,
  },
  vertical: {
    alignSelf: 'stretch',
    width: '1px',
  },
});

export type SeparatorProps = Omit<SeparatorPrimitive.Props, 'style'> & {
  className?: string | undefined;
  style?: StyleXStyles | undefined;
};

const Separator = ({ className, orientation = 'horizontal', style, ...props }: SeparatorProps) => (
  <SeparatorPrimitive
    data-slot="separator"
    orientation={orientation}
    {...stylexProps(
      styles.root,
      orientation === 'vertical' ? styles.vertical : styles.horizontal,
      customClassName(className),
      style,
    )}
    {...props}
  />
);

export { Separator, styles as separatorStyles };
