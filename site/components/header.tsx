import { SiteHeader } from "@/components/site-header";
import { getLatestRelease } from "@/lib/release";

export async function Header() {
  const release = await getLatestRelease();
  return <SiteHeader release={release} />;
}
