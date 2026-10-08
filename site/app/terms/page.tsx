import { LegalPage, legalMetadata } from "@/components/legal-page";
import { PLANS, PRICE_LIST, dollars, macs } from "@/lib/pricing";
import { CONTACT_EMAIL, TERMS_UPDATED } from "@/lib/site";

export const metadata = legalMetadata(
  "Terms",
  `The terms for Agent Caffeine: what a license key covers, a 7-day free trial, ${PRICE_LIST}, paid once through Polar, and what the app does and does not promise.`,
  "/terms"
);

export default function Terms() {
  return (
    <LegalPage title="Terms" updated={TERMS_UPDATED}>
      <p>
        These terms cover Agent Caffeine, a macOS app made and sold by me, Mert Duzgun, an
        individual based in Antalya, Türkiye. By buying or using the app you agree to them.
      </p>

      <h2>What you get</h2>
      <p>
        {PLANS.length === 1
          ? "A license key lets you use Agent Caffeine on one Mac at a time."
          : "A license key lets you use Agent Caffeine on one Mac at a time, or on up to three Macs at a time, depending on the plan you buy."}{" "}
        To move it to another Mac, deactivate it on a Mac you no longer use, in the app or in your
        Polar purchases, then enter it on the new one.
      </p>
      <p>
        Your key includes lifetime updates. Lifetime updates means that updates are included for as
        long as Agent Caffeine is developed. I do not promise any future features.
      </p>

      <h2>Free trial</h2>
      <p>
        You can try the app for 7 days with every feature. After that it stops keeping your Mac
        awake until you enter a license key.
      </p>

      <h2>Price and payment</h2>
      <p>
        {PLANS.map((plan, index) => (
          <span key={plan.id}>
            {index === 0 ? "A key" : " A key"} for {macs(plan)} costs {dollars(plan)}, paid once.
          </span>
        ))}{" "}
        <a href="https://polar.sh">Polar</a> sells it as the merchant of
        record: Polar takes the payment, adds taxes where they apply and sends the invoice.
      </p>

      <h2>Refunds</h2>
      <p>
        All sales are final, and there are no refunds after purchase, because the full app is free
        to try for 7 days first. This does not limit any right that consumer law in your country
        gives you and that cannot be waived.
      </p>

      <h2>Fair use</h2>
      <p>Do not resell or share your key. I may turn off a key that I find shared.</p>

      <h2>No warranty</h2>
      <p>
        The app is provided as is, without any warranty. A Mac that is kept awake uses battery and
        makes heat. You are responsible for where you leave it.
      </p>

      <h2>Liability</h2>
      <p>
        To the extent the law allows, my liability for anything to do with the app is limited to the
        amount you paid for it.
      </p>

      <h2>Changes</h2>
      <p>
        I may change these terms. The date at the top shows when they last changed.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about these terms go to <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>
    </LegalPage>
  );
}
