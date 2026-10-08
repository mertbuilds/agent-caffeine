import { parseUtm, utmFrom, type Utm } from "@/lib/attribution";
import type { Plan } from "@/lib/pricing";

/** The hosts the live site is served on. A preview or a local run never sends an event. */
const LIVE_HOSTS = ["caffeinagent.com", "www.caffeinagent.com"];

export function isLiveHost(hostname: string): boolean {
  return LIVE_HOSTS.includes(hostname);
}

export function onLiveHost(): boolean {
  return typeof window !== "undefined" && isLiveHost(window.location.hostname);
}

export type Placement = "header" | "hero" | "pricing" | "blog" | "footer";

/** Every event the site counts, with what it carries. None carries anything about the visitor. */
export type TrackEvents = {
  download_click: { placement: Placement };
  plan_select: { plan: Plan["id"] };
  buy_click: { plan: Plan["id"]; price: number; placement: Placement };
  /** The first time in a page view that a visitor touches the menu bar simulator. */
  simulator_use: { control: string };
  /** A question of the home page opened, by its `id` in `lib/faq.tsx`. */
  faq_open: { id: string };
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
    // No storage, as in some private windows: the checkout link then names the site as the source.
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
