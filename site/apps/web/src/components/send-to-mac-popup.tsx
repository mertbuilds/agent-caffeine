import { colors, fontWeight, motion, radius, spacing, text } from '@caffeinagent/ui/tokens.stylex';
import { create, props } from '@stylexjs/stylex';
import { useEffect, useId, useRef, useState, useSyncExternalStore } from 'react';
import {
  closeSendToMac,
  SEND_LINK,
  sendToMacOpener,
  subscribeSendToMac,
  type Opener,
} from '../lib/send-to-mac.ts';
import { m } from '../paraglide/messages.js';
import { pill } from './pill.ts';

/** How long the copy button says the link is copied, in milliseconds. */
const COPIED_MS = 2000;

const styles = create({
  // One button of the row. Each takes an equal share of it, so the copy's change of words moves nothing.
  action: {
    borderWidth: 0,
    cursor: 'pointer',
    flexBasis: 0,
    flexGrow: 1,
    minWidth: 0,
    textAlign: 'center',
  },
  actions: {
    display: 'flex',
    gap: spacing.s2,
    marginTop: spacing.s3,
  },
  body: {
    display: 'flex',
    flexDirection: 'column',
    gap: spacing.s2,
    padding: spacing.s5,
  },
  close: {
    '::before': {
      content: "''",
      inset: `calc(-1 * ${spacing.s2})`,
      position: 'absolute',
    },
    alignItems: 'center',
    backgroundColor: 'transparent',
    borderRadius: radius.full,
    borderWidth: 0,
    color: { ':hover': colors.fg, default: colors.muted },
    cursor: 'pointer',
    display: 'flex',
    height: spacing.s7,
    justifyContent: 'center',
    padding: 0,
    position: 'absolute',
    right: spacing.s4,
    top: spacing.s4,
    transitionDuration: motion.durationQuick,
    transitionProperty: {
      '@media (prefers-reduced-motion: reduce)': 'none',
      default: 'color, background-color, border-color, text-decoration-color, fill, stroke',
    },
    transitionTimingFunction: motion.easeSmoothOut,
    width: spacing.s7,
  },
  closeIcon: {
    height: spacing.s3_5,
    width: spacing.s3_5,
  },
  dialog: {
    backgroundColor: colors.bg,
    borderColor: `color-mix(in srgb, ${colors.fg} 10%, transparent)`,
    borderRadius: radius.xl2,
    borderStyle: 'solid',
    borderWidth: '1px',
    boxShadow: `0 8px 32px ${colors.shadow}`,
    color: colors.fg,
    margin: 'auto',
    maxWidth: '24rem',
    padding: 0,
    width: 'calc(100% - 2rem)',
  },
  line: {
    color: colors.muted,
    fontSize: text.sm,
    lineHeight: text.smLeading,
  },
  share: {
    backgroundColor: colors.surface,
    boxShadow: `inset 0 0 0 1px ${colors.border}`,
    color: colors.fg,
  },
  title: {
    fontSize: text.lg,
    fontWeight: fontWeight.medium,
    lineHeight: spacing.s7,
    paddingRight: spacing.s8,
  },
});

/** Hands the link to the browser's share sheet. */
async function share() {
  try {
    await navigator.share({ title: m.app_name(), url: SEND_LINK });
  } catch {
    // The visitor closed the share sheet.
  }
}

function onServer(): null {
  return null;
}

/** The share sheet is there or not for the whole visit, so there is nothing to subscribe to. */
function subscribeNever(): () => void {
  return () => {};
}

function hasShareSheet(): boolean {
  return typeof navigator.share === 'function';
}

function noShareSheetOnServer(): boolean {
  return false;
}

/**
 * What a download button opens off a Mac, where the app cannot run: it says
 * so, and gives the site's link to copy or share on to a Mac. One of it stands
 * on every page (routes/__root.tsx), and it is in the page only while it is
 * open. Escape, a press outside it and its close button close it, and focus
 * goes back to the button that opened it.
 */
export function SendToMacPopup() {
  const opener = useSyncExternalStore(subscribeSendToMac, sendToMacOpener, onServer);
  return opener === null ? null : <Popup opener={opener} />;
}

function Popup({ opener }: { opener: Opener }) {
  const dialog = useRef<HTMLDialogElement>(null);
  // True while the press that is under way began on the dimmed page.
  const pressedOutside = useRef(false);
  const [copied, setCopied] = useState(false);
  const title = useId();
  // A browser without a share sheet has the copy alone.
  const canShare = useSyncExternalStore(subscribeNever, hasShareSheet, noShareSheetOnServer);

  useEffect(() => {
    const node = dialog.current;
    if (node !== null && !node.open) {
      node.showModal();
    }
  }, []);

  useEffect(() => {
    if (!copied) {
      return;
    }
    const timer = window.setTimeout(() => setCopied(false), COPIED_MS);
    return () => window.clearTimeout(timer);
  }, [copied]);

  function onClose() {
    closeSendToMac();
    // A button that has gone with the menu it stood in leaves focus where the browser puts it.
    if (opener.isConnected) {
      opener.focus({ preventScroll: true });
    }
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(SEND_LINK);
      setCopied(true);
    } catch {
      // No clipboard, or the browser refused it: the button keeps its words.
    }
  }

  return (
    <dialog
      aria-labelledby={title}
      className={`popup-in ${props(styles.dialog).className ?? ''}`}
      // A drag that began on the popup's words and ended on the dimmed page is not a press outside.
      onClick={(event) => {
        if (pressedOutside.current && event.target === event.currentTarget) {
          event.currentTarget.close();
        }
      }}
      onClose={onClose}
      // The dialog has no padding, so only a press on the dimmed page lands on the dialog itself.
      onPointerDown={(event) => {
        pressedOutside.current = event.target === event.currentTarget;
      }}
      ref={dialog}
    >
      <div {...props(styles.body)}>
        <h2 id={title} {...props(styles.title)}>
          {m.popup_title()}
        </h2>
        <p {...props(styles.line)}>{m.popup_about()}</p>
        <p {...props(styles.line)}>{m.popup_send()}</p>
        <div {...props(styles.actions)}>
          <button
            onClick={() => void copy()}
            type="button"
            {...props(pill.base, pill.small, styles.action, pill.ink)}
          >
            <span aria-live="polite">{copied ? m.popup_copied() : m.popup_copy()}</span>
          </button>
          {canShare ? (
            <button
              onClick={() => void share()}
              type="button"
              {...props(pill.base, pill.small, styles.action, styles.share)}
            >
              {m.popup_share()}
            </button>
          ) : null}
        </div>
      </div>
      {/* After the actions, so focus starts on the copy button. */}
      <button
        aria-label={m.popup_close()}
        onClick={() => dialog.current?.close()}
        type="button"
        {...props(styles.close)}
      >
        <svg
          aria-hidden="true"
          fill="none"
          stroke="currentColor"
          strokeLinecap="round"
          strokeWidth="1.5"
          viewBox="0 0 14 14"
          {...props(styles.closeIcon)}
        >
          <path d="M2 2l10 10M12 2L2 12" />
        </svg>
      </button>
    </dialog>
  );
}
