"use client";

import Link from "next/link";
import type { ReactNode } from "react";

function fire(event: string, props?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (typeof window.op !== "function") return;
  window.op("track", event, props);
}

export function BuyCta({
  href,
  placement,
  className,
  children,
}: {
  href: string;
  placement: "header" | "hero" | "pricing";
  className?: string;
  children: ReactNode;
}) {
  return (
    <Link
      href={href}
      onClick={() => fire("buy_clicked", { placement })}
      className={className}
    >
      {children}
    </Link>
  );
}

export function OutboundLink({
  href,
  event,
  props,
  className,
  target = "_blank",
  rel = "noreferrer",
  children,
}: {
  href: string;
  event: string;
  props?: Record<string, unknown>;
  className?: string;
  target?: string;
  rel?: string;
  children: ReactNode;
}) {
  return (
    <a
      href={href}
      target={target}
      rel={rel}
      onClick={() => fire(event, props)}
      className={className}
    >
      {children}
    </a>
  );
}
