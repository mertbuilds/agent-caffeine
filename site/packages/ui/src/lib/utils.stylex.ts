import type { StyleXStyles } from '@stylexjs/stylex';

export const customClassName = (className: string | undefined) =>
  className ? ({ $$css: true, [className]: className } as StyleXStyles) : null;
