"use client";

import { useEffect, useId, useRef, useState, useSyncExternalStore } from "react";
import { PILL, SIZES } from "@/components/buy-button";
import { SEND_LINK, type Opener, closeSendToMac, sendToMacOpener, subscribeSendToMac } from "@/lib/send-to-mac";

/** How long the copy button says the link is copied, in milliseconds. */
const COPIED_MS = 2000;

/** One button of the row. Each takes an equal share of it, so the copy's change of words moves nothing. */
const ACTION = `${PILL} ${SIZES.small} min-w-0 flex-1 cursor-pointer border-0 text-center`;

function onServer(): null {
  return null;
}

/**
 * What a download button opens off a Mac, where the app cannot run: it says so, and gives the
 * site's link to copy or share on to a Mac. One of it stands on every page (app/layout.tsx), and
 * it is in the page only while it is open. Escape, a press outside it and its close button close
 * it, and focus goes back to the button that opened it.
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
  const canShare = typeof navigator.share === "function";

  useEffect(() => {
    const node = dialog.current;
    if (node !== null && !node.open) node.showModal();
  }, []);

  useEffect(() => {
    if (!copied) return;
    const timer = window.setTimeout(() => setCopied(false), COPIED_MS);
    return () => window.clearTimeout(timer);
  }, [copied]);

  function onClose() {
    closeSendToMac();
    // A button that has gone with the menu it stood in leaves focus where the browser puts it.
    if (opener.isConnected) opener.focus({ preventScroll: true });
  }

  async function copy() {
    try {
      await navigator.clipboard.writeText(SEND_LINK);
      setCopied(true);
    } catch {
      // No clipboard, or the browser refused it: the button keeps its words.
    }
  }

  async function share() {
    try {
      await navigator.share({ title: "Agent Caffeine", url: SEND_LINK });
    } catch {
      // The visitor closed the share sheet.
    }
  }

  return (
    <dialog
      ref={dialog}
      aria-labelledby={title}
      onClose={onClose}
      // The dialog has no padding, so only a press on the dimmed page lands on the dialog itself.
      onPointerDown={(event) => {
        pressedOutside.current = event.target === event.currentTarget;
      }}
      // A drag that began on the popup's words and ended on the dimmed page is not a press outside.
      onClick={(event) => {
        if (pressedOutside.current && event.target === event.currentTarget) event.currentTarget.close();
      }}
      className="popup-in m-auto w-[calc(100%-2rem)] max-w-sm rounded-2xl border border-[color:color-mix(in_srgb,var(--fg)_10%,transparent)] bg-bg p-0 text-fg shadow-[0_8px_32px_var(--shadow)] backdrop:bg-black/40 dark:backdrop:bg-black/60"
    >
      <div className="flex flex-col gap-2 p-5">
        <h2 id={title} className="pr-8 text-lg font-medium leading-7">
          This app runs on a Mac
        </h2>
        <p className="text-sm text-muted">Agent Caffeine is a Mac app. It keeps your Mac awake while your agents work.</p>
        <p className="text-sm text-muted">Send this link to your Mac and download it there.</p>
        <div className="mt-3 flex gap-2">
          <button type="button" onClick={() => void copy()} className={`${ACTION} bg-fg text-bg`}>
            <span aria-live="polite">{copied ? "Link copied" : "Copy link"}</span>
          </button>
          {canShare ? (
            <button
              type="button"
              onClick={() => void share()}
              className={`${ACTION} bg-surface text-fg shadow-[inset_0_0_0_1px_var(--border)]`}
            >
              Share
            </button>
          ) : null}
        </div>
      </div>
      {/* After the actions, so focus starts on the copy button. */}
      <button
        type="button"
        aria-label="Close"
        onClick={() => dialog.current?.close()}
        className="absolute right-4 top-4 flex size-7 cursor-pointer items-center justify-center rounded-full border-0 bg-transparent p-0 text-muted transition-colors duration-quick ease-smooth-out before:absolute before:-inset-2 before:content-[''] hover:text-fg motion-reduce:transition-none"
      >
        <svg aria-hidden="true" className="size-3.5" fill="none" stroke="currentColor" strokeLinecap="round" strokeWidth="1.5" viewBox="0 0 14 14">
          <path d="M2 2l10 10M12 2L2 12" />
        </svg>
      </button>
    </dialog>
  );
}
