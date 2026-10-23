'use client';

import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import { createContext, useContext } from 'react';
import type { CSSProperties, ComponentProps } from 'react';
import { colors, radius } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

export type CardSize = 'default' | 'sm';

interface CardContextValue {
  size?: CardSize;
}

const CardContext = createContext<CardContextValue>({
  size: 'default',
});

const styles = create({
  action: {
    alignSelf: 'start',
    gridColumnStart: 2,
    gridRowEnd: 'span 2',
    gridRowStart: 1,
    justifySelf: 'end',
  },
  card: {
    ':has([data-slot=card-footer])': {
      paddingBottom: 0,
    },
    ':has(> img:first-child)': {
      paddingTop: 0,
    },
    backgroundColor: colors.card,
    borderRadius: radius.md,
    boxShadow: `0 0 0 1px color-mix(in oklab, ${colors.foreground} 10%, transparent)`,
    color: colors.cardForeground,
    display: 'flex',
    flexDirection: 'column',
    fontSize: '0.875rem',
    lineHeight: '1.25rem',
    overflow: 'hidden',
  },
  cardDefault: {
    gap: 'var(--card-spacing, 1rem)',
    paddingBottom: 'var(--card-spacing, 1rem)',
    paddingTop: 'var(--card-spacing, 1rem)',
  },
  cardSm: {
    gap: 'var(--card-spacing, 0.75rem)',
    paddingBottom: 'var(--card-spacing, 0.75rem)',
    paddingTop: 'var(--card-spacing, 0.75rem)',
  },
  content: {},
  contentDefault: {
    paddingInline: 'var(--card-spacing, 1rem)',
  },
  contentSm: {
    paddingInline: 'var(--card-spacing, 0.75rem)',
  },
  description: {
    color: colors.mutedForeground,
    fontSize: '0.875rem',
    lineHeight: '1.25rem',
    textWrap: 'pretty',
  },
  footer: {
    alignItems: 'center',
    backgroundColor: `color-mix(in oklab, ${colors.muted} 50%, transparent)`,
    borderBottomLeftRadius: radius.md,
    borderBottomRightRadius: radius.md,
    borderTopColor: colors.border,
    borderTopStyle: 'solid',
    borderTopWidth: '1px',
    display: 'flex',
  },
  footerDefault: {
    padding: 'var(--card-spacing, 1rem)',
  },
  footerSm: {
    padding: 'var(--card-spacing, 0.75rem)',
  },
  header: {
    ':has([data-slot=card-action])': {
      gridTemplateColumns: '1fr auto',
    },
    ':has([data-slot=card-description])': {
      gridTemplateRows: 'auto auto',
    },
    alignItems: 'start',
    borderTopLeftRadius: radius.md,
    borderTopRightRadius: radius.md,
    display: 'grid',
    gap: '0.25rem',
    gridAutoRows: 'min-content',
  },
  headerDefault: {
    paddingInline: 'var(--card-spacing, 1rem)',
  },
  headerSm: {
    paddingInline: 'var(--card-spacing, 0.75rem)',
  },
  title: {
    fontSize: '1rem',
    fontWeight: 500,
    lineHeight: '1.375',
    textWrap: 'balance',
  },
  titleSm: {
    fontSize: '0.875rem',
  },
});

export type CardProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  size?: CardSize;
  style?: StyleXStyles | CSSProperties;
};

const Card = ({ children, className, size = 'default', style, ...props }: CardProps) => {
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.card,
    size === 'sm' ? styles.cardSm : styles.cardDefault,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <CardContext.Provider value={{ size }}>
      <div
        data-size={size}
        data-slot="card"
        {...styleProps}
        style={{
          ...styleProps.style,
          ...inlineStyle,
        }}
        {...props}
      >
        {children}
      </div>
    </CardContext.Provider>
  );
};

export type CardHeaderProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardHeader = ({ className, style, ...props }: CardHeaderProps) => {
  const { size } = useContext(CardContext);
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.header,
    size === 'sm' ? styles.headerSm : styles.headerDefault,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-header"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export type CardTitleProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardTitle = ({ className, style, ...props }: CardTitleProps) => {
  const { size } = useContext(CardContext);
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.title,
    size === 'sm' && styles.titleSm,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-title"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export type CardDescriptionProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardDescription = ({ className, style, ...props }: CardDescriptionProps) => {
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.description,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-description"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export type CardActionProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardAction = ({ className, style, ...props }: CardActionProps) => {
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.action,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-action"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export type CardContentProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardContent = ({ className, style, ...props }: CardContentProps) => {
  const { size } = useContext(CardContext);
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.content,
    size === 'sm' ? styles.contentSm : styles.contentDefault,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-content"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export type CardFooterProps = Omit<ComponentProps<'div'>, 'style'> & {
  className?: string;
  style?: StyleXStyles | CSSProperties;
};

const CardFooter = ({ className, style, ...props }: CardFooterProps) => {
  const { size } = useContext(CardContext);
  const isStyleX =
    style !== null &&
    style !== undefined &&
    typeof style === 'object' &&
    ('$$css' in style || Array.isArray(style));
  const styleProps = stylexProps(
    styles.footer,
    size === 'sm' ? styles.footerSm : styles.footerDefault,
    customClassName(className),
    isStyleX ? (style as StyleXStyles) : null,
  );
  const inlineStyle = !isStyleX && style ? (style as CSSProperties) : undefined;
  return (
    <div
      data-slot="card-footer"
      {...styleProps}
      style={{
        ...styleProps.style,
        ...inlineStyle,
      }}
      {...props}
    />
  );
};

export { Card, CardHeader, CardFooter, CardTitle, CardAction, CardDescription, CardContent };
