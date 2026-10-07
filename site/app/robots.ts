import type { MetadataRoute } from "next";
import { DOWNLOAD_PATH } from "@/lib/download";
import { SITE_URL } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    // `/download` counts each request as a download, so crawlers stay out. The dmg under `/mac/` stays open.
    rules: { userAgent: "*", allow: "/", disallow: DOWNLOAD_PATH },
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
