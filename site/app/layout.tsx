import "./globals.css";
import type { Metadata } from "next";
import { Analytics } from "@/components/analytics";
import { DevKnobs } from "@/components/dev-knobs";
import { HashScroll } from "@/components/hash-scroll";
import { Header } from "@/components/header";
import { SendToMacPopup } from "@/components/send-to-mac-popup";
import { suisse } from "@/lib/fonts";
import { PRICE } from "@/lib/pricing";
import { THEME_SCRIPT } from "@/lib/theme";

const offer = `Free for 7 days, then ${PRICE} once.`;

export const metadata: Metadata = {
  metadataBase: new URL("https://caffeinagent.com"),
  alternates: { canonical: "/" },
  title: "Agent Caffeine · Keep your Mac awake while AI agents work",
  description:
    `Agent Caffeine keeps your Mac awake while AI coding agents work, also with the lid closed, and lets it sleep when they are done. ${offer}`,
  openGraph: {
    title: "Agent Caffeine",
    description:
      `Keep your Mac awake while AI agents work. Agent-aware sleep prevention for macOS. ${offer}`,
    type: "website",
    url: "/",
    images: [
      {
        url: "/og.png",
        width: 1200,
        height: 630,
        alt: "Agent Caffeine. Close your lid, come back to finished work",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Agent Caffeine",
    description:
      `Keep your Mac awake while AI agents work. Agent-aware sleep prevention for macOS. ${offer}`,
    images: ["/og.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    // The head's script sets `data-theme` before hydration; that one attribute may differ.
    // `data-scroll-behavior` lets Next jump, not glide, to the top of a new page.
    <html lang="en" className={suisse.variable} data-scroll-behavior="smooth" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body className="bg-bg font-sans text-fg antialiased">
        <a
          href="#main"
          className="sr-only left-2 top-2 z-40 rounded-full bg-bg text-sm no-underline shadow-[0_8px_32px_var(--shadow)] focus-visible:not-sr-only focus-visible:fixed focus-visible:px-4 focus-visible:py-1.5"
        >
          Skip to content
        </a>
        <Header />
        {children}
        <HashScroll />
        <SendToMacPopup />
        <Analytics />
        <DevKnobs />
      </body>
    </html>
  );
}
