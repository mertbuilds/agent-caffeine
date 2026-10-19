import { Fragment } from "react";
import { formatDate } from "@/lib/blog";
import { CHECKED_ON, OURS, ROWS, TOOLS, isText, type Cell, type Row, type Value } from "@/lib/compare";
import { CONTACT_EMAIL } from "@/lib/site";

const WORDS: Record<Value, string> = { yes: "Yes", no: "No", partly: "Partly", unstated: "Not stated" };

/** Our column stands a little apart: a faint wash of the accent, the same in every row. */
const OURS_GROUND = "bg-[color-mix(in_srgb,var(--accent)_7%,var(--bg))]";

function Mark({ value }: { value: "yes" | "no" }) {
  return (
    <>
      <svg
        aria-hidden="true"
        className={`inline-block align-[-3px] ${value === "yes" ? "" : "text-muted"}`}
        fill="none"
        height="16"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
        viewBox="0 0 16 16"
        width="16"
      >
        <path d={value === "yes" ? "M3 8.5l3.25 3.25L13 4.75" : "M4 8h8"} />
      </svg>
      <span className="sr-only">{WORDS[value]}</span>
    </>
  );
}

function CellValue({ cell, row }: { cell: Cell; row: Row }) {
  if (isText(cell)) return <span>{cell.text}</span>;
  if (cell.value === "unstated") return <span className="text-muted">{WORDS.unstated}</span>;
  if (cell.value === "partly" || row.words) return <span>{WORDS[cell.value]}</span>;
  return <Mark value={cell.value} />;
}

/** Every tool against every row of `lib/compare.ts`. A narrow window scrolls it sideways inside its box, with the row labels in place. */
export function CompareTable() {
  return (
    <div
      tabIndex={0}
      role="region"
      aria-label="Comparison table"
      className="overflow-x-auto rounded-[20px] border border-border focus-visible:outline focus-visible:outline-1 focus-visible:outline-offset-2 focus-visible:outline-muted"
    >
      <table className="w-full min-w-[60rem] table-fixed border-separate border-spacing-0 text-left text-sm leading-snug">
        <caption className="sr-only">Agent Caffeine and five other tools, feature by feature</caption>
        <colgroup>
          <col className="w-[8.5rem] sm:w-[14.5rem]" />
          {TOOLS.map((tool) => (
            <col key={tool.id} />
          ))}
        </colgroup>
        <thead>
          <tr>
            <td className="sticky left-0 z-10 border-r border-border bg-bg px-3 py-3 sm:px-4" />
            {TOOLS.map((tool) => (
              <th
                key={tool.id}
                scope="col"
                className={`px-3 py-3 font-medium ${tool.id === OURS ? `${OURS_GROUND} text-accent` : ""}`}
              >
                {tool.name}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {ROWS.map((row) => (
            <tr key={row.id}>
              <th scope="row" className="sticky left-0 z-10 border-r border-t border-border bg-bg px-3 py-1.5 align-top font-normal text-pretty sm:px-4">
                {row.label}
              </th>
              {TOOLS.map((tool) => {
                const cell = row.cells[tool.id];
                return (
                  <td key={tool.id} className={`border-t border-border px-3 py-1.5 align-top text-pretty ${tool.id === OURS ? OURS_GROUND : ""}`}>
                    <CellValue cell={cell} row={row} />
                    {cell.note === undefined ? null : (
                      <span className={`text-xs text-muted ${isText(cell) ? "mt-0.5 block" : ""}`}> {cell.note}</span>
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
  return (
    <div className="flex flex-col gap-1.5 text-pretty text-xs leading-relaxed text-muted">
      <p>
        Checked on <time dateTime={CHECKED_ON}>{formatDate(CHECKED_ON)}</time>. Each tool&apos;s own page is the
        source:{" "}
        {TOOLS.filter((tool) => tool.sources.length > 0).map((tool, index) => (
          <Fragment key={tool.id}>
            {index > 0 ? ", " : null}
            <a href={tool.sources[0].url} rel="noreferrer">
              {tool.name}
            </a>
          </Fragment>
        ))}
        . &quot;Not stated&quot; means that the page does not say. It does not mean no.
      </p>
      <p>
        Is a cell wrong or out of date? Write to <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> and we
        correct it.
      </p>
    </div>
  );
}
