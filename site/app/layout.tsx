import "./globals.css";
import type { Metadata } from "next";
import localFont from "next/font/local";
import { Analytics } from "@/components/analytics";
import { DevKnobs } from "@/components/dev-knobs";
import { agentsMoreThan } from "@/lib/agents";

const suisse = localFont({
  src: [
    { path: "./fonts/SuisseIntl-Regular.woff2", weight: "400", style: "normal" },
    { path: "./fonts/SuisseIntl-Medium.woff2", weight: "500", style: "normal" },
  ],
  variable: "--font-suisse",
  display: "swap",
  adjustFontFallback: false,
});

export const metadata: Metadata = {
  metadataBase: new URL("https://caffeinagent.com"),
  alternates: { canonical: "/" },
  title: "agent caffeine · Keep your Mac awake while AI agents work",
  description:
    `Agent-aware sleep prevention for macOS. Detects Claude Code, Codex, OpenCode and more than ${agentsMoreThan} AI coding agents. Lets the Mac sleep when they are idle. $9 once.`,
  openGraph: {
    title: "agent caffeine",
    description:
      "Keep your Mac awake while AI agents work. Agent-aware sleep prevention for macOS. $9 once.",
    type: "website",
    url: "/",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Keep your Mac awake while your agents work, even with the lid closed",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "agent caffeine",
    description:
      "Keep your Mac awake while AI agents work. Agent-aware sleep prevention for macOS. $9 once.",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={suisse.variable}>
      <body className="bg-bg font-sans text-fg antialiased">
        {children}
        <Analytics />
        <DevKnobs />
      </body>
    </html>
  );
}
