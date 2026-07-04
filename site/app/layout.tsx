import "./globals.css";
import type { Metadata } from "next";
import { Analytics } from "@/components/analytics";

export const metadata: Metadata = {
  metadataBase: new URL("https://caffeinagent.com"),
  title: "agent caffeine · keep your mac awake while ai agents work",
  description:
    "agent-aware sleep prevention for macos. detects claude code, codex, opencode, and 40+ ai coding agents. sleeps when they're idle. $9 one-time.",
  openGraph: {
    title: "agent caffeine",
    description:
      "keep your mac awake while ai agents work. agent-aware sleep prevention for macos. $9 one-time.",
    type: "website",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "keep your mac awake. while your agents are working. even with the lid closed.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "agent caffeine",
    description:
      "keep your mac awake while ai agents work. agent-aware sleep prevention for macos. $9 one-time.",
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="antialiased">
        {children}
        <Analytics />
      </body>
    </html>
  );
}
