import { colors, motion } from '@caffeinagent/ui/tokens.stylex';
import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import { memo, useId } from 'react';
import type { Pose } from '../lib/simulator.ts';

/**
 * The robot at the top of the app's menu, from the app's own pictures and
 * measures (`UI/Panel/Robot/*.swift`, `RobotLook.swift`): a still tile, the
 * robot floating over it, and its eyes, steam and antenna light drawn on top.
 * It is laid out at the app's 96 points and scaled to `size`.
 */

const SIDE = 96;
/** The pictures are 100 points, a little larger than the tile they show in. */
const PICTURE = 100;

type Look = {
  antenna: 'glowing' | 'steady' | 'amber' | 'dark' | 'red';
  contrast: number;
  dimming: number;
  eyes: 'happy' | 'open' | 'closed' | 'dim' | 'dead';
  /** Blinks and floats. */
  lively: boolean;
  saturation: number;
  snoozes: boolean;
  /** How many wisps of steam rise from the cup. */
  wisps: number;
};

const CALM = { contrast: 1, dimming: 0, lively: false, saturation: 1, snoozes: false, wisps: 0 };

/** `RobotLook.init(pose:)`. */
const LOOKS: Record<Pose, Look> = {
  asleep: {
    ...CALM,
    antenna: 'dark',
    dimming: 0.08,
    eyes: 'closed',
    saturation: 0.6,
    snoozes: true,
  },
  attentive: { ...CALM, antenna: 'amber', eyes: 'open', lively: true },
  awake: { ...CALM, antenna: 'glowing', eyes: 'happy', lively: true, wisps: 2 },
  off: { ...CALM, antenna: 'dark', contrast: 0.8, dimming: 0.04, eyes: 'dim', saturation: 0 },
  paused: {
    ...CALM,
    antenna: 'dark',
    dimming: 0.08,
    eyes: 'closed',
    saturation: 0.6,
    snoozes: true,
  },
  reachable: { ...CALM, antenna: 'steady', eyes: 'happy', lively: true, wisps: 1 },
  trouble: { ...CALM, antenna: 'red', dimming: 0.1, eyes: 'dead', saturation: 0.5 },
};

/** `RobotGeometry`, in hundredths of the picture: the middle of each eye and how far a shut one reaches. */
const EYES = [
  { reach: 4.21, x: 38.528, y: 44.25 },
  { reach: 4.217, x: 61.426, y: 44.265 },
];
const ANTENNA = { r: 4.467, x: 50.011, y: 14.6 };
const CUP = '51.855px 68.333px';
/** The round eyes shut towards this height (`RobotEyes.anchor`). */
const EYE_ANCHOR = '50px 44.6px';

/** One row of a wisp: its height, its left and right edge, and how much the steam covers. */
type WispRow = readonly [y: number, left: number, right: number, strength: number];

const LARGE_WISP: ReadonlyArray<WispRow> = [
  [49.833, 49.128, 49.283, 0.133],
  [50.5, 48.404, 49.273, 0.217],
  [51.233, 47.874, 49.492, 0.287],
  [51.9, 47.672, 49.99, 0.331],
  [52.567, 47.715, 50.968, 0.342],
  [53.233, 47.844, 51.73, 0.357],
  [53.967, 48.216, 52.653, 0.36],
  [54.633, 48.628, 53.48, 0.337],
  [55.3, 49.266, 54.195, 0.325],
  [56.033, 49.882, 54.826, 0.346],
  [56.7, 50.307, 55.214, 0.382],
  [57.367, 50.727, 55.464, 0.295],
  [58.1, 50.89, 55.589, 0.359],
  [58.767, 50.689, 55.525, 0.394],
  [59.433, 50.443, 55.48, 0.386],
  [60.1, 50.305, 55.117, 0.389],
  [60.833, 50.201, 54.688, 0.394],
  [61.5, 49.988, 54.187, 0.397],
  [62.167, 49.805, 53.584, 0.409],
  [62.9, 49.43, 52.984, 0.404],
  [63.567, 49.392, 52.506, 0.314],
  [64.233, 49.262, 52.129, 0.309],
  [64.967, 49.394, 51.846, 0.336],
  [65.633, 49.571, 51.677, 0.367],
  [66.3, 49.776, 51.615, 0.364],
  [66.967, 50.085, 51.634, 0.291],
  [67.7, 50.719, 51.827, 0.228],
  [68.367, 51.79, 51.986, 0.144],
];

