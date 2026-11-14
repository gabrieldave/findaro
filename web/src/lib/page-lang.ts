import { cookies, headers } from "next/headers";
import { detectLanguageFromHeaders } from "./geo";
import { LANG_HEADER, langFromCookieStore, parseLang, type Lang } from "./lang";

/** Idioma de una página secundaria: ?lang → cabecera del middleware → cookie → país. */
export async function resolvePageLang(searchParams: Promise<{ lang?: string }>): Promise<Lang> {
  const sp = await searchParams;
  const explicit = parseLang(sp?.lang);
  if (explicit) return explicit;
  const headerList = await headers();
  const fromMiddleware = parseLang(headerList.get(LANG_HEADER));
  if (fromMiddleware) return fromMiddleware;
  const cookieStore = await cookies();
  return detectLanguageFromHeaders(headerList, langFromCookieStore(cookieStore), null);
}
