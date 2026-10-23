import type { ReactNode } from "react";
import { BRAND_VARIANTS, PILL, SIZES } from "@/components/pill";
import { BuyCta, type Placement } from "@/components/track";

const VARIANTS = {
  ...BRAND_VARIANTS,
  solid: (size: keyof typeof SIZES) => `${PILL} bg-fg text-bg ${SIZES[size]}`,
  text: () =>
    "shrink-0 text-sm text-muted no-underline transition-colors duration-quick ease-smooth-out hover:text-fg motion-reduce:transition-none",
};

export function BuyButton({
  placement,
  size = "large",
  variant = "solid",
  children,
}: {
  placement: Placement;
  size?: keyof typeof SIZES;
  variant?: keyof typeof VARIANTS;
  children: ReactNode;
}) {
  return (
    <BuyCta placement={placement} className={VARIANTS[variant](size)}>
      {children}
    </BuyCta>
  );
}
