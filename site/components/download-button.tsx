import type { ReactNode } from "react";
import { PILL, SIZES } from "@/components/buy-button";
import { DownloadCta } from "@/components/track";
import type { Release } from "@/lib/release";

export function DownloadButton({
  release,
  placement,
  size = "large",
  children,
}: {
  release: Release;
  placement: "header" | "hero" | "pricing" | "blog";
  size?: keyof typeof SIZES;
  children: ReactNode;
}) {
  return (
    <DownloadCta
      href={release.href}
      filename={release.filename}
      placement={placement}
      className={`${PILL} bg-fg text-bg ${SIZES[size]}`}
    >
      {children}
    </DownloadCta>
  );
}
