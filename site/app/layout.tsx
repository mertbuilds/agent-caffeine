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
        url: "/laptop-on-copier.jpg",
        width: 1600,
        height: 854,
        alt: "a macbook propped open on a xerox photocopier so the lid doesn't close",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "agent caffeine",
    description:
      "keep your mac awake while ai agents work. agent-aware sleep prevention for macos. $9 one-time.",
    images: ["/laptop-on-copier.jpg"],
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
