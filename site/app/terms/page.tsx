import { LegalPage, legalMetadata } from "@/components/legal-page";
import { CONTACT_EMAIL, LICENSE_URL, REPO_URL, TERMS_UPDATED } from "@/lib/site";

export const metadata = legalMetadata(
  "Terms",
  "The terms for Agent Caffeine: free and open source under the AGPL-3.0, voluntary support through GitHub Sponsors, and what the app does and does not promise.",
  "/terms"
);

export default function Terms() {
  return (
    <LegalPage title="Terms" updated={TERMS_UPDATED}>
      <p>
        These terms cover Agent Caffeine, a macOS app made by me, Mert Duzgun, an individual based
        in Antalya, Türkiye. By using the app you agree to them.
      </p>

      <h2>License</h2>
      <p>
        Agent Caffeine is free and open source. Its source code is{" "}
        <a href={REPO_URL}>on GitHub</a> under the{" "}
        <a href={LICENSE_URL}>GNU Affero General Public License, version 3</a>. That license says
        what you may do with the code. The name Agent Caffeine, the app icon and the robot art are
        not under that license.
      </p>

      <h2>Support</h2>
      <p>
        You can support the project with a payment of an amount you choose, in the{" "}
        <a href="/#support">support section</a> of the home page. It is voluntary and gives you nothing extra: the app is
        the same for everyone. <a href="https://github.com/sponsors/mertbuilds">GitHub Sponsors</a>{" "}
        handles it, one-time or monthly.
      </p>

      <h2>Earlier purchases</h2>
      <p>
        Versions before 1.1.0 were sold and needed a key. Every purchase is refunded, and you do
        not have to do anything. From version 1.1.0 the app needs no key.
      </p>

      <h2>No warranty</h2>
      <p>
        The app is provided as is, without any warranty. A Mac that is kept awake uses battery and
        makes heat. You are responsible for where you leave it.
      </p>

      <h2>Liability</h2>
      <p>
        To the extent the law allows, I am not liable for damage that comes from the use of the app.
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
