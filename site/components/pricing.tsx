import { BuyButton } from "@/components/buy-button";
import { DownloadButton } from "@/components/download-button";
import { getLatestRelease, releaseDetails } from "@/lib/release";

export async function Pricing() {
  const release = await getLatestRelease();
  return (
    <section className="mx-auto w-full max-w-[1120px]">
      <div className="mx-auto flex max-w-[640px] flex-col items-center gap-6 rounded-lg border border-border bg-surface px-6 py-12 text-center md:py-16">
        <div className="flex flex-col gap-3">
          <p className="text-7xl font-medium tabular-nums leading-none tracking-[-0.02em]">$9</p>
          <p className="text-muted">Once per Mac. Lifetime updates. No subscription</p>
          {release === null ? null : <p className="text-muted">Try it free for 7 days first</p>}
        </div>
        {release === null ? (
          <BuyButton placement="pricing">Buy agent caffeine</BuyButton>
        ) : (
          <div className="flex flex-col items-center gap-3">
            <div className="flex flex-wrap items-center justify-center gap-3">
              <DownloadButton release={release} placement="pricing">
                Download free trial
              </DownloadButton>
              <BuyButton placement="pricing" variant="outline">
                Buy a key
              </BuyButton>
            </div>
            <p className="text-balance text-sm text-muted">{releaseDetails(release)}</p>
          </div>
        )}
        <p className="text-sm text-muted">Signed, notarized and Gatekeeper clean</p>
      </div>
    </section>
  );
}
