import type { Config } from "tailwindcss";

export default {
  content: ["./app/**/*.{ts,tsx,mdx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["var(--font-suisse)", "'Suisse Intl Fallback'", "system-ui", "sans-serif"],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "Monaco", "monospace"],
      },
      colors: {
        bg: "var(--bg)",
        fg: "var(--fg)",
        muted: "var(--muted)",
        border: "var(--border)",
        surface: "var(--surface)",
        accent: "var(--accent)",
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
