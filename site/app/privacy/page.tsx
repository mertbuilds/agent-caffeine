import { LegalPage, legalMetadata } from "@/components/legal-page";
import { CONTACT_EMAIL, PRIVACY_UPDATED } from "@/lib/site";

export const metadata = legalMetadata(
  "Privacy",
  "What agent caffeine, its purchase and this website collect: no telemetry in the app, Polar for payments, self-hosted analytics with no cookies.",
  "/privacy"
);

export default function Privacy() {
  return (
    <LegalPage title="Privacy" updated={PRIVACY_UPDATED}>
      <p>
        agent caffeine is made and sold by me, Mert Duzgun, an individual based in Antalya, Türkiye.
        I am responsible for the data on this page. Here is what the app, a purchase and this website
        collect, and why.
      </p>

      <h2>The app</h2>
      <p>
        The app has no telemetry, no analytics and no account. To see whether an agent is working,
        it reads the list of running processes on your Mac, the state and session files that Claude
        Code and Codex keep in <code>~/.claude</code> and <code>~/.codex</code>, and the times at
        which other agents write their session files. From those files it takes only the state of
        a session (working, waiting for you or idle), its folder and its name, and shows them in
        the menu. It also reads the battery level and the lid angle of your Mac, to let it sleep
        when the battery is low and to dim the display as the lid closes. None of that leaves your
        Mac.
      </p>
      <p>
        Better detection is off until you switch it on for an agent. agent caffeine then adds a few
        lines to that agent&apos;s own settings file and keeps a backup next to it. The agent
        writes its state to a small file in agent caffeine&apos;s folder on your Mac. That file
        holds the state and the name of the event, and nothing you or the agent typed. When you
        switch better detection off, agent caffeine removes its lines again.
      </p>
      <p>It makes two kinds of network request:</p>
      <ul>
        <li>
          Updates. About once a day it asks caffeinagent.com for the update feed, and when you
          agree to an update it downloads it from there. These requests carry what every download
          request carries, such as your IP address and a user agent with the app&apos;s name and
          version. They carry nothing that identifies you.
        </li>
        <li>
          License. When you enter a key, the app sends it to Polar with your Mac&apos;s model (for
          example &quot;MacBookPro18,3&quot;), never the computer&apos;s name. Polar answers with an
          activation id. About once a day the app sends the key and that activation id to check that
          the key is still good, and it sends them once more when you deactivate the Mac. During the
          free trial the app sends nothing to Polar.
        </li>
      </ul>

      <h2>Buying</h2>
      <p>
        Payments go through <a href="https://polar.sh">Polar</a>, the merchant of record: Polar
        collects the payment, handles tax and sends the invoice. At checkout Polar collects your
        email address, name, billing country and payment details.
      </p>
      <p>
        From Polar I receive your email address, name, country and what you bought. I use them to
        send your license key and to answer support. I never see your card number.
      </p>

      <h2>This website</h2>
      <p>
        I count page views and clicks on the buy and download buttons with OpenPanel, an analytics
        tool I run on my own server at analytics.vinena.studio. The requests go through this site
        first, at <code>/api/op</code>, and carry your IP address and your browser&apos;s user
        agent. There are no cookies and no session recordings.
      </p>
      <p>
        If you pick a light or dark theme, the choice is kept in your browser&apos;s local storage.
        It never leaves your browser.
      </p>
      <p>
        Vercel serves this site, and Cloudflare sits in front of it and stores the app downloads.
        Both see the IP address of each request, as any host does.
      </p>

      <h2>Email</h2>
      <p>If you write to me, I keep the conversation so I can answer you.</p>

      <h2>How long I keep it, and your rights</h2>
      <p>
        I keep purchase records for as long as the law requires for bookkeeping. You can ask me to
        see, correct or delete what I hold about you. I do not sell your data, and I do not share it
        beyond the services named on this page.
      </p>

      <h2>Contact</h2>
      <p>
        Write to me at <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>
    </LegalPage>
  );
}
