import { AgentsPanel } from "@/components/agents-panel";
import { SectionHeading } from "@/components/section-heading";

/** Stand-ins for the other status items, as wide as each glyph, in pixels. */
const GLYPHS = [16, 14, 20];

/** The SF Symbol `cup.and.saucer.fill`, as a template image in the menu bar colour. */
function CupAndSaucer({ className }: { className?: string }) {
  return (
    <svg aria-hidden="true" className={className} fill="currentColor" viewBox="0 0 20 16">
      <path d="M2.5 2.5h12v5c0 3.1-2.4 5.25-6 5.25s-6-2.15-6-5.25z" />
      <path
        d="M14.5 4.25h1a2.25 2.25 0 0 1 0 4.5h-1.25"
        fill="none"
        stroke="currentColor"
        strokeLinecap="round"
        strokeWidth={1.6}
      />
      <rect height={1.7} rx={0.85} width={17} x={0} y={13.6} />
    </svg>
  );
}

export function MenuBarSection() {
  return (
    <section className="mx-auto flex w-full max-w-[1120px] flex-col items-center gap-12">
      <SectionHeading title="Lives in your menu bar" />
      <div className="flex w-full max-w-[36rem] flex-col items-end gap-1">
        <div
          aria-hidden="true"
          className="flex h-6 w-full items-center justify-end rounded-md bg-[color-mix(in_srgb,var(--surface)_85%,transparent)] px-1.5 text-[13px] text-fg backdrop-blur"
        >
          {GLYPHS.map((width, index) => (
            <span key={index} className="flex h-[22px] items-center px-2">
              <span className="h-3.5 rounded-[3px] bg-current opacity-30" style={{ width }} />
            </span>
          ))}
          <span className="flex h-[22px] items-center rounded-[5px] bg-[color-mix(in_srgb,var(--fg)_14%,transparent)] px-2">
            <CupAndSaucer className="h-[15px] w-[19px]" />
          </span>
          <span className="w-14 text-center tabular-nums">9:41</span>
        </div>
        <div className="w-[320px] max-w-full sm:mr-[3.875rem]">
          <AgentsPanel />
        </div>
      </div>
      <p className="max-w-[26rem] text-balance text-center text-sm leading-normal text-muted">
        A small native Mac app. No daemons, no telemetry
      </p>
    </section>
  );
}
