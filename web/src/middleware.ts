import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { SPANISH_COUNTRIES } from "./lib/geo";
import {
  LANG_COOKIE,
  LANG_COOKIE_MAX_AGE,
  LANG_HEADER,
  LEGACY_LANG_COOKIE,
  parseLang,
  type Lang,
} from "./lib/lang";

/** Bots y previsualizadores: nunca se redirigen, así Google indexa `/` y `/es` con su hreflang. */
const BOT_UA =
  /bot|crawl|spider|slurp|bingpreview|facebookexternalhit|embedly|quora link preview|whatsapp|telegram|slack|discord|lighthouse|headlesschrome|preview/i;

function countryOf(request: NextRequest): string {
  return (
    request.headers.get("cf-ipcountry") ||
    request.headers.get("x-vercel-ip-country") ||
    request.headers.get("x-country") ||
    request.headers.get("geoip-country-code") ||
    ""
  )
    .toUpperCase()
    .trim();
}

function geoLang(request: NextRequest): Lang | null {
  const country = countryOf(request);
  if (country && country !== "XX" && country !== "T1") {
    return SPANISH_COUNTRIES.has(country) ? "es" : "en";
  }
  return null;
}

function acceptLang(request: NextRequest): Lang {
  const accept = (request.headers.get("accept-language") || "").toLowerCase();
  return accept.startsWith("es") || accept.includes(",es") || accept.includes(";es") ? "es" : "en";
}

function withoutLangParam(url: URL): URL {
  const next = new URL(url);
  next.searchParams.delete("lang");
  return next;
}

function setLangCookie(res: NextResponse, lang: Lang) {
  res.cookies.set(LANG_COOKIE, lang, { maxAge: LANG_COOKIE_MAX_AGE, path: "/", sameSite: "lax" });
}

function persistAttribution(request: NextRequest, res: NextResponse) {
  const sp = request.nextUrl.searchParams;
  const utm = {
    utm_source: sp.get("utm_source") || "",
    utm_medium: sp.get("utm_medium") || "",
    utm_campaign: sp.get("utm_campaign") || "",
    utm_content: sp.get("utm_content") || "",
  };
  if (utm.utm_source || utm.utm_medium || utm.utm_campaign || utm.utm_content) {
    // First-touch UTM en cookie de 30 días.
    res.cookies.set("findaro_utm", JSON.stringify(utm), { maxAge: 60 * 60 * 24 * 30, path: "/", sameSite: "lax" });
  }
  const refRaw = (sp.get("ref") || "").trim();
  if (/^[A-Za-z0-9-]{3,32}$/.test(refRaw)) {
    res.cookies.set("findaro_ref", refRaw.toUpperCase(), { maxAge: 60 * 60 * 24 * 30, path: "/", sameSite: "lax" });
  }
}

export function middleware(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;
  const isBot = BOT_UA.test(request.headers.get("user-agent") || "");

  // 1. Landings estáticas antiguas → nuevas rutas nativas (301, conservando UTM/ref).
  if (pathname === "/findaro-landing-en.html" || pathname === "/findaro-landing.html") {
    const lang: Lang = pathname === "/findaro-landing.html" ? "es" : "en";
    const url = withoutLangParam(request.nextUrl);
    url.pathname = lang === "es" ? "/es" : "/";
    const res = NextResponse.redirect(url, 301);
    setLangCookie(res, lang);
    persistAttribution(request, res);
    return res;
  }

  const queryLang = parseLang(searchParams.get("lang"));
  const currentCookie = parseLang(request.cookies.get(LANG_COOKIE)?.value);
  const legacyCookie = parseLang(request.cookies.get(LEGACY_LANG_COOKIE)?.value);
  const cookieLang = currentCookie ?? legacyCookie;
  const isLandingEn = pathname === "/";
  const isLandingEs = pathname === "/es" || pathname === "/es/";

  // 2. Landing: primero la cookie `findaro-lang`, después CF-IPCountry.
  if (isLandingEn || isLandingEs) {
    const explicit = queryLang ?? cookieLang;
    let target: Lang = isLandingEs ? "es" : "en";
    if (explicit) {
      target = explicit;
    } else if (isLandingEn && !isBot) {
      // Sin preferencia guardada: los países hispanohablantes van a /es.
      target = geoLang(request) ?? acceptLang(request);
    }

    const needsMove = !isBot && ((isLandingEn && target === "es") || (isLandingEs && target === "en"));
    if (needsMove || queryLang) {
      const url = withoutLangParam(request.nextUrl);
      url.pathname = target === "es" ? "/es" : "/";
      const res = NextResponse.redirect(url, 307);
      if (queryLang) setLangCookie(res, queryLang);
      persistAttribution(request, res);
      return res;
    }
  }

  // 3. Idioma para <html lang> y para las páginas que se traducen en servidor.
  const pageLang: Lang = isLandingEs
    ? "es"
    : isLandingEn
      ? "en"
      : (queryLang ?? cookieLang ?? geoLang(request) ?? acceptLang(request));
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(LANG_HEADER, pageLang);

  const res = NextResponse.next({ request: { headers: requestHeaders } });

  if (queryLang) {
    setLangCookie(res, queryLang);
  } else if (!currentCookie && legacyCookie) {
    // Migración de la cookie anterior `findaro_lang` → `findaro-lang`.
    setLangCookie(res, legacyCookie);
  }
  if (legacyCookie) res.cookies.delete(LEGACY_LANG_COOKIE);

  persistAttribution(request, res);
  return res;
}

export const config = {
  matcher: [
    "/findaro-landing.html",
    "/findaro-landing-en.html",
    "/((?!api|_next/static|_next/image|favicon.ico|.*\\.[A-Za-z0-9]+$).*)",
  ],
};
