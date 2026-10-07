import type { ReactNode } from "react";
import { BRAND_VARIANTS, PILL, SIZES } from "@/components/buy-button";
import { DownloadCta, type Placement } from "@/components/track";
import type { Release } from "@/lib/release";

export function DownloadButton({
  release,
  placement,
  size = "large",
  variant = "solid",
  children,
}: {
  release: Release;
  placement: Placement;
  size?: keyof typeof SIZES;
  variant?: "solid" | "brand" | "brandOutline";
  children: ReactNode;
}) {
  return (
    <DownloadCta
      href={release.href}
      filename={release.filename}
      placement={placement}
      className={variant === "solid" ? `${PILL} bg-fg text-bg ${SIZES[size]}` : BRAND_VARIANTS[variant](size)}
    >
      {children}
    </DownloadCta>
  );
}
