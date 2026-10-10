import "./globals.css";
import type { Metadata } from "next";
import localFont from "next/font/local";
import { Analytics } from "@/components/analytics";
import { DevKnobs } from "@/components/dev-knobs";
import { HashScroll } from "@/components/hash-scroll";
import { Header } from "@/components/header";
import { SendToMacPopup } from "@/components/send-to-mac-popup";
import { PRICE } from "@/lib/pricing";
import { getLatestRelease } from "@/lib/release";
import { THEME_SCRIPT } from "@/lib/theme";

const suisse = localFont({
  src: [
    { path: "./fonts/SuisseIntl-Regular.woff2", weight: "400", style: "normal" },
    { path: "./fonts/SuisseIntl-Medium.woff2", weight: "500", style: "normal" },
  ],
  variable: "--font-suisse",
  display: "swap",
  adjustFontFallback: false,
});

/** The free trial is in the descriptions only while there is a download to start it with. */
export async function generateMetadata(): Promise<Metadata> {
  const offer = (await getLatestRelease()) === null ? `${PRICE} once.` : `Free for 7 days, then ${PRICE} once.`;
  return {
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
}

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
