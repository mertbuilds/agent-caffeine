import type { ReactNode } from "react";
import { BuyCta } from "@/components/track";
import { BUY_URL } from "@/lib/buy";

export const SIZES = {
  small: "px-4 py-1.5 text-sm",
  large: "px-6 py-3 text-base",
};

export const PILL =
  "inline-block shrink-0 rounded-full font-medium no-underline transition-opacity duration-quick ease-smooth-out hover:opacity-80 motion-reduce:transition-none";

const VARIANTS = {
  solid: (size: keyof typeof SIZES) => `${PILL} bg-fg text-bg ${SIZES[size]}`,
  outline: (size: keyof typeof SIZES) => `${PILL} text-fg shadow-[inset_0_0_0_1px_var(--border)] ${SIZES[size]}`,
  text: () =>
    "shrink-0 text-sm text-muted no-underline transition-colors duration-quick ease-smooth-out hover:text-fg motion-reduce:transition-none",
};

export function BuyButton({
  placement,
  size = "large",
  variant = "solid",
  children,
}: {
  placement: "header" | "hero" | "pricing" | "blog";
  size?: keyof typeof SIZES;
  variant?: keyof typeof VARIANTS;
  children: ReactNode;
}) {
  return (
    <BuyCta href={BUY_URL} placement={placement} className={VARIANTS[variant](size)}>
      {children}
    </BuyCta>
  );
}
