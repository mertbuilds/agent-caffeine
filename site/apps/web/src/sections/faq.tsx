import {
  colors,
  fontWeight,
  leading,
  motion,
  radius,
  spacing,
} from '@caffeinagent/ui/tokens.stylex';
import { create, defaultMarker, props, when } from '@stylexjs/stylex';
import { useId, useState, type ReactNode } from 'react';
import { faqItems } from '../lib/faq.tsx';
import { track } from '../lib/track.ts';
import { m } from '../paraglide/messages.js';

const LESS_MOTION = '@media (prefers-reduced-motion: reduce)';

const styles = create({
  answer: {
    color: colors.muted,
    lineHeight: leading.relaxed,
    paddingBottom: spacing.s4,
    textWrap: 'pretty',
  },
  button: {
    alignItems: 'center',
    borderRadius: radius.base,
    display: 'flex',
    gap: spacing.s4,
    justifyContent: 'space-between',
    lineHeight: leading.normal,
    paddingBlock: spacing.s4,
    textAlign: 'left',
    width: '100%',
  },
  chevron: {
    color: { default: colors.muted, [when.ancestor(':hover')]: colors.fg },
    flexShrink: 0,
    transitionDuration: motion.durationFast,
    transitionProperty: { default: 'transform', [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  chevronOpen: {
    color: colors.fg,
    transform: 'rotate(180deg)',
  },
  clip: {
    minHeight: 0,
    overflow: 'hidden',
  },
  item: {
    borderTopColor: colors.border,
    borderTopStyle: 'solid',
    borderTopWidth: { ':first-child': 0, default: '1px' },
  },
  question: {
    textWrap: 'pretty',
  },
  region: {
    display: 'grid',
    gridTemplateRows: '0fr',
    opacity: 0,
    transitionDuration: motion.durationFast,
    transitionProperty: { default: 'grid-template-rows, opacity', [LESS_MOTION]: 'none' },
    transitionTimingFunction: motion.easeSmoothOut,
  },
  regionOpen: {
    gridTemplateRows: '1fr',
    opacity: 1,
  },
  section: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s6,
    marginInline: 'auto',
    maxWidth: '640px',
    scrollMarginTop: spacing.s20,
    width: '100%',
  },
  title: {
    fontSize: '1.75rem',
    fontWeight: fontWeight.medium,
    letterSpacing: '-0.01em',
    lineHeight: 1.2,
    textWrap: 'balance',
  },
});

function Question({
  answer,
  initiallyOpen,
  name,
  question,
}: {
  answer: ReactNode;
  initiallyOpen: boolean;
  name: string;
  question: string;
}) {
  const id = useId();
  const [open, setOpen] = useState(initiallyOpen);
  const questionId = `${id}-question`;
  const answerId = `${id}-answer`;

  return (
    <div {...props(styles.item)}>
      <h3>
        <button
          aria-controls={answerId}
          aria-expanded={open}
          id={questionId}
          onClick={() => {
            if (!open) {
              track('faq_open', { id: name });
            }
            setOpen(!open);
          }}
          type="button"
          {...props(styles.button, defaultMarker())}
        >
          <span {...props(styles.question)}>{question}</span>
          <svg
            aria-hidden="true"
            fill="none"
            height="16"
            stroke="currentColor"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth="2.25"
            viewBox="0 0 24 24"
            width="16"
            {...props(styles.chevron, open && styles.chevronOpen)}
          >
            <path d="M6 9l6 6 6-6" />
          </svg>
        </button>
      </h3>
      <div
        aria-labelledby={questionId}
        id={answerId}
        inert={!open}
        role="region"
        {...props(styles.region, open && styles.regionOpen)}
      >
        <div {...props(styles.clip)}>
          <p {...props(styles.answer)}>{answer}</p>
        </div>
      </div>
    </div>
  );
}

export function Faq() {
  return (
    <section id="faq" {...props(styles.section)}>
      <h2 {...props(styles.title)}>{m.faq_title()}</h2>
      <div>
        {faqItems().map((item) => (
          <Question
            answer={item.answer}
            initiallyOpen={item.open === true}
            key={item.id}
            name={item.id}
            question={item.question}
          />
        ))}
      </div>
    </section>
  );
}
