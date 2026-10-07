import type { Utm } from "@/lib/attribution";
import type { Release } from "@/lib/release";
import { OPENPANEL_API_URL } from "@/lib/site";
import { isLiveHost } from "@/lib/track";

/** The address every download link goes to. The server counts the download there, then sends the browser on to the dmg. */
export const DOWNLOAD_PATH = "/download";

const PLACEMENTS = ["header", "menu", "hero", "pricing", "blog", "footer"] as const;

export type DownloadPlacement = (typeof PLACEMENTS)[number] | "other";

/** Where the link sits, from `?from=`. A value that is not on the list counts as "other". */
export function placementFrom(from: string | null): DownloadPlacement {
  return PLACEMENTS.find((placement) => placement === from) ?? "other";
}

const COUNTED_UTM_KEYS = ["utm_source", "utm_medium", "utm_campaign"] as const;

export type DownloadUtm = Partial<Record<(typeof COUNTED_UTM_KEYS)[number], string>>;

const MAX_LENGTH = 100;

/** The three campaign tags the count keeps, each cut at 100 characters. Empty ones are left out. */
export function downloadUtmFrom(params: URLSearchParams): DownloadUtm {
  const utm: DownloadUtm = {};
  for (const key of COUNTED_UTM_KEYS) {
    const value = params.get(key)?.trim().slice(0, MAX_LENGTH);
    if (value) utm[key] = value;
  }
  return utm;
}

/** The link of a download button: where it sits, and the source of the visit when the browser knows one. */
export function downloadLink(placement: string, utm: Utm | null): string {
  const params = new URLSearchParams({ from: placement });
  for (const key of COUNTED_UTM_KEYS) {
    const value = utm?.[key];
    if (value) params.set(key, value);
  }
  return `${DOWNLOAD_PATH}?${params}`;
}

const BOT = /bot|crawler|spider|curl|wget|python-requests|headless|preview|facebookexternalhit/i;

/** True for no user agent and for the programs that fetch links without a person behind them. */
export function isBot(userAgent: string | null): boolean {
  return !userAgent || userAgent.trim() === "" || BOT.test(userAgent);
}

/** True when the browser fetches the link ahead of a click. */
export function isPrefetch(headers: Headers): boolean {
  return ["purpose", "sec-purpose"].some((name) => headers.get(name)?.toLowerCase().includes("prefetch"));
}

/** The host name of a `host` header, without the port. */
export function hostnameOf(host: string | null): string {
  return (host ?? "").trim().toLowerCase().replace(/:\d+$/, "");
}

/**
 * The visitor's IP address. Cloudflare sits in front of Vercel, so its header comes first:
 * there `x-forwarded-for` can name Cloudflare and not the visitor.
 */
export function clientIp(headers: Headers): string | null {
  const ip =
    headers.get("cf-connecting-ip")?.trim() ||
    headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    headers.get("x-real-ip")?.trim();
  return ip || null;
}

export type DownloadEvent = {
  name: "download";
  properties: { version: string; build?: string; placement: DownloadPlacement } & DownloadUtm;
  /** Sent on to OpenPanel for the country and the device. Not kept by this site. */
  ip: string | null;
  userAgent: string;
};

export type DownloadDecision = { redirectTo: string; event: DownloadEvent | null };

/**
 * Where a request for the download goes, and the event to count, if any.
 * Every request gets a redirect. Only a person's GET on the live site, with the secret set, is counted.
 */
export function decideDownload({
  host,
  method,
  headers,
  search,
  release,
  secretSet,
}: {
  host: string | null;
  method: string;
  headers: Headers;
  search: string;
  release: Release | null;
  secretSet: boolean;
}): DownloadDecision {
  if (release === null || !release.href.startsWith("/mac/")) return { redirectTo: "/", event: null };
  const redirectTo = release.href;
  const userAgent = headers.get("user-agent");
  if (
    !secretSet ||
    method !== "GET" ||
    !isLiveHost(hostnameOf(host)) ||
    userAgent === null ||
    isBot(userAgent) ||
    isPrefetch(headers)
  ) {
    return { redirectTo, event: null };
  }
  const params = new URLSearchParams(search);
  return {
    redirectTo,
    event: {
      name: "download",
      properties: {
        version: release.version,
        ...(release.build === undefined ? {} : { build: release.build }),
        placement: placementFrom(params.get("from")),
        ...downloadUtmFrom(params),
      },
      ip: clientIp(headers),
      userAgent,
    },
  };
}

/** How long the count may take. The redirect does not wait for it. */
export const TRACK_TIMEOUT_MS = 1500;

/**
 * The request that counts an event on the server. The secret is what lets a server send one.
 * Without the IP headers OpenPanel takes every server event for one device.
 */
export function trackRequest(
  event: DownloadEvent,
  clientId: string,
  clientSecret: string,
): { url: string; init: { method: "POST"; headers: Record<string, string>; body: string } } {
  return {
    url: `${OPENPANEL_API_URL}/track`,
    init: {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "openpanel-client-id": clientId,
        "openpanel-client-secret": clientSecret,
        "user-agent": event.userAgent,
        ...(event.ip === null ? {} : { "openpanel-client-ip": event.ip, "x-client-ip": event.ip }),
      },
      body: JSON.stringify({ type: "track", payload: { name: event.name, properties: event.properties } }),
    },
  };
}
