import { createFileRoute } from '@tanstack/react-router';
import { LegalPage } from '../components/legal-page.tsx';
import { Rich } from '../components/rich.tsx';
import { FULL_PRICE, LAUNCH_PRICE_ACTIVE, MACS, PRICE, dollars } from '../lib/pricing.ts';
import { pageHead, TERMS_UPDATED } from '../lib/seo.ts';
import { CONTACT_EMAIL } from '../lib/site.ts';
import { m } from '../paraglide/messages.js';

export const Route = createFileRoute('/terms')({
  component: Terms,
  head: () =>
    pageHead({
      description: m.terms_meta_description({ macs: MACS, price: PRICE }),
      path: '/terms',
      title: m.terms_meta_title(),
    }),
});

function Terms() {
  return (
    <LegalPage title={m.terms_title()} updated={TERMS_UPDATED}>
      <p>{m.terms_intro()}</p>

      <h2>{m.terms_get_heading()}</h2>
      <p>{m.terms_get_macs({ macs: MACS })}</p>
      <p>{m.terms_get_updates()}</p>

      <h2>{m.terms_trial_heading()}</h2>
      <p>{m.terms_trial()}</p>

      <h2>{m.terms_price_heading()}</h2>
      <p>
        <Rich
          text={
            LAUNCH_PRICE_ACTIVE
              ? m.terms_price_launch({ full: dollars(FULL_PRICE), price: PRICE })
              : m.terms_price({ price: PRICE })
          }
        />
      </p>

      <h2>{m.terms_refunds_heading()}</h2>
      <p>{m.terms_refunds()}</p>

      <h2>{m.terms_fair_heading()}</h2>
      <p>{m.terms_fair()}</p>

      <h2>{m.terms_warranty_heading()}</h2>
      <p>{m.terms_warranty()}</p>

      <h2>{m.terms_liability_heading()}</h2>
      <p>{m.terms_liability()}</p>

      <h2>{m.terms_changes_heading()}</h2>
      <p>{m.terms_changes()}</p>

      <h2>{m.legal_contact_heading()}</h2>
      <p>
        <Rich text={m.terms_contact({ email: CONTACT_EMAIL })} />
      </p>
    </LegalPage>
  );
}
