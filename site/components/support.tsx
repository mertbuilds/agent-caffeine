import { PILL, SIZES } from "@/components/pill";
import { SupportCta } from "@/components/track";
import { REPO_URL, SUPPORT_URL } from "@/lib/site";

/** The closing ask of the home page. `/support`, where the app and old links point, redirects here. */
export function Support() {
  return (
    <section id="support" className="mx-auto flex w-full max-w-[640px] scroll-mt-20 flex-col gap-6">
      <h2 className="text-balance text-[1.75rem] font-medium leading-[1.2] tracking-[-0.01em]">
        Support Agent Caffeine
      </h2>
      <div className="flex flex-col gap-4 text-pretty leading-relaxed">
        <p>
          Agent Caffeine is free and open source. If it helps you, you can support the work. You
          choose the amount.
        </p>
        <p className="text-muted">Support is a gift. It unlocks nothing, and the app is the same for everyone.</p>
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
          <SupportCta href={SUPPORT_URL} placement="section" className={`${PILL} bg-fg text-bg ${SIZES.large}`}>
            Support the project
          </SupportCta>
          <p className="text-pretty text-sm text-muted">
            GitHub Sponsors handles it: one-time or monthly, any amount. <a href={REPO_URL}>The source code is on GitHub</a>
          </p>
        </div>
      )}
    </section>
  );
}
