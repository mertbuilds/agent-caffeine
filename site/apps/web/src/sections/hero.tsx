import {
  breakpoints,
  colors,
  fontWeight,
  leading,
  motion,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, defaultMarker, props, when } from '@stylexjs/stylex';
import { AgentIcon } from '../components/agent-icons.tsx';
import {
  DownloadButton,
  DownloadNotReady,
  TryFree,
  useRelease,
} from '../components/download-button.tsx';
import { GridTexture } from '../components/grid-texture.tsx';
import { HeroScene } from '../components/hero/hero-scene.tsx';
import { agents, markedAgents } from '../lib/agents.ts';
import type { Release } from '../lib/latest-release.ts';
import { PRICE } from '../lib/pricing.ts';
import { m } from '../paraglide/messages.js';

const SHOWN = markedAgents.slice(0, 7);
const MORE = agents.length - SHOWN.length;

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';

const styles = create({
  agent: {
    color: colors.fg,
    display: 'flex',
    position: 'relative',
  },
  agentIcon: {
    height: spacing.s6,
    width: spacing.s6,
  },
  agentList: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s3,
  },
  agentName: {
    backgroundColor: colors.bg,
    borderColor: colors.border,
    borderRadius: '0.375rem',
    borderStyle: 'solid',
    borderWidth: '1px',
    bottom: '100%',
    boxShadow: `0 4px 12px ${colors.shadow}`,
    color: colors.fg,
    fontSize: text.xs,
    left: '50%',
    lineHeight: text.xsLeading,
    marginBottom: spacing.s2,
    opacity: { default: 0, [when.ancestor(':hover')]: 1 },
    paddingBlock: spacing.s1,
    paddingInline: spacing.s2,
    pointerEvents: 'none',
    position: 'absolute',
    transform: {
      default: 'translateX(-50%) scale(0.98)',
      [when.ancestor(':hover')]: 'translateX(-50%)',
    },
    transitionDelay: { default: null, [when.ancestor(':hover')]: '80ms' },
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      default:
        'color, background-color, border-color, text-decoration-color, fill, stroke, opacity, box-shadow, transform, filter, backdrop-filter',
      [LESS_MOTION]: 'none',
    },
    transitionTimingFunction: 'cubic-bezier(0, 0, 0.2, 1)',
    whiteSpace: 'nowrap',
  },
  cta: {
    alignItems: { [breakpoints.lg]: 'flex-start', default: 'center' },
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s4,
  },
  dot: {
    transform: 'translateY(-0.09em)',
  },
  dotWide: {
    display: { [breakpoints.sm]: 'block', default: 'none' },
  },
  fact: {
    alignItems: 'center',
    display: 'flex',
    gap: spacing.s1_5,
  },
  factLast: {
    flexBasis: { [breakpoints.sm]: 'auto', default: '100%' },
    justifyContent: 'center',
  },
  facts: {
    alignItems: 'center',
    color: colors.muted,
    columnGap: spacing.s3,
    display: 'flex',
    flexWrap: 'wrap',
    fontSize: text.sm,
    justifyContent: { [breakpoints.lg]: 'flex-start', default: 'center' },
    lineHeight: text.smLeading,
    rowGap: spacing.s1_5,
  },
  glyph: {
    flexShrink: 0,
    transform: 'translateY(-0.08em)',
    width: 'auto',
  },
  lead: {
    color: colors.muted,
    fontSize: text.lg,
    gridColumnStart: { [breakpoints.lg]: 1, default: null },
    gridRowStart: { [breakpoints.lg]: 3, default: null },
    lineHeight: leading.relaxed,
    marginInline: { [breakpoints.lg]: 0, default: 'auto' },
    marginTop: { [breakpoints.lg]: `-${spacing.s2}`, default: null },
    maxWidth: { [breakpoints.lg]: '31rem', default: '26rem' },
    position: 'relative',
    textWrap: 'pretty',
    zIndex: 10,
  },
  price: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  scene: {
    gridColumnStart: { [breakpoints.lg]: 2, default: null },
    gridRow: { [breakpoints.lg]: '1 / span 5', default: null },
    minWidth: 0,
  },
  section: {
    alignItems: 'center',
    columnGap: spacing.s12,
    display: 'grid',
    gridTemplateColumns: { [breakpoints.lg]: 'minmax(0, 7fr) minmax(0, 5fr)', default: null },
    gridTemplateRows: { [breakpoints.lg]: '1fr auto auto auto 1fr', default: null },
    isolation: 'isolate',
    marginBottom: { [breakpoints.lg]: '-5.5rem', default: null },
    marginInline: 'auto',
    maxWidth: '1120px',
    minHeight: { [breakpoints.lg]: 'calc(100svh - 3.5rem)', default: null },
    paddingBottom: { [breakpoints.lg]: spacing.s10, default: spacing.s12 },
    paddingTop: { [breakpoints.lg]: spacing.s10, default: spacing.s8 },
    position: 'relative',
    rowGap: { [breakpoints.lg]: spacing.s7, default: spacing.s5 },
    textAlign: { [breakpoints.lg]: 'left', default: 'center' },
    width: '100%',
  },
  start: {
    alignItems: { [breakpoints.lg]: 'flex-start', default: 'center' },
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s7,
    gridColumnStart: { [breakpoints.lg]: 1, default: null },
    gridRowStart: { [breakpoints.lg]: 4, default: null },
    position: 'relative',
    zIndex: 10,
  },
  title: {
    fontSize: {
      [breakpoints.lg]: 'clamp(2.5rem, 4.2vw, 3rem)',
      default: 'clamp(2.25rem, 9vw, 2.75rem)',
    },
    fontWeight: fontWeight.medium,
    gridColumnStart: { [breakpoints.lg]: 1, default: null },
    gridRowStart: { [breakpoints.lg]: 2, default: null },
    letterSpacing: '-0.02em',
    lineHeight: 1.1,
    position: 'relative',
    zIndex: 10,
  },
  titleRest: {
    color: colors.accent,
    display: 'block',
    textWrap: 'balance',
    whiteSpace: { [breakpoints.xl]: 'nowrap', default: null },
  },
  worksWith: {
    alignItems: 'center',
    color: colors.muted,
    columnGap: spacing.s3,
    display: 'flex',
    flexWrap: 'wrap',
    fontSize: text.sm,
    justifyContent: { [breakpoints.lg]: 'flex-start', default: 'center' },
    lineHeight: text.smLeading,
    rowGap: spacing.s2,
  },
});

