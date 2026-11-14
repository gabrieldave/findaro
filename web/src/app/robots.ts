import type { MetadataRoute } from "next";
import { PUBLIC_APP_URL } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  const base = PUBLIC_APP_URL.replace(/\/$/, "");
  return {
    rules: [
      {
        userAgent: "*",
        allow: ["/", "/es", "/comprar", "/probar", "/comparar", "/soporte", "/terminos", "/privacidad", "/reembolso"],
        disallow: ["/api/", "/admin", "/gracias"],
      },
    ],
    sitemap: `${base}/sitemap.xml`,
    host: base,
  };
}
