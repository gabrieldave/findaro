/**
 * Idioma del sitio. Cookie oficial: `findaro-lang`.
 * `findaro_lang` (guion bajo) es la cookie anterior: se sigue leyendo para no
 * perder la preferencia de visitantes recurrentes y se migra en el middleware.
 * Este archivo no importa nada de servidor: se puede usar en cliente y en edge.
 */
export type Lang = "en" | "es";

export const LANG_COOKIE = "findaro-lang";
export const LEGACY_LANG_COOKIE = "findaro_lang";
export const LANG_HEADER = "x-findaro-lang";
export const LANG_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

export function parseLang(raw: unknown): Lang | null {
  return raw === "en" || raw === "es" ? raw : null;
}

/** Lee el idioma desde una cabecera `Cookie` cruda (API routes). Prioriza la cookie nueva. */
export function langFromCookieHeader(cookieHeader: string | null | undefined): Lang | null {
  const header = cookieHeader || "";
  const current = header.match(/(?:^|;\s*)findaro-lang=(en|es)(?:;|$)/);
  if (current) return current[1] as Lang;
  const legacy = header.match(/(?:^|;\s*)findaro_lang=(en|es)(?:;|$)/);
  return legacy ? (legacy[1] as Lang) : null;
}

/** Para `cookies()` de next/headers (o cualquier objeto con `get`). */
export function langFromCookieStore(store: { get(name: string): { value: string } | undefined }): Lang | null {
  return parseLang(store.get(LANG_COOKIE)?.value) ?? parseLang(store.get(LEGACY_LANG_COOKIE)?.value);
}

/** Cliente: idioma guardado en `document.cookie`. */
export function readClientLang(): Lang | null {
  if (typeof document === "undefined") return null;
  return langFromCookieHeader(document.cookie);
}

/** Cliente: guarda la preferencia y retira la cookie antigua. */
export function writeClientLang(lang: Lang): void {
  if (typeof document === "undefined") return;
  document.cookie = `${LANG_COOKIE}=${lang}; path=/; max-age=${LANG_COOKIE_MAX_AGE}; samesite=lax`;
  document.cookie = `${LEGACY_LANG_COOKIE}=; path=/; max-age=0`;
}

/** Ruta de la landing para cada idioma. */
export function landingPath(lang: Lang): string {
  return lang === "es" ? "/es" : "/";
}
