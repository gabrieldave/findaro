import type { MetadataRoute } from "next";
import { PUBLIC_APP_URL } from "@/lib/site";

function localized(path: string, lang: "en" | "es"): string {
  const base = PUBLIC_APP_URL.replace(/\/$/, "");
  const join = path === "/" ? `${base}/` : `${base}${path}`;
  return `${join}?lang=${lang}`;
}

export default function sitemap(): MetadataRoute.Sitemap {
  const paths = ["/", "/comprar", "/probar", "/terminos", "/privacidad", "/reembolso"] as const;
  const now = new Date();

  return paths.map((path) => ({
    url: localized(path, "en"),
    lastModified: now,
    changeFrequency: path === "/" ? "weekly" : "monthly",
    priority: path === "/" ? 1 : path === "/comprar" || path === "/probar" ? 0.9 : 0.5,
    alternates: {
      languages: {
        en: localized(path, "en"),
        es: localized(path, "es"),
        "x-default": localized(path, "en"),
      },
    },
  }));
}
