"use client";

import Link from "next/link";
import type { ReactNode } from "react";

type Placement = "header" | "hero" | "pricing" | "blog";

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
  placement: Placement;
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
      download={filename}
      onClick={() => fire("download_clicked", { placement })}
      className={className}
    >
      {children}
    </a>
  );
}
