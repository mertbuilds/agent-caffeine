import type { Config } from "tailwindcss";

export default {
  content: ["./app/**/*.{ts,tsx,mdx}", "./components/**/*.{ts,tsx}"],
  // The system's scheme unless `data-theme` forces one (lib/theme.ts).
  darkMode: [
    "variant",
    [
      "@media (prefers-color-scheme: dark) { &:not([data-theme=light] *) }",
      "&:is([data-theme=dark] *)",
    ],
  ],
  theme: {
    extend: {
      fontFamily: {
        // Without the Suisse Intl files the variable is not set (lib/fonts-fallback.ts), and the list starts at its second name.
        sans: ["var(--font-suisse, 'Suisse Intl Fallback')", "'Suisse Intl Fallback'", "system-ui", "sans-serif"],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "Monaco", "monospace"],
      },
      colors: {
        bg: "var(--bg)",
        fg: "var(--fg)",
        muted: "var(--muted)",
        border: "var(--border)",
        surface: "var(--surface)",
        accent: "var(--accent)",
        brand: {
          light: "var(--brand-light)",
          deep: "var(--brand-deep)",
        },
      },
      transitionDuration: {
        quick: "var(--duration-quick)",
        fast: "var(--duration-fast)",
        slow: "var(--duration-slow)",
      },
      transitionTimingFunction: {
        "smooth-out": "var(--ease-smooth-out)",
      },
    },
  },
  plugins: [],
} satisfies Config;