const SMALL_WISP: ReadonlyArray<WispRow> = [
  [55.967, 47.014, 47.157, 0.131],
  [56.367, 46.746, 47.28, 0.161],
  [56.7, 46.48, 47.402, 0.193],
  [57.1, 46.16, 47.549, 0.233],
  [57.433, 45.893, 47.671, 0.266],
  [57.833, 45.58, 47.805, 0.302],
  [58.167, 45.319, 47.79, 0.322],
  [58.567, 44.884, 47.616, 0.336],
  [58.9, 44.521, 47.45, 0.345],
  [59.3, 44.13, 47.244, 0.353],
  [59.633, 43.869, 47.086, 0.355],
  [60.033, 43.621, 46.747, 0.347],
  [60.367, 43.452, 46.506, 0.341],
  [60.767, 43.277, 46.264, 0.339],
  [61.1, 43.155, 46.115, 0.34],
  [61.5, 43.085, 45.962, 0.338],
  [61.833, 43.067, 45.875, 0.341],
  [62.233, 43.067, 45.805, 0.345],
  [62.567, 43.072, 45.801, 0.344],
  [62.967, 43.164, 45.845, 0.337],
  [63.3, 43.429, 45.91, 0.321],
  [63.7, 43.862, 45.975, 0.291],
  [64.033, 44.226, 46.029, 0.265],
  [64.433, 44.664, 46.095, 0.234],
  [64.767, 45.028, 46.149, 0.208],
  [65.167, 45.465, 46.214, 0.177],
  [65.5, 45.829, 46.268, 0.152],
  [65.9, 46.195, 46.323, 0.128],
];

/** The two wisps of the icon, each a share of the steam's loop behind the first (`RobotSteam.all`). */
const WISPS = [
  { lag: 0, rows: LARGE_WISP },
  { lag: 0.37, rows: SMALL_WISP },
];
const STEAM_PERIOD = 3.6;
const SNOOZE_PERIOD = 4.4;
/** The letter a sleeping robot sends up. */
const SNOOZE = 'z';

function outline(rows: ReadonlyArray<WispRow>): string {
  return [
    ...rows.map((row) => `${row[1]},${row[0]}`),
    ...[...rows].reverse().map((row) => `${row[2]},${row[0]}`),
  ].join(' ');
}

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';
const EASE_OUT = 'cubic-bezier(0, 0, 0.2, 1)';

