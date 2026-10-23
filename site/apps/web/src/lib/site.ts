/** The one origin the site answers on. `www` and plain http are sent here. */
export const SITE_URL = 'https://caffeinagent.com';

/** The OpenPanel server that counts for this site. The browser reaches it through `/api/op`. */
export const OPENPANEL_API_URL = 'https://analytics.vinena.studio/api';

export const CONTACT_EMAIL = 'hi@caffeinagent.com';

/** A link to one of Mert's own sites, tagged with where on this site it sits. */
export function ownLink(url: string, placement: string): string {
  const link = new URL(url);
  link.searchParams.set('utm_source', 'caffeinagent.com');
  link.searchParams.set('utm_medium', 'referral');
  link.searchParams.set('utm_campaign', placement);
  return link.href;
}

export const MERTBUILDS_URL = ownLink('https://mertbuilds.com/', 'footer');