/** The small glyphs of the line under the download, in the stroke of the page. Each box is the ink of its glyph, at the height of the capitals. */
const GLYPH = {
  'aria-hidden': true,
  fill: 'none',
  stroke: 'currentColor',
  strokeLinecap: 'round',
  strokeLinejoin: 'round',
  strokeWidth: 1.5,
  ...props(styles.glyph),
} as const;

function WorksWith() {
  return (
    <div {...props(styles.worksWith)}>
      <span>{m.hero_works_with()}</span>
      <ul {...props(styles.agentList)}>
        {SHOWN.map((agent) => (
          <li key={agent.name} {...props(defaultMarker(), styles.agent)}>
            <AgentIcon label={agent.name} name={agent.icon} style={styles.agentIcon} />
            <span aria-hidden="true" {...props(styles.agentName)}>
              {agent.name}
            </span>
          </li>
        ))}
      </ul>
      <span>{m.hero_works_with_more({ count: MORE })}</span>
    </div>
  );
}

function Cta({ release }: { release: Release | null }) {
  return (
    <div {...props(styles.cta)}>
      {release === null ? (
        <DownloadNotReady />
      ) : (
        <DownloadButton placement="hero" release={release}>
          <TryFree />
        </DownloadButton>
      )}
      {/* With no download there is no trial to start, so the line names only the price. */}
      {release === null ? (
        <p {...props(styles.price)}>{m.hero_price_once({ price: PRICE })}</p>
      ) : (
        <ul {...props(styles.facts)}>
          <li {...props(styles.fact)}>
            <svg {...GLYPH} height="10.5" viewBox="0 0 12 10.5">
              <path d="M.75 3h10.5v2.5H.75zM1.75 5.5v4.25h8.5V5.5M6 3v6.75M6 3C4.6 3 3.4 2.6 3.4 1.7c0-.6.45-.95.95-.95C5.5.75 6 2 6 3Zm0 0c1.4 0 2.6-.4 2.6-1.3 0-.6-.45-.95-.95-.95C6.5.75 6 2 6 3Z" />
            </svg>
            {m.hero_free_days()}
          </li>
          <li aria-hidden="true" {...props(styles.dot)}>
            ·
          </li>
          <li>{m.hero_then_price({ price: PRICE })}</li>
          <li aria-hidden="true" {...props(styles.dot, styles.dotWide)}>
            ·
          </li>
          <li {...props(styles.fact, styles.factLast)}>
            <svg {...GLYPH} height="10" viewBox="0 0 13.5 10">
              <rect height="8.5" rx="1.5" width="12" x=".75" y=".75" />
              <path d="M.75 3.6h12M3.25 6.6h2" />
            </svg>
            {m.hero_no_card()}
          </li>
        </ul>
      )}
    </div>
  );
}

/**
 * The first screen. While no release can be read, the download gives way to a line that says so.
 */
export function Hero() {
  const release = useRelease();
  // On a phone the picture comes right after the headline, so the first screen shows it with the closed laptop. Side by side, the words and the download are one column.
  // Side by side the hero is the whole first screen, with its content in the middle, so the space under the content is already the gap to the next section. The margin takes most of the page's own gap away, and leaves the next heading just under the first screen.
  return (
    <section {...props(styles.section)}>
      <GridTexture />
      <h1 {...props(styles.title)}>
        {m.hero_title_lead()} <span {...props(styles.titleRest)}>{m.hero_title_rest()}</span>
      </h1>
      <div {...props(styles.scene)}>
        <HeroScene />
      </div>
      <p {...props(styles.lead)}>{m.hero_lead()}</p>
      <div {...props(styles.start)}>
        <WorksWith />
        <Cta release={release} />
      </div>
    </section>
  );
}
