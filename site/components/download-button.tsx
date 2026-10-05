import type { ReactNode } from "react";
import { BRAND_VARIANTS, PILL, SIZES } from "@/components/buy-button";
import { DownloadCta } from "@/components/track";
import type { Release } from "@/lib/release";

export function DownloadButton({
  release,
  placement,
  size = "large",
  variant = "solid",
  children,
}: {
  release: Release;
  placement: "header" | "hero" | "pricing" | "blog";
  size?: keyof typeof SIZES;
  variant?: "solid" | "brand";
  children: ReactNode;
}) {
  return (
    <DownloadCta
      href={release.href}
      filename={release.filename}
      placement={placement}
      className={variant === "brand" ? BRAND_VARIANTS.brand(size) : `${PILL} bg-fg text-bg ${SIZES[size]}`}
    >
      {children}
    </DownloadCta>
  );
}
