import {
  breakpoints,
  colors,
  fontWeight,
  leading,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Fragment } from 'react';
import { formatDate } from '../lib/blog.ts';
import { CHECKED_ON, OURS, isText, rows, tools } from '../lib/compare.ts';
import type { Cell, Row, Value } from '../lib/compare.ts';
import { CONTACT_EMAIL } from '../lib/site.ts';
import { m } from '../paraglide/messages.js';
import { Rich } from './rich.tsx';

const WORDS: Record<Value, () => string> = {
  no: m.compare_no,
  partly: m.compare_partly,
  unstated: m.compare_unstated,
  yes: m.compare_yes,
};

/** Our column stands a little apart: a faint wash of the accent, the same in every row. */
const OURS_GROUND = `color-mix(in srgb, ${colors.accent} 7%, ${colors.bg})`;

const styles = create({
  box: {
    borderColor: colors.border,
    borderRadius: '20px',
    borderStyle: 'solid',
    borderWidth: '1px',
    outline: { ':focus-visible': `1px solid ${colors.muted}`, default: null },
    outlineOffset: '2px',
    overflowX: 'auto',
  },
  cell: {
    borderTopColor: colors.border,
    borderTopStyle: 'solid',
    borderTopWidth: '1px',
    paddingBlock: spacing.s1_5,
    paddingInline: spacing.s3,
    textWrap: 'pretty',
    verticalAlign: 'top',
  },
  corner: {
    paddingBlock: spacing.s3,
  },
  head: {
    fontWeight: fontWeight.medium,
    paddingBlock: spacing.s3,
    paddingInline: spacing.s3,
  },
  labelColumn: {
    width: { [breakpoints.sm]: '14.5rem', default: '8.5rem' },
  },
  mark: {
    display: 'inline-block',
    verticalAlign: '-3px',
  },
  muted: {
    color: colors.muted,
  },
  note: {
    color: colors.muted,
    fontSize: text.xs,
    lineHeight: text.xsLeading,
  },
  noteBlock: {
    display: 'block',
    marginTop: spacing.s0_5,
  },
  ours: {
    backgroundColor: OURS_GROUND,
  },
  oursHead: {
    color: colors.accent,
  },
  rowLabel: {
    fontWeight: fontWeight.normal,
    textAlign: 'left',
  },
  sources: {
    color: colors.muted,
    display: 'flex',
    flexDirection: 'column',
    fontSize: text.xs,
    gap: spacing.s1_5,
    lineHeight: leading.relaxed,
    textWrap: 'pretty',
  },
  // The row labels stay in place while a narrow window scrolls the table sideways.
  sticky: {
    backgroundColor: colors.bg,
    borderRightColor: colors.border,
    borderRightStyle: 'solid',
    borderRightWidth: '1px',
    left: 0,
    paddingInline: { [breakpoints.sm]: spacing.s4, default: spacing.s3 },
    position: 'sticky',
    zIndex: 10,
  },
  // Read by a screen reader, not drawn.
  srOnly: {
    borderWidth: 0,
    clip: 'rect(0, 0, 0, 0)',
    height: '1px',
    margin: '-1px',
    overflow: 'hidden',
    padding: 0,
    position: 'absolute',
    whiteSpace: 'nowrap',
    width: '1px',
  },
  table: {
    borderCollapse: 'separate',
    borderSpacing: 0,
    fontSize: text.sm,
    lineHeight: leading.snug,
    minWidth: '60rem',
    tableLayout: 'fixed',
    textAlign: 'left',
    width: '100%',
  },
});

function Mark({ value }: { value: 'yes' | 'no' }) {
  return (
    <>
      <svg
        aria-hidden="true"
        fill="none"
        height="16"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
        viewBox="0 0 16 16"
        width="16"
        {...props(styles.mark, value === 'no' && styles.muted)}
      >
        <path d={value === 'yes' ? 'M3 8.5l3.25 3.25L13 4.75' : 'M4 8h8'} />
      </svg>
      <span {...props(styles.srOnly)}>{WORDS[value]()}</span>
    </>
  );
}

function CellValue({ cell, row }: { cell: Cell; row: Row }) {
  if (isText(cell)) {
    return <span>{cell.text}</span>;
  }
  if (cell.value === 'unstated') {
    return <span {...props(styles.muted)}>{WORDS.unstated()}</span>;
  }
  if (cell.value === 'partly' || row.words) {
    return <span>{WORDS[cell.value]()}</span>;
  }
  return <Mark value={cell.value} />;
}

/** Every tool against every row of `lib/compare.ts`. A narrow window scrolls it sideways inside its box, with the row labels in place. */
export function CompareTable() {
  const all = tools();
  return (
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- a box that scrolls sideways takes the keyboard's focus so the arrow keys can scroll it
    <div aria-label={m.compare_table_label()} role="region" tabIndex={0} {...props(styles.box)}>
      <table {...props(styles.table)}>
        <caption {...props(styles.srOnly)}>{m.compare_table_caption()}</caption>
        <colgroup>
          <col {...props(styles.labelColumn)} />
          {all.map((tool) => (
            <col key={tool.id} />
          ))}
        </colgroup>
        <thead>
          <tr>
            <td {...props(styles.sticky, styles.corner)} />
            {all.map((tool) => (
              <th
                key={tool.id}
                scope="col"
                {...props(styles.head, tool.id === OURS && [styles.ours, styles.oursHead])}
              >
                {tool.name}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows().map((row) => (
            <tr key={row.id}>
              <th scope="row" {...props(styles.cell, styles.sticky, styles.rowLabel)}>
                {row.label}
              </th>
              {all.map((tool) => {
                const cell = row.cells[tool.id];
                return (
                  <td key={tool.id} {...props(styles.cell, tool.id === OURS && styles.ours)}>
                    <CellValue cell={cell} row={row} />
                    {cell.note === undefined ? null : (
                      <span {...props(styles.note, isText(cell) && styles.noteBlock)}>
                        {' '}
                        {cell.note}
                      </span>
                    )}
                  </td>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** Where the cells come from, and where to send a correction. */
export function CompareSources() {
  const sourced = tools().filter((tool) => tool.sources.length > 0);
  return (
    <div {...props(styles.sources)}>
      <p>
        {m.compare_checked_on()} <time dateTime={CHECKED_ON}>{formatDate(CHECKED_ON)}</time>
        {m.compare_sources_lead()}{' '}
        {sourced.map((tool, index) => (
          <Fragment key={tool.id}>
            {index > 0 ? ', ' : null}
            <a href={tool.sources[0]?.url} rel="noreferrer">
              {tool.name}
            </a>
          </Fragment>
        ))}
        {m.compare_sources_end()}
      </p>
      <p>
        <Rich text={m.compare_correction({ email: CONTACT_EMAIL })} />
      </p>
    </div>
  );
}
