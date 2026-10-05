import type { MetadataRoute } from "next";
import { getPosts } from "@/lib/blog";
import { PRIVACY_UPDATED, SITE_URL, TERMS_UPDATED } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const posts = getPosts();
  return [
    { url: SITE_URL },
    { url: `${SITE_URL}/blog`, lastModified: posts[0]?.updated },
    ...posts.map((post) => ({ url: `${SITE_URL}/blog/${post.slug}`, lastModified: post.updated })),
    { url: `${SITE_URL}/privacy`, lastModified: PRIVACY_UPDATED },
    { url: `${SITE_URL}/terms`, lastModified: TERMS_UPDATED },
  ];
}
