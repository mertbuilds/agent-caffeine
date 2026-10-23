import { colors } from '@caffeinagent/ui/tokens.stylex';
import NumberFlow from '@number-flow/react';
import { create, props, type StyleXStyles } from '@stylexjs/stylex';
import { Fragment, type ReactNode } from 'react';

/**
 * The app's menu, with the measures of `UI/Panel/PanelMetrics.swift`: 320
 * points wide, a 16 point gutter, a 56 point tile for the robot, a 28 point box for an agent's mark in a 34
 * point slot for its ring, and the system's text sizes (17, 13 and 12).
 */

const SYSTEM_FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif';
const ROLL = { duration: 350, easing: 'cubic-bezier(0.22, 1, 0.36, 1)' };

const styles = create({
  surface: {
    backgroundColor: colors.panel,
    borderColor: colors.panelLine,
    borderRadius: '0.75rem',
    borderStyle: 'solid',
    borderWidth: '1px',
    color: colors.panelFg,
    fontFamily: SYSTEM_FONT,
    fontSize: '13px',
    lineHeight: '1rem',
    textAlign: 'left',
  },
  tabular: {
    fontVariantNumeric: 'tabular-nums',
  },
});

/** Text whose numbers roll when they change, as the app's do. A group of digits keeps its length, so "06:00" keeps its zeros. With `still` a change shows at once. */
export function Flow({ children, still = false }: { children: string; still?: boolean }) {
  return (
    <>
      {children
        .split(/(\d+)/)
        .map((part, index) =>
          index % 2 === 1 ? (
            <NumberFlow
              animated={!still}
              className={props(styles.tabular).className}
              format={{ minimumIntegerDigits: part.length }}
              key={index}
              locales="en-US"
              opacityTiming={ROLL}
              spinTiming={ROLL}
              transformTiming={ROLL}
              value={Number(part)}
            />
          ) : (
            <Fragment key={index}>{part}</Fragment>
          ),
        )}
    </>
  );
}

/** The window of the menu, for a still cut of it. `className` takes the classes of styles/scenes.css, such as `panel-paused`. */
export function PanelSurface({
  children,
  className,
  label,
  style,
}: {
  children: ReactNode;
  className?: string | undefined;
  label: string;
  style?: StyleXStyles;
}) {
  const sx = props(styles.surface, style);
  return (
    <div
      aria-label={label}
      className={[className, sx.className].filter(Boolean).join(' ')}
      role="group"
    >
      {children}
    </div>
  );
}
