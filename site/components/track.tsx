"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import type { Plan } from "@/lib/pricing";

export type Placement = "header" | "hero" | "pricing" | "blog" | "footer";

function fire(event: string, props?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (typeof window.op !== "function") return;
  window.op("track", event, props);
}

/** A link to a plan's checkout. The click is counted with the plan and its price. */
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
  return (
    <Link
      href={plan.checkoutUrl}
      onClick={() => fire("buy_clicked", { placement, plan: plan.id, price: plan.price })}
      className={className}
    >
      {children}
    </Link>
  );
}

/** A link to the dmg. The click is counted with where it sits, to set trial starts beside buys. */
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
  return (
    <a
      href={href}
      download={href.startsWith("#") ? undefined : filename}
      onClick={() => fire("download_clicked", { placement })}
      className={className}
    >
      {children}
    </a>
  );
}
