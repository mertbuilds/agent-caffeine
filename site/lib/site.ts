export const SITE_URL = "https://caffeinagent.com";

export const AUTHOR = { "@type": "Person", name: "Mert Duzgun", url: "https://mertbuilds.com" };

export const ORGANIZATION = {
  "@type": "Organization",
  name: "Agent Caffeine",
  url: SITE_URL,
  logo: `${SITE_URL}/icon.png`,
};

/** The OpenPanel server that counts for this site. The browser reaches it through `/api/op`. */
export const OPENPANEL_API_URL = "https://analytics.vinena.studio/api";

/** The app's source code. Not one of our own sites, so links to it carry no campaign tags. */
export const REPO_URL = "https://github.com/mertbuilds/agent-caffeine";

export const LICENSE_URL = "https://www.gnu.org/licenses/agpl-3.0.html";

const supportUrl = process.env.NEXT_PUBLIC_SUPPORT_URL ?? "";

/** The checkout where a reader pays what they want, or null while none is set. */
export const SUPPORT_URL = supportUrl.startsWith("https://") && URL.canParse(supportUrl) ? supportUrl : null;

export const CONTACT_EMAIL = "hi@caffeinagent.com";

export const PRIVACY_UPDATED = "2026-10-12";

export const TERMS_UPDATED = "2026-10-12";
