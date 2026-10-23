import { colors } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';

const LINE = `color-mix(in srgb, ${colors.fg} 8%, transparent)`;
const MASK = 'radial-gradient(ellipse at 30% 40%, black 30%, transparent 75%)';

const styles = create({
  grid: {
    backgroundImage: `linear-gradient(${LINE} 1px, transparent 1px), linear-gradient(90deg, ${LINE} 1px, transparent 1px)`,
    backgroundSize: '40px 40px',
    bottom: 0,
    left: 'calc(50% - 50vw)',
    maskImage: MASK,
    pointerEvents: 'none',
    position: 'absolute',
    right: 'calc(50% - 50vw)',
    top: 0,
    zIndex: -10,
  },
});

export function GridTexture() {
  return <div aria-hidden="true" {...props(styles.grid)} />;
}
