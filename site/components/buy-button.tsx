import type { ReactNode } from "react";
import { BuyCta } from "@/components/track";
import { BUY_URL } from "@/lib/buy";

const SIZES = {
  small: "px-4 py-1.5 text-sm",
  large: "px-6 py-3 text-base",
};

export function BuyButton({
  placement,
  size = "large",
  children,
}: {
  placement: "header" | "hero" | "pricing" | "blog";
  size?: keyof typeof SIZES;
  children: ReactNode;
}) {
  return (
    <BuyCta
      href={BUY_URL}
      placement={placement}
      className={`inline-block shrink-0 rounded-full bg-fg font-medium text-bg no-underline transition-opacity duration-quick ease-smooth-out hover:opacity-80 motion-reduce:transition-none ${SIZES[size]}`}
    >
      {children}
    </BuyCta>
  );
}
