'use client';

import { create, props as stylexProps } from '@stylexjs/stylex';
import type { StyleXStyles } from '@stylexjs/stylex';
import type { ComponentProps } from 'react';
import { colors } from '../lib/tokens.stylex.ts';
import { customClassName } from '../lib/utils.stylex.ts';

const styles = create({
  body: {
    borderBottomWidth: {
      ':nth-child(n) > tr:last-child': 0,
      default: null,
    },
  },
  caption: {
    color: colors.mutedForeground,
    fontSize: '0.875rem',
    lineHeight: '1.25rem',
    marginTop: '1rem',
  },
  cell: {
    padding: '0.5rem',
    paddingRight: {
      ':has([role=checkbox])': 0,
      default: null,
    },
    verticalAlign: 'middle',
    whiteSpace: 'nowrap',
  },
  container: {
    overflowX: 'auto',
    position: 'relative',
    width: '100%',
  },
  footer: {
    backgroundColor: `color-mix(in oklab, ${colors.muted} 50%, transparent)`,
    borderBottomWidth: {
      ':nth-child(n) > tr:last-child': 0,
      default: null,
    },
    borderTopColor: colors.border,
    borderTopStyle: 'solid',
    borderTopWidth: '1px',
    fontWeight: 500,
  },
  head: {
    color: colors.foreground,
    fontWeight: 500,
    height: '2.5rem',
    paddingInline: '0.5rem',
    paddingRight: {
      ':has([role=checkbox])': 0,
      default: null,
    },
    textAlign: 'left',
    verticalAlign: 'middle',
    whiteSpace: 'nowrap',
  },
  header: {
    borderBottomColor: {
      ':nth-child(n) > tr': colors.border,
      default: null,
    },
    borderBottomStyle: {
      ':nth-child(n) > tr': 'solid',
      default: null,
    },
    borderBottomWidth: {
      ':nth-child(n) > tr': '1px',
      default: null,
    },
  },
  row: {
    backgroundColor: {
      ':has([aria-expanded=true])': `color-mix(in oklab, ${colors.muted} 50%, transparent)`,
      ':hover': `color-mix(in oklab, ${colors.muted} 50%, transparent)`,
      ':nth-child(n)[data-state=selected]': colors.muted,
      default: 'transparent',
    },
    borderBottomColor: colors.border,
    borderBottomStyle: 'solid',
    borderBottomWidth: '1px',
    transitionDuration: '150ms',
    transitionProperty: 'color, background-color, border-color',
  },
  table: {
    // Row borders (styles.row) only render in the collapsing border model.
    borderCollapse: 'collapse',
    captionSide: 'bottom',
    fontSize: '0.875rem',
    lineHeight: '1.25rem',
    width: '100%',
  },
});

export type TableProps = Omit<ComponentProps<'table'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const Table = ({ className, style, ...props }: TableProps) => (
  <div data-slot="table-container" {...stylexProps(styles.container)}>
    <table
      data-slot="table"
      {...stylexProps(styles.table, customClassName(className), style as StyleXStyles)}
      {...props}
    />
  </div>
);

export type TableHeaderProps = Omit<ComponentProps<'thead'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableHeader = ({ className, style, ...props }: TableHeaderProps) => (
  <thead
    data-slot="table-header"
    {...stylexProps(styles.header, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableBodyProps = Omit<ComponentProps<'tbody'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableBody = ({ className, style, ...props }: TableBodyProps) => (
  <tbody
    data-slot="table-body"
    {...stylexProps(styles.body, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableFooterProps = Omit<ComponentProps<'tfoot'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableFooter = ({ className, style, ...props }: TableFooterProps) => (
  <tfoot
    data-slot="table-footer"
    {...stylexProps(styles.footer, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableRowProps = Omit<ComponentProps<'tr'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableRow = ({ className, style, ...props }: TableRowProps) => (
  <tr
    data-slot="table-row"
    {...stylexProps(styles.row, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableHeadProps = Omit<ComponentProps<'th'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableHead = ({ className, style, ...props }: TableHeadProps) => (
  <th
    data-slot="table-head"
    {...stylexProps(styles.head, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableCellProps = Omit<ComponentProps<'td'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableCell = ({ className, style, ...props }: TableCellProps) => (
  <td
    data-slot="table-cell"
    {...stylexProps(styles.cell, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export type TableCaptionProps = Omit<ComponentProps<'caption'>, 'style'> & {
  className?: string;
  style?: StyleXStyles;
};

const TableCaption = ({ className, style, ...props }: TableCaptionProps) => (
  <caption
    data-slot="table-caption"
    {...stylexProps(styles.caption, customClassName(className), style as StyleXStyles)}
    {...props}
  />
);

export { Table, TableHeader, TableBody, TableFooter, TableHead, TableRow, TableCell, TableCaption };
