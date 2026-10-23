import { createFileRoute } from '@tanstack/react-router';
import { LegalPage } from '../components/legal-page.tsx';
import { Rich } from '../components/rich.tsx';
import { pageHead, PRIVACY_UPDATED } from '../lib/seo.ts';
import { CONTACT_EMAIL } from '../lib/site.ts';
import { m } from '../paraglide/messages.js';

export const Route = createFileRoute('/privacy')({
  component: Privacy,
  head: () =>
    pageHead({
      description: m.privacy_meta_description(),
      path: '/privacy',
      title: m.privacy_meta_title(),
    }),
});

function Privacy() {
  return (
    <LegalPage title={m.privacy_title()} updated={PRIVACY_UPDATED}>
      <p>{m.privacy_intro()}</p>

      <h2>{m.privacy_app_heading()}</h2>
      <p>
        <Rich text={m.privacy_app_reads()} />
      </p>
      <p>{m.privacy_app_detection()}</p>
      <p>{m.privacy_app_requests()}</p>
      <ul>
        <li>{m.privacy_app_updates()}</li>
        <li>{m.privacy_app_license()}</li>
      </ul>

      <h2>{m.privacy_buying_heading()}</h2>
      <p>
        <Rich text={m.privacy_buying_polar()} />
      </p>
      <p>{m.privacy_buying_received()}</p>

      <h2>{m.privacy_site_heading()}</h2>
      <p>
        <Rich text={m.privacy_site_analytics()} />
      </p>
      <p>{m.privacy_site_download()}</p>
      <p>
        <Rich text={m.privacy_site_source()} />
      </p>
      <p>{m.privacy_site_theme()}</p>
      <p>{m.privacy_site_hosts()}</p>

      <h2>{m.privacy_email_heading()}</h2>
      <p>{m.privacy_email()}</p>

      <h2>{m.privacy_rights_heading()}</h2>
      <p>{m.privacy_rights()}</p>

      <h2>{m.legal_contact_heading()}</h2>
      <p>
        <Rich text={m.privacy_contact({ email: CONTACT_EMAIL })} />
      </p>
    </LegalPage>
  );
}
