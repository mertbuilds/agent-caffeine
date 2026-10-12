import { LegalPage, legalMetadata } from "@/components/legal-page";
import { CONTACT_EMAIL, PRIVACY_UPDATED } from "@/lib/site";

export const metadata = legalMetadata(
  "Privacy",
  "What Agent Caffeine and this website collect: no telemetry in the app, Polar for voluntary support payments, self-hosted analytics with no cookies.",
  "/privacy"
);

export default function Privacy() {
  return (
    <LegalPage title="Privacy" updated={PRIVACY_UPDATED}>
      <p>
        Agent Caffeine is made by me, Mert Duzgun, an individual based in Antalya, Türkiye. I am
        responsible for the data on this page. Here is what the app and this website collect, and
        why.
      </p>

      <h2>The app</h2>
      <p>
        The app has no telemetry, no analytics and no account. To see whether an agent is working,
        it reads the list of running processes on your Mac, the state and session files that Claude
        Code and Codex keep in <code>~/.claude</code> and <code>~/.codex</code>, and the times at
        which other agents write their session files. From those files it takes only the state of
        a session (working, waiting for you or idle), its folder and its name, and shows them in
        the menu. For Cursor it reads the transcript files in <code>~/.cursor/projects</code>.
        From those it takes only where a turn starts and ends and the time the file was last
        written, never the text. It also reads the battery level and the lid angle of your Mac, to let it sleep
        when the battery is low and to dim the display as the lid closes. None of that leaves your
        Mac.
      </p>
      <p>
        Better detection is off until you switch it on for an agent. Agent Caffeine then adds a few
        lines to that agent&apos;s own settings file and keeps a backup next to it. The agent
        writes its state to a small file in Agent Caffeine&apos;s folder on your Mac. That file
        holds the state and the name of the event, and nothing you or the agent typed. When you
        switch better detection off, Agent Caffeine removes its lines again.
      </p>
      <p>
        It makes one kind of network request: updates. About once a day it asks caffeinagent.com
        for the update feed, and when you agree to an update it downloads it from there. These
        requests carry what every download request carries, such as your IP address and a user
        agent with the app&apos;s name and version. They carry nothing that identifies you.
      </p>
      <p>
        Versions before 1.1.0 were sold and needed a key. Such a version still sends its key and
        an activation id to <a href="https://polar.sh">Polar</a> about once a day, until you update
        it. From version 1.1.0 the app has no key and sends nothing to Polar.
      </p>

      <h2>Support</h2>
      <p>
        The app is free. If you choose to support it, the payment goes through{" "}
        <a href="https://polar.sh">Polar</a>, the merchant of record: Polar collects the payment,
        handles tax and sends the invoice. At checkout Polar collects your email address, name,
        billing country and payment details.
      </p>
      <p>
        From Polar I receive your email address, name, country and the amount. I never see your
        card number. The same is true for a purchase made before the app became free.
      </p>

      <h2>This website</h2>
      <p>
        I count page views and clicks on this site with OpenPanel, an analytics tool I run on my
        own server at analytics.vinena.studio. It also records how the page is used: pointer
        movement, scrolling and clicks. I watch these recordings to find where the page is unclear
        and to improve it. A recording shows only this site, never the rest of your screen, and
        anything typed into a field is hidden. The requests go through this site first, at{" "}
        <code>/api/op</code>, and carry your IP address and your browser&apos;s user agent. There
        are no cookies. The app itself sends none of this.
      </p>
      <p>
        When you download the app, the site also counts the download on the server, with no
        cookie: the version, where on the page the button was, the source of the link that brought
        you here, and the country and the kind of browser, taken from your IP address and user
        agent.
      </p>
      <p>
        If the link that brought you here names its source (for example{" "}
        <code>utm_source</code>), your browser keeps that source until you close the tab. The page
        view and the download count carry it, so I can see which link led to a download.
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
        I keep the records of support payments, and of purchases and refunds from before the app
        became free, for as long as the law requires for bookkeeping. You can ask me to
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
