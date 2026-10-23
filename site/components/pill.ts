export const SIZES = {
  compact: "h-7 px-3.5 text-[0.8rem] leading-7",
  small: "px-4 py-1.5 text-sm",
  large: "px-6 py-3 text-base",
};

export const PILL =
  "inline-block shrink-0 rounded-full font-medium no-underline transition-opacity duration-quick ease-smooth-out hover:opacity-80 motion-reduce:transition-none";

const ON_BRAND =
  "inline-block shrink-0 rounded-full font-medium no-underline transition-[transform,box-shadow] duration-quick ease-smooth-out focus-visible:outline-white hover:-translate-y-px motion-reduce:transition-none motion-reduce:hover:translate-y-0";

/** Pills for the blue pricing card. */
export const BRAND_VARIANTS = {
  brand: (size: keyof typeof SIZES) =>
    `${ON_BRAND} bg-white text-brand-deep shadow-[0_1px_2px_rgba(8,30,90,0.25)] hover:shadow-[0_6px_16px_-4px_rgba(8,30,90,0.45)] ${SIZES[size]}`,
  brandOutline: (size: keyof typeof SIZES) =>
    `${ON_BRAND} text-white shadow-[inset_0_0_0_1px_rgba(255,255,255,0.55)] hover:shadow-[inset_0_0_0_1px_#ffffff] ${SIZES[size]}`,
};
