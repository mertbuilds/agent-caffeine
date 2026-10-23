'use client';

import type { StyleXStyles } from '@stylexjs/stylex';
import { create, props as stylexProps } from '@stylexjs/stylex';
import { useMemo } from 'react';
import type { ComponentProps } from 'react';
import { colors } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';
import { Label } from './label.tsx';
import { Separator } from './separator.tsx';

const styles = create({
  content: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    gap: '0.375rem',
    lineHeight: 1.375,
  },
  description: {
    color: colors.mutedForeground,
    fontSize: '0.875rem',
    fontWeight: 400,
    lineHeight: 1.5,
  },
  error: {
    color: colors.destructive,
    fontSize: '0.875rem',
    fontWeight: 400,
  },
  errorList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.25rem',
  },
  fieldBase: {
    display: 'flex',
    gap: '0.75rem',
    width: '100%',
  },
  group: {
    display: 'flex',
    flexDirection: 'column',
    gap: '1.75rem',
    width: '100%',
  },
  horizontal: {
    alignItems: 'center',
    flexDirection: 'row',
  },
  label: {
    alignItems: 'center',
    display: 'flex',
    gap: '0.5rem',
    lineHeight: 1.375,
    width: 'fit-content',
  },
  legend: {
    fontWeight: 500,
    marginBottom: '0.75rem',
  },
  legendLabel: {
    fontSize: '0.875rem',
  },
  legendLegend: {
    fontSize: '1rem',
  },
  responsive: {
    alignItems: { '@media (min-width: 768px)': 'center', default: null },
    flexDirection: { '@media (min-width: 768px)': 'row', default: 'column' },
  },
  separator: {
    alignItems: 'center',
    display: 'flex',
    fontSize: '0.875rem',
    height: '1.25rem',
    justifyContent: 'center',
    marginBlock: '-0.5rem',
    position: 'relative',
  },
  separatorContent: {
    backgroundColor: colors.background,
    color: colors.mutedForeground,
    display: 'block',
    marginInline: 'auto',
    paddingInline: '0.5rem',
    position: 'relative',
    width: 'fit-content',
  },
  separatorLine: {
    insetInline: 0,
    position: 'absolute',
    top: '50%',
  },
  set: {
    display: 'flex',
    flexDirection: 'column',
    gap: '1.5rem',
  },
  title: {
    alignItems: 'center',
    display: 'flex',
    fontSize: '0.875rem',
    fontWeight: 500,
    gap: '0.5rem',
    lineHeight: 1.375,
    width: 'fit-content',
  },
  vertical: {
    flexDirection: 'column',
  },
});

type FieldOrientation = 'vertical' | 'horizontal' | 'responsive';

const orientationStyles: Record<FieldOrientation, StyleXStyles> = {
  horizontal: styles.horizontal,
  responsive: styles.responsive,
  vertical: styles.vertical,
};

// `style` is merged into stylexProps, so it takes StyleX styles, not inline CSS.
type StyleXElementProps<Tag extends 'div' | 'fieldset' | 'legend' | 'p'> = Omit<
  ComponentProps<Tag>,
  'style'
> & {
  style?: StyleXStyles;
};

const FieldSet = ({ className, style, ...props }: StyleXElementProps<'fieldset'>) => (
  <fieldset
    {...stylexProps(styles.set, customClassName(className), style)}
    data-slot="field-set"
    {...props}
  />
);

const FieldLegend = ({
  className,
  style,
  variant = 'legend',
  ...props
}: StyleXElementProps<'legend'> & { variant?: 'legend' | 'label' }) => (
  <legend
    {...stylexProps(
      styles.legend,
      variant === 'label' ? styles.legendLabel : styles.legendLegend,
      customClassName(className),
      style,
    )}
    data-slot="field-legend"
    data-variant={variant}
    {...props}
  />
);

const FieldGroup = ({ className, style, ...props }: StyleXElementProps<'div'>) => (
  <div
    {...stylexProps(styles.group, customClassName(className), style)}
    data-slot="field-group"
    {...props}
  />
);

const Field = ({
  className,
  orientation = 'vertical',
  style,
  ...props
}: StyleXElementProps<'div'> & { orientation?: FieldOrientation }) => (
  <div
    {...stylexProps(
      styles.fieldBase,
      orientationStyles[orientation],
      customClassName(className),
      style,
    )}
    data-orientation={orientation}
    data-slot="field"
    role="group"
    {...props}
  />
);

const FieldContent = ({ className, style, ...props }: StyleXElementProps<'div'>) => (
  <div
    {...stylexProps(styles.content, customClassName(className), style)}
    data-slot="field-content"
    {...props}
  />
);

const FieldLabel = ({ className, ...props }: ComponentProps<typeof Label>) => (
  <Label
    {...stylexProps(styles.label, customClassName(className))}
    data-slot="field-label"
    {...props}
  />
);

const FieldTitle = ({ className, style, ...props }: StyleXElementProps<'div'>) => (
  <div
    {...stylexProps(styles.title, customClassName(className), style)}
    data-slot="field-label"
    {...props}
  />
);

const FieldDescription = ({ className, style, ...props }: StyleXElementProps<'p'>) => (
  <p
    {...stylexProps(styles.description, customClassName(className), style)}
    data-slot="field-description"
    {...props}
  />
);

const FieldSeparator = ({ children, className, style, ...props }: StyleXElementProps<'div'>) => {
  const line = stylexProps(styles.separatorLine);
  const content = stylexProps(styles.separatorContent);
  return (
    <div
      {...stylexProps(styles.separator, customClassName(className), style)}
      data-content={Boolean(children)}
      data-slot="field-separator"
      {...props}
    >
      <Separator className={line.className} style={line.style} />
      {children ? (
        <span
          className={content.className}
          data-slot="field-separator-content"
          style={content.style}
        >
          {children}
        </span>
      ) : null}
    </div>
  );
};

const FieldError = ({
  children,
  className,
  errors,
  style,
  ...props
}: StyleXElementProps<'div'> & {
  errors?: Array<{ message?: string } | undefined>;
}) => {
  const content = useMemo(() => {
    if (children) {
      return children;
    }
    if (!errors?.length) {
      return null;
    }
    const uniqueErrors = [...new Map(errors.map((error) => [error?.message, error])).values()];
    if (uniqueErrors.length === 1) {
      return uniqueErrors[0]?.message;
    }
    return (
      <ul {...stylexProps(styles.errorList)}>
        {uniqueErrors.map((error) =>
          error?.message ? <li key={error.message}>{error.message}</li> : null,
        )}
      </ul>
    );
  }, [children, errors]);

  if (!content) {
    return null;
  }
  return (
    <div
      {...stylexProps(styles.error, customClassName(className), style)}
      data-slot="field-error"
      role="alert"
      {...props}
    >
      {content}
    </div>
  );
};

export {
  Field,
  FieldLabel,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLegend,
  FieldSeparator,
  FieldSet,
  FieldContent,
  FieldTitle,
};
