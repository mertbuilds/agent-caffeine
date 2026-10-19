const LINE = "color-mix(in srgb, var(--fg) 8%, transparent)";
const MASK = "radial-gradient(ellipse at 30% 40%, black 30%, transparent 75%)";

export function GridTexture() {
  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute inset-y-0 left-[calc(50%-50vw)] right-[calc(50%-50vw)] -z-10"
      style={{
        backgroundImage: `linear-gradient(${LINE} 1px, transparent 1px), linear-gradient(90deg, ${LINE} 1px, transparent 1px)`,
        backgroundSize: "40px 40px",
        maskImage: MASK,
        WebkitMaskImage: MASK,
      }}
    />
  );
}
