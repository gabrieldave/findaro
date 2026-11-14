import type { MetadataRoute } from "next";
import { PUBLIC_APP_URL } from "@/lib/site";

const base = PUBLIC_APP_URL.replace(/\/$/, "");

export default function sitemap(): MetadataRoute.Sitemap {
  const now = new Date();
  const landing = {
    en: `${base}/`,
    es: `${base}/es`,
  };
  const entries: MetadataRoute.Sitemap = [
    {
      url: landing.en,
      lastModified: now,
      changeFrequency: "weekly",
      priority: 1,
      alternates: { languages: { en: landing.en, es: landing.es, "x-default": landing.en } },
    },
    {
      url: landing.es,
      lastModified: now,
      changeFrequency: "weekly",
      priority: 1,
      alternates: { languages: { en: landing.en, es: landing.es, "x-default": landing.en } },
    },
  ];
  const paths = ["/comprar", "/probar", "/comparar", "/soporte", "/terminos", "/privacidad", "/reembolso"] as const;
  for (const path of paths) {
    const en = `${base}${path}?lang=en`;
    const es = `${base}${path}?lang=es`;
    entries.push({
      url: en,
      lastModified: now,
      changeFrequency: "monthly",
      priority: path === "/comprar" || path === "/probar" ? 0.9 : 0.5,
      alternates: { languages: { en, es, "x-default": en } },
    });
  }
  return entries;
}
