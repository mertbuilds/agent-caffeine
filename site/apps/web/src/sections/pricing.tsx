import {
  breakpoints,
  colors,
  fontWeight,
  radius,
  spacing,
  text,
} from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { BuyButton } from '../components/buy-button.tsx';
import { DownloadButton, TryFree, useRelease } from '../components/download-button.tsx';
import {
  dollars,
  FULL_PRICE,
  LAUNCH_PRICE_ACTIVE,
  MACS,
  PORTAL_URL,
  PRICE,
} from '../lib/pricing.ts';
import { m } from '../paraglide/messages.js';

const GRID_LINE = 'rgba(255, 255, 255, 0.07)';

// Up to the lg breakpoint only, so it never competes with an lg value: StyleX does not order overlapping min-width queries.
const MD_ONLY = '@media (min-width: 768px) and (max-width: 1023.98px)';

const styles = create({
  actions: {
    alignItems: 'center',
    display: 'flex',
    flexWrap: 'wrap',
    gap: spacing.s3,
    justifyContent: { [breakpoints.md]: 'flex-start', default: 'center' },
  },
  badge: {
    backgroundColor: 'rgba(255, 255, 255, 0.15)',
    borderRadius: radius.full,
    fontSize: text.sm,
    lineHeight: text.smLeading,
    paddingBlock: spacing.s1,
    paddingInline: spacing.s3,
  },
  card: {
    backgroundImage: `linear-gradient(to bottom right, ${colors.brandLight}, ${colors.brandDeep})`,
    borderRadius: '20px',
    color: 'white',
    marginInline: 'auto',
    marginTop: { [breakpoints.md]: spacing.s10, default: spacing.s14 },
    maxWidth: '880px',
    position: 'relative',
  },
  column: {
    alignItems: { [breakpoints.md]: 'flex-start', default: 'center' },
    display: 'flex',
    flexDirection: 'column',
  },
  content: {
    alignItems: { [breakpoints.md]: 'center', default: null },
    display: 'grid',
    gap: { [breakpoints.md]: spacing.s10, default: spacing.s8 },
    gridTemplateColumns: { [breakpoints.md]: 'minmax(0, 1fr) auto', default: null },
    justifyItems: { [breakpoints.md]: 'start', default: 'center' },
    paddingBottom: { [breakpoints.md]: spacing.s14, default: spacing.s10 },
    paddingLeft: { [breakpoints.md]: spacing.s14, default: spacing.s6 },
    paddingRight: { [breakpoints.md]: spacing.s12, default: spacing.s6 },
    paddingTop: { [breakpoints.md]: spacing.s14, default: 0 },
    position: 'relative',
    textAlign: { [breakpoints.md]: 'left', default: 'center' },
  },
  decor: {
    borderRadius: 'inherit',
    inset: 0,
    overflow: 'hidden',
    pointerEvents: 'none',
    position: 'absolute',
  },
  // On a narrow card the light ends above the first line of text, which needs the blue under it to be read.
  gap3: { gap: spacing.s3 },
  gap4: { gap: spacing.s4 },
  gap5: { gap: spacing.s5 },
  gap8: { gap: spacing.s8 },
  glow: {
    backgroundImage: 'radial-gradient(closest-side, rgba(160, 205, 255, 0.5), transparent)',
    height: { [breakpoints.lg]: '520px', default: '190px', [MD_ONLY]: '380px' },
    left: { [breakpoints.md]: 'auto', default: '50%' },
    position: 'absolute',
    right: { [breakpoints.lg]: '-40px', default: null, [MD_ONLY]: '-60px' },
    top: 0,
    transform: { [breakpoints.md]: 'translate(0, -20%)', default: 'translate(-50%, -50%)' },
    width: { [breakpoints.lg]: '520px', default: '190px', [MD_ONLY]: '380px' },
  },
  grid: {
    backgroundImage: `linear-gradient(${GRID_LINE} 1px, transparent 1px), linear-gradient(90deg, ${GRID_LINE} 1px, transparent 1px)`,
    backgroundSize: '32px 32px',
    inset: 0,
    maskImage: {
      [breakpoints.md]: 'radial-gradient(ellipse 60% 90% at 82% 40%, black 10%, transparent 70%)',
      default: 'radial-gradient(ellipse 90% 45% at 50% 0%, black 10%, transparent 75%)',
    },
    position: 'absolute',
  },
  icon: {
    filter: 'drop-shadow(0 18px 22px rgba(6, 24, 74, 0.5))',
    height: { [breakpoints.lg]: '260px', default: '120px', [MD_ONLY]: '200px' },
    maxWidth: 'none',
    position: 'relative',
    transform: 'rotate(5deg)',
    width: { [breakpoints.lg]: '260px', default: '120px', [MD_ONLY]: '200px' },
  },
  iconBox: {
    alignSelf: { [breakpoints.md]: 'start', default: null },
    marginTop: {
      [breakpoints.md]: `calc(-1 * ${spacing.s24})`,
      default: `calc(-1 * ${spacing.s14})`,
    },
    order: { [breakpoints.md]: 9999, default: null },
    position: 'relative',
  },
  large: {
    fontSize: text.lg,
    lineHeight: text.lgLeading,
  },
  lostKey: {
    fontSize: text.sm,
    lineHeight: text.smLeading,
    outlineColor: { ':focus-visible': 'white', default: null },
  },
  now: {
    fontSize: { [breakpoints.md]: '6rem', default: '4.5rem' },
    lineHeight: 1,
  },
  price: {
    alignItems: 'baseline',
    display: 'flex',
    fontVariantNumeric: 'tabular-nums',
    fontWeight: fontWeight.medium,
    gap: spacing.s4,
    letterSpacing: '-0.02em',
    lineHeight: 1,
  },
  section: {
    marginInline: 'auto',
    maxWidth: '1120px',
    scrollMarginTop: spacing.s20,
    width: '100%',
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
  struck: {
    fontSize: { [breakpoints.md]: '3rem', default: '2.25rem' },
    lineHeight: { [breakpoints.md]: 1, default: '2.5rem' },
    opacity: 0.6,
    textDecorationThickness: '2px',
  },
  tabular: {
    fontVariantNumeric: 'tabular-nums',
  },
});

/** The price a buyer pays today. With the launch price on, the full price stands before it, struck through. */
function Price() {
  return (
    <div {...props(styles.column, styles.gap3)}>
      {LAUNCH_PRICE_ACTIVE ? (
        <p aria-hidden="true" {...props(styles.badge)}>
          {m.pricing_launch_badge()}
        </p>
      ) : null}
      <p {...props(styles.price)}>
        {LAUNCH_PRICE_ACTIVE ? (
          <s {...props(styles.struck)}>
            <span {...props(styles.srOnly)}>{m.pricing_full_price()}</span>
            {dollars(FULL_PRICE)}
          </s>
        ) : null}
        <span {...props(styles.now)}>
          {LAUNCH_PRICE_ACTIVE ? (
            <span {...props(styles.srOnly)}>{m.pricing_launch_price()}</span>
          ) : null}
          {PRICE}
        </span>
      </p>
    </div>
  );
}

export function Pricing() {
  const release = useRelease();
  return (
    <section id="pricing" {...props(styles.section)}>
      <h2 {...props(styles.srOnly)}>{m.pricing_title()}</h2>
      <div className={`pricing-card ${props(styles.card).className ?? ''}`}>
        <div aria-hidden="true" {...props(styles.decor)}>
          <div {...props(styles.grid)} />
          <div {...props(styles.glow)} />
        </div>
        <div {...props(styles.content)}>
          <div {...props(styles.iconBox)}>
            <img alt={''} height={1024} src="/icon-1024.png" width={1024} {...props(styles.icon)} />
          </div>
          <div {...props(styles.column, styles.gap8)}>
            <div {...props(styles.column, styles.gap5)}>
              <div {...props(styles.column, styles.gap3)}>
                {release === null ? null : <p {...props(styles.large)}>{m.pricing_trial()}</p>}
                <Price />
              </div>
              {/* A line may end only where a sentence ends. */}
              <p {...props(styles.large)}>{m.pricing_once({ macs: MACS })}</p>
            </div>
            <div {...props(styles.column, styles.gap4)}>
              <div {...props(styles.actions)}>
                {release === null ? null : (
                  <DownloadButton placement="pricing" release={release} variant="brand">
                    <TryFree />
                  </DownloadButton>
                )}
                <BuyButton
                  placement="pricing"
                  variant={release === null ? 'brand' : 'brandOutline'}
                >
                  {m.pricing_buy()}
                  <span {...props(styles.tabular)}>{PRICE}</span>
                </BuyButton>
              </div>
              <p>{m.pricing_updates()}</p>
              <a href={PORTAL_URL} {...props(styles.lostKey)}>
                {m.pricing_lost_key()}
              </a>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
