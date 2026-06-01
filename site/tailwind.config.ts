import type { Config } from "tailwindcss";

export default {
  content: ["./app/**/*.{ts,tsx,mdx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["ui-sans-serif", "system-ui", "-apple-system", "Helvetica Neue", "Arial"],
        mono: ["ui-monospace", "SFMono-Regular", "Menlo", "Monaco", "monospace"],
      },
      colors: {
        ink: "#0a0a0a",
        paper: "#fafaf7",
        cream: "#f5f1e8",
        accent: "#c4561e",
      },
    },
  },
  plugins: [],
} satisfies Config;
