export const APP_ID = "findaro";
export const PRODUCT_NAME = "FINDARO";
export const WHATSAPP = "https://wa.me/525645674407";
export const PUBLIC_APP_URL =
  process.env.NEXT_PUBLIC_APP_URL ?? "https://findaro.iareal.net";
export const PAYMENT_GATEWAY_URL =
  process.env.PAYMENT_GATEWAY_URL ??
  "https://n8n.vibesystems.tech/webhook/findaro-payment";
export const VERIFY_GATEWAY_URL =
  process.env.VERIFY_GATEWAY_URL ??
  "https://n8n.vibesystems.tech/webhook/findaro-verify";
export const DMG_UPSTREAM_URL =
  process.env.DMG_UPSTREAM_URL ??
  // Preferir alias fresco; Findaro-latest.dmg a veces queda en caché de Cloudflare.
  "https://ordena.iareal.net/downloads/Findaro-current.dmg";
export const LATEST_JSON_URL =
  process.env.LATEST_JSON_URL ??
  "https://ordena.iareal.net/downloads/latest.json";

/** Resuelve el DMG versionado del feed (evita caché stale de Findaro-latest.dmg). */
export async function resolveDmgUpstreamUrl(): Promise<string> {
  try {
    const res = await fetch(LATEST_JSON_URL, { cache: "no-store" });
    if (res.ok) {
      const data = (await res.json()) as { findaro_dmg_url?: string; dmg_url?: string };
      if (typeof data.findaro_dmg_url === "string" && data.findaro_dmg_url.startsWith("https://")) {
        return data.findaro_dmg_url;
      }
    }
  } catch {
    // fallback abajo
  }
  return DMG_UPSTREAM_URL;
}
