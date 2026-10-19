"use client";

import { useSyncExternalStore, type ReactNode } from "react";
import { downloadLink } from "@/lib/download";
import { isMacDevice, openSendToMac } from "@/lib/send-to-mac";
import { rememberedUtm, track, type Placement, type SupportPlacement } from "@/lib/track";

export type { Placement };

/** The support section's link to GitHub Sponsors, counted in the browser with where it sits. */
export function SupportCta({
  href,
  placement,
  className,
  children,
}: {
  href: string;
  placement: SupportPlacement;
  className?: string;
  children: ReactNode;
}) {
  return (
    <a href={href} onClick={() => track("support_click", { placement })} className={className}>
      {children}
    </a>
  );
}

const subscribe = () => () => {};

function onServer(): null {
  return null;
}

/**
 * A link to the dmg, by way of `/download`, where the server counts it. `href` is the dmg itself:
 * it tells a sample release, which has no file, from a real one. The click is also counted in
 * the browser with where it sits.
 *
 * The link is the same for everyone, so it works with no script. Off a Mac, where the app cannot
 * run, a click starts no download: it opens the popup that sends the link on to a Mac
 * (components/send-to-mac-popup.tsx), and is counted apart.
 */
export function DownloadCta({
  href,
  filename,
  placement,
  className,
  children,
}: {
  href: string;
  filename: string;
  placement: Placement;
  className?: string;
  children: ReactNode;
}) {
  const utm = useSyncExternalStore(subscribe, rememberedUtm, onServer);
  return (
    <a
      href={downloadLink(placement, utm)}
      download={href.startsWith("#") ? undefined : filename}
      onClick={(event) => {
        if (isMacDevice(navigator.userAgent, navigator.maxTouchPoints)) {
          track("download_click", { placement });
          return;
        }
        event.preventDefault();
        track("download_blocked_not_mac", { placement });
        openSendToMac(event.currentTarget);
      }}
      className={className}
    >
      {children}
    </a>
  );
}
