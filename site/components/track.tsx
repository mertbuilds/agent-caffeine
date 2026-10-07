"use client";

import Link from "next/link";
import { useSyncExternalStore, type ReactNode } from "react";
import { checkoutUrlWith } from "@/lib/attribution";
import { downloadLink } from "@/lib/download";
import type { Plan } from "@/lib/pricing";
import { rememberedUtm, track, type Placement } from "@/lib/track";

export type { Placement };

const subscribe = () => () => {};

function onServer(): null {
  return null;
}

/**
 * A link to a plan's checkout. The click is counted with the plan and its price.
 * The server's link is the plain checkout link. On the live site the browser then adds the visitor's source to it.
 */
export function BuyCta({
  plan,
  placement,
  className,
  children,
}: {
  plan: Plan;
  placement: Placement;
  className?: string;
  children: ReactNode;
}) {
  const utm = useSyncExternalStore(subscribe, rememberedUtm, onServer);
  return (
    <Link
      href={utm === null ? plan.checkoutUrl : checkoutUrlWith(plan.checkoutUrl, utm)}
      onClick={() => track("buy_click", { plan: plan.id, price: plan.price, placement })}
      className={className}
    >
      {children}
    </Link>
  );
}

/**
 * A link to the dmg, by way of `/download`, where the server counts it. `href` is the dmg itself:
 * it tells a sample release, which has no file, from a real one. The click is also counted in
 * the browser with where it sits, to set trial starts beside buys.
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
      onClick={() => track("download_click", { placement })}
      className={className}
    >
      {children}
    </a>
  );
}