const styles = create({
  badge: {
    alignItems: 'center',
    backgroundColor: colors.panel,
    borderRadius: '9999px',
    bottom: '-4.8px',
    boxShadow: `inset 0 0 0 0.5px color-mix(in srgb, ${colors.panelFg} 10%, transparent)`,
    display: 'flex',
    height: '26.9px',
    justifyContent: 'center',
    opacity: 0,
    position: 'absolute',
    right: '-6.7px',
    transform: 'scale(0.6)',
    transitionDuration: '350ms',
    transitionProperty: { default: 'opacity, transform', [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
    width: '26.9px',
  },
  badgeIcon: {
    height: '9px',
    width: '18px',
  },
  badgeShown: {
    opacity: 1,
    transform: 'scale(1)',
  },
  clip: {
    borderRadius: '21.6px',
    display: 'block',
    inset: 0,
    overflow: 'hidden',
    position: 'absolute',
  },
  fade: {
    transitionDuration: '350ms',
    transitionProperty: { default: 'opacity', [LESS_MOTION]: 'none' },
    transitionTimingFunction: EASE_OUT,
  },
  filterFade: {
    transitionDuration: '350ms',
    transitionProperty: { default: 'filter', [LESS_MOTION]: 'none' },
    transitionTimingFunction: EASE_OUT,
  },
  rim: {
    borderRadius: 'inherit',
    boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.16)',
    display: 'block',
    inset: 0,
    position: 'absolute',
  },
  root: {
    display: 'block',
    flexShrink: 0,
    position: 'relative',
  },
  steam: {
    overflow: 'visible',
  },
  tile: {
    display: 'block',
    height: '96px',
    left: 0,
    position: 'absolute',
    top: 0,
    transformOrigin: 'top left',
    width: '96px',
  },
});

/** The classes of styles/scenes.css beside StyleX styles, as one className. */
function classes(names: string, ...style: ReadonlyArray<StyleXStyles | false>): string {
  return [names, props(...style).className].filter(Boolean).join(' ');
}

function shown(on: boolean) {
  return { ...props(styles.fade), opacity: on ? 1 : 0 };
}

type RobotProps = {
  /** Holds every loop where it is, while nobody sees the robot. */
  paused?: boolean | undefined;
  pose: Pose;
  /** How far the pose's tone has come in, from 0 (the full colour of the robot awake) to 1, as a CSS number such as `var(--rest)`. With it the tone follows that number and does not fade by itself. */
  rest?: string | undefined;
  /** The side of the tile, in pixels. */
  size?: number | undefined;
  /** A still picture of the pose, as the app shows it with Reduce Motion. */
  still?: boolean | undefined;
};

export const Robot = memo(function Robot({
  paused = false,
  pose,
  rest,
  size = SIDE,
  still = false,
}: RobotProps) {
  const id = `robot-${useId().replaceAll(/[^a-zA-Z0-9]/g, '')}`;
  const look = LOOKS[pose];
  const lift = `robot-layer ${look.lively ? 'robot-float' : ''}`;
  const iconEyes = look.eyes === 'happy' ? 1 : look.eyes === 'dim' ? 0.3 : 0;
  const toned = (full: number) =>
    rest === undefined ? String(full) : `calc(1 + ${full - 1} * ${rest})`;
  // A robot in its full colour has no filter, so its loops are drawn without one.
  const plain = look.saturation === 1 && look.contrast === 1 && look.dimming === 0;
  const filter = plain
    ? undefined
    : `saturate(${toned(look.saturation)}) contrast(${toned(look.contrast)}) brightness(${toned(1 - look.dimming)})`;
  const picture = {
    alt: '',
    decoding: 'async',
    draggable: false,
    height: PICTURE,
    loading: 'lazy',
    width: PICTURE,
  } as const;

  return (
    <span
      aria-hidden="true"
      className={classes('robot', styles.root)}
      data-paused={paused || undefined}
      data-still={still || undefined}
      style={{ height: size, width: size }}
    >
      <span
        {...props(styles.tile)}
        style={{ transform: size === SIDE ? undefined : `scale(${size / SIDE})` }}
      >
        <span className={classes('robot-clip', styles.clip)}>
          <span
            className={classes('robot-layer', rest === undefined && styles.filterFade)}
            style={{ filter }}
          >
            <img {...picture} className="robot-layer" src="/robot/tile.png" />
            <span className={lift}>
              <img {...picture} className="robot-layer" src="/robot/body.png" />
              <span className={classes('robot-layer', styles.fade)} style={{ opacity: iconEyes }}>
                <img
                  {...picture}
                  className={`robot-layer ${look.lively ? 'robot-blink-hide' : ''}`}
                  src="/robot/eyes.png"
                />
              </span>
            </span>
          </span>
          <span className={lift}>
            <svg className={classes('robot-layer', styles.steam)} viewBox="0 0 100 100">
              <defs>
                {WISPS.map((wisp, index) => {
                  const top = wisp.rows[0]![0];
                  const foot = wisp.rows.at(-1)![0];
                  return (
                    <linearGradient
                      id={`${id}-wisp-${index}`}
                      key={index}
                      x1="0"
                      x2="0"
                      y1="0"
                      y2="1"
                    >
                      {wisp.rows.map((row) => (
                        <stop
                          key={row[0]}
                          offset={((row[0] - top) / (foot - top)).toFixed(3)}
                          stopColor="#fff"
                          stopOpacity={row[3]}
                        />
                      ))}
                    </linearGradient>
                  );
                })}
                {(
                  [
                    ['blue', '184,230,255'],
                    ['amber', '255,184,51'],
                    ['red', '255,69,59'],
                  ] as const
                ).map(([name, color]) => (
                  <radialGradient id={`${id}-halo-${name}`} key={name}>
                    <stop offset="0.23" stopColor={`rgb(${color})`} stopOpacity="0.9" />
                    <stop offset="0.615" stopColor={`rgb(${color})`} stopOpacity="0.35" />
                    <stop offset="1" stopColor={`rgb(${color})`} stopOpacity="0" />
                  </radialGradient>
                ))}
                <radialGradient cx="0.4" cy="0.34" id={`${id}-ball-amber`} r="0.61">
                  <stop offset="0" stopColor="#ffedad" />
                  <stop offset="0.5" stopColor="#ffb833" />
                  <stop offset="1" stopColor="#eb8f14" />
                </radialGradient>
                <radialGradient cx="0.4" cy="0.34" id={`${id}-ball-red`} r="0.61">
                  <stop offset="0" stopColor="#ffa899" />
                  <stop offset="0.5" stopColor="#ff453b" />
                  <stop offset="1" stopColor="#bd1a17" />
                </radialGradient>
              </defs>

              <g className="robot-eye-glow">
                <g {...shown(look.eyes === 'open')}>
                  <g
                    className={look.lively ? 'robot-blink-squash' : undefined}
                    fill="#b5e1fa"
                    style={{ transformOrigin: EYE_ANCHOR }}
                  >
                    {EYES.map((eye) => (
                      <ellipse cx={eye.x} cy={eye.y} key={eye.x} rx="3.4" ry="4.1" />
                    ))}
                  </g>
                </g>
                {/* Shut for good while it sleeps, and for a moment when the happy eyes blink. */}
                {(['closed', 'happy'] as const).map((kind) => (
                  <g key={kind} {...shown(look.eyes === kind)}>
                    <g
                      className={kind === 'happy' ? 'robot-blink-show' : undefined}
                      fill="none"
                      stroke="#b5e1fa"
                      strokeLinecap="round"
                      strokeOpacity="0.85"
                      strokeWidth="2.2"
                    >
                      {EYES.map((eye) => (
                        <path
                          d={`M${eye.x - eye.reach} ${eye.y + 1.2}Q${eye.x} ${eye.y + 2.6} ${eye.x + eye.reach} ${eye.y + 1.2}`}
                          key={eye.x}
                        />
                      ))}
                    </g>
                  </g>
                ))}
              </g>
              <g
                className={classes('robot-eye-glow-red', styles.fade)}
                fill="none"
                opacity={look.eyes === 'dead' ? 1 : 0}
                stroke="#ff5c52"
                strokeLinecap="round"
                strokeWidth="2.4"
              >
                {EYES.map((eye) => (
                  <path
                    d={`M${eye.x - 3.1} ${eye.y - 3.1}l6.2 6.2M${eye.x + 3.1} ${eye.y - 3.1}l-6.2 6.2`}
                    key={eye.x}
                  />
                ))}
              </g>

              <g {...shown(look.antenna === 'glowing')}>
                <circle
                  className="robot-glow robot-glow-blue"
                  cx={ANTENNA.x}
                  cy={ANTENNA.y}
                  fill={`url(#${id}-halo-blue)`}
                  r={ANTENNA.r * 2.6}
                />
              </g>
              {/* The glow at rest, with no breath (`RobotAntennaLight.rest`). */}
              <circle
                {...props(styles.fade)}
                cx={ANTENNA.x}
                cy={ANTENNA.y}
                fill={`url(#${id}-halo-blue)`}
                opacity={look.antenna === 'steady' ? 0.49 : 0}
                r={ANTENNA.r * 2.6}
              />
              <g {...shown(look.antenna === 'amber')}>
                <circle
                  className="robot-glow robot-glow-amber"
                  cx={ANTENNA.x}
                  cy={ANTENNA.y}
                  fill={`url(#${id}-halo-amber)`}
                  r={ANTENNA.r * 2.6}
                />
                <circle
                  cx={ANTENNA.x}
                  cy={ANTENNA.y}
                  fill={`url(#${id}-ball-amber)`}
                  r={ANTENNA.r * 1.02}
                />
              </g>
              <g {...shown(look.antenna === 'red')}>
                <circle
                  cx={ANTENNA.x}
                  cy={ANTENNA.y}
                  fill={`url(#${id}-halo-red)`}
                  opacity="0.55"
                  r={ANTENNA.r * 2.6}
                />
                <circle
                  cx={ANTENNA.x}
                  cy={ANTENNA.y}
                  fill={`url(#${id}-ball-red)`}
                  r={ANTENNA.r * 1.02}
                />
              </g>
              <circle
                {...shown(look.antenna === 'dark')}
                cx={ANTENNA.x}
                cy={ANTENNA.y}
                fill="rgba(26,51,107,0.22)"
                r={ANTENNA.r}
              />

              <g className="robot-sway" style={{ transformOrigin: CUP }}>
                {WISPS.map((wisp, index) => (
                  <g key={index} {...shown(index < look.wisps)}>
                    {/* Two of each, half a loop apart, so the steam never stops. */}
                    {[0, 1].map((copy) => (
                      <polygon
                        className={`robot-wisp ${copy === 1 ? 'robot-wisp-second' : ''}`}
                        fill={`url(#${id}-wisp-${index})`}
                        key={copy}
                        points={outline(wisp.rows)}
                        style={{ animationDelay: `${-(wisp.lag + copy * 0.5) * STEAM_PERIOD}s` }}
                      />
                    ))}
                  </g>
                ))}
              </g>
            </svg>
          </span>
          <span
            className={classes('robot-layer', styles.fade)}
            style={{ opacity: look.snoozes ? 1 : 0 }}
          >
            {[0, 1].map((index) => (
              <span
                className={`robot-snooze ${index === 1 ? 'robot-snooze-second' : ''}`}
                key={index}
                style={{
                  animationDelay: `${-index * 0.45 * SNOOZE_PERIOD}s`,
                  fontSize: index === 0 ? 13 : 9.5,
                  left: 77 - index * 7,
                  top: 17 + index * 9,
                }}
              >
                {SNOOZE}
              </span>
            ))}
          </span>
          <span {...props(styles.rim)} />
        </span>
        <span {...props(styles.badge, pose === 'trouble' && styles.badgeShown)}>
          <svg
            {...props(styles.badgeIcon)}
            fill="none"
            style={{ color: 'light-dark(#ff3b30, #ff453a)' }}
            viewBox="0 0 18 9"
          >
            <rect height="8" rx="2.4" stroke="currentColor" width="14.6" x="0.5" y="0.5" />
            <rect fill="currentColor" height="5" rx="1.1" width="3.6" x="2" y="2" />
            <path d="M16.6 3v3" stroke="currentColor" strokeLinecap="round" strokeWidth="1.2" />
          </svg>
        </span>
      </span>
    </span>
  );
});
