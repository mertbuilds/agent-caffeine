import type { Metadata } from "next";
import { Footer } from "@/components/footer";
import { PILL, SIZES } from "@/components/pill";
import { REPO_URL, SUPPORT_URL } from "@/lib/site";

const title = "Support · Agent Caffeine";
const description =
  "Agent Caffeine is free and open source. If it helps you, you can support the work with an amount you choose.";

export const metadata: Metadata = {
  title,
  description,
  alternates: { canonical: "/support" },
  openGraph: { title, description, type: "website", url: "/support", images: ["/og.png"] },
  twitter: { card: "summary_large_image", title, description, images: ["/og.png"] },
};

export default function Support() {
  return (
    <main id="main" className="relative isolate flex min-h-screen flex-col gap-12 overflow-x-clip px-4 pt-[6.5rem] md:px-6">
      <div className="mx-auto flex w-full max-w-[680px] flex-1 flex-col items-start gap-8 pb-12">
        <h1 className="text-balance text-[2rem] font-medium leading-[1.15] tracking-[-0.01em] md:text-[2.5rem]">
          Support Agent Caffeine
        </h1>
        <div className="flex flex-col gap-4 text-pretty leading-relaxed">
          <p>Agent Caffeine is free and open source. Every feature is in it, with no account and no card.</p>
          <p>
            If it helps you, you can support the work. You choose the amount. It helps me keep the app
            maintained: new agents, new versions of macOS, and fixes.
          </p>
          <p className="text-muted">
            Support is a gift. It unlocks nothing, and the app is the same for everyone.
          </p>
        </div>
        {SUPPORT_URL === null ? (
          <div className="flex flex-col gap-4 text-pretty leading-relaxed">
            <p>Support is not set up yet.</p>
            <p>
              <a href={REPO_URL}>The source code is on GitHub</a>
            </p>
          </div>
        ) : (
          <div className="flex flex-col items-start gap-4">
            <a href={SUPPORT_URL} className={`${PILL} bg-fg text-bg ${SIZES.large}`}>
              Support the project
            </a>
            <p className="text-sm text-muted">
              Polar handles the payment. <a href={REPO_URL}>The source code is on GitHub</a>
            </p>
          </div>
        )}
      </div>
      <Footer />
    </main>
  );
}
