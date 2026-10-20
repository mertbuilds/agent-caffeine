import { parseUtm, utmFrom, type Utm } from "@/lib/attribution";

/** The hosts the live site is served on. A preview or a local run never sends an event. */
const LIVE_HOSTS = ["caffeinagent.com", "www.caffeinagent.com"];

export function isLiveHost(hostname: string): boolean {
  return LIVE_HOSTS.includes(hostname);
}

export function onLiveHost(): boolean {
  return typeof window !== "undefined" && isLiveHost(window.location.hostname);
}

export type Placement = "header" | "hero" | "pricing" | "blog" | "footer";

/** Where a support link sits: the header's link to the section, or the section's own button. */
export type SupportPlacement = "header" | "section";

/** Where a GitHub link sits: the header's button, the phone menu's row, or the footer's links. */
export type GitHubPlacement = "header" | "menu" | "footer";

/** Every event the site counts, with what it carries. None carries anything about the visitor. */
export type TrackEvents = {
  download_click: { placement: Placement };
  /** A download button pressed off a Mac: the popup opened and no download started. */
  download_blocked_not_mac: { placement: Placement };
  /** The first time in a page view that a visitor touches the menu bar simulator. */
  simulator_use: { control: string };
  /** A question of the home page opened, by its `id` in `lib/faq.tsx`. */
  faq_open: { id: string };
  /** A support link pressed: the header's link to the section, or the section's button to GitHub Sponsors. */
  support_click: { placement: SupportPlacement };
  /** A link to the code on GitHub pressed, with where it sits. */
  github_clicked: { placement: GitHubPlacement };
};

/** Counts an event. Does nothing off the live site, or while OpenPanel is not there. */
export function track<Name extends keyof TrackEvents>(name: Name, properties: TrackEvents[Name]) {
  if (!onLiveHost() || typeof window.op !== "function") return;
  window.op("track", name, properties);
}

const UTM_STORE = "utm";

/** Keeps the campaign tags of the first page of this visit, for this tab only. Only on the live site. */
export function rememberUtm() {
  if (!onLiveHost()) return;
  try {
    if (sessionStorage.getItem(UTM_STORE) === null) {
      sessionStorage.setItem(UTM_STORE, JSON.stringify(utmFrom(window.location.search)));
    }
  } catch {
    // No storage, as in some private windows: the tags are then read from the address of each page.
  }
}

let read: { stored: string | null; utm: Utm | null } | null = null;

/**
 * The tags `rememberUtm` kept, or null off the live site. The same object comes back
 * until the store changes, so it can be a snapshot for `useSyncExternalStore`.
 */
export function rememberedUtm(): Utm | null {
  if (!onLiveHost()) return null;
  rememberUtm();
  let stored: string | null = null;
  try {
    stored = sessionStorage.getItem(UTM_STORE);
  } catch {
    // As above.
  }
  if (read === null || read.stored !== stored) {
    read = { stored, utm: parseUtm(stored) ?? utmFrom(window.location.search) };
  }
  return read.utm;
}
