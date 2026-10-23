import { breakpoints, colors, fontWeight, leading, spacing } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { Link } from '@tanstack/react-router';
import { m } from '../paraglide/messages.js';
import { Footer } from './footer.tsx';
import { pill } from './pill.ts';

/** How many z letters are on their way at once. Their still poses are in styles/scenes.css. */
const SNORES = 3;
const SNORE_PERIOD = 7.2;

const styles = create({
  copy: {
    alignItems: 'center',
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s3,
  },
  inner: {
    alignItems: 'center',
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    gap: spacing.s10,
    justifyContent: 'center',
    marginInline: 'auto',
    maxWidth: '680px',
    paddingBottom: spacing.s12,
    textAlign: 'center',
    width: '100%',
  },
  main: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s12,
    isolation: 'isolate',
    minHeight: '100vh',
    overflowX: 'clip',
    paddingInline: { [breakpoints.md]: spacing.s6, default: spacing.s4 },
    paddingTop: '6.5rem',
    position: 'relative',
  },
  robot: {
    color: colors.fg,
    height: 'auto',
    maxWidth: '100%',
    overflow: 'visible',
    width: '168px',
  },
  snores: {
    color: colors.muted,
  },
  text: {
    color: colors.muted,
    lineHeight: leading.relaxed,
    maxWidth: '26rem',
    textWrap: 'pretty',
  },
  title: {
    fontSize: { [breakpoints.md]: '2.5rem', default: '2rem' },
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.15,
    textWrap: 'balance',
  },
});

/** The menu bar icon's head drawn as a line at five times its size, its eyes shut. */
function SleepingRobot() {
  return (
    <svg aria-hidden="true" fill="none" viewBox="0 0 168 144" {...props(styles.robot)}>
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.5">
        <circle cx="72" cy="41" r="5" />
        <path d="M72 46v10" />
        <rect height="64" rx="27" width="80" x="32" y="56" />
        <path d="M32 72h-4a4 4 0 0 0-4 4v12a4 4 0 0 0 4 4h4M112 72h4a4 4 0 0 1 4 4v12a4 4 0 0 1-4 4h-4" />
        <path d="M50.5 89q7 6 14 0M79.5 89q7 6 14 0" />
      </g>
      <g
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="1.5"
        {...props(styles.snores)}
      >
        {Array.from({ length: SNORES }, (_, index) => {
          const delay = `${-index * (SNORE_PERIOD / SNORES)}s`;
          return (
            <g className={`snore-still-${index}`} key={index} transform="translate(118 50)">
              <g className="snore-sway" style={{ animationDelay: delay }}>
                <path
                  className="snore-rise"
                  d="M-5-5h10l-10 10h10"
                  style={{ animationDelay: delay }}
                />
              </g>
            </g>
          );
        })}
      </g>
    </svg>
  );
}

/** Any address no route has: the robot asleep, a line on why, the way home and the footer. */
export function NotFound() {
  return (
    <main id="main" {...props(styles.main)}>
      <div {...props(styles.inner)}>
        <SleepingRobot />
        <div {...props(styles.copy)}>
          <h1 {...props(styles.title)}>{m.notfound_title()}</h1>
          <p {...props(styles.text)}>{m.notfound_text()}</p>
        </div>
        <Link to="/" {...props(pill.base, pill.ink, pill.small)}>
          {m.notfound_home()}
        </Link>
      </div>
      <Footer />
    </main>
  );
}
