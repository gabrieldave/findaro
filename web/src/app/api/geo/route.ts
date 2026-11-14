import { NextResponse } from "next/server";
import { headers, cookies } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { langFromCookieStore } from "@/lib/lang";

export async function GET() {
  const headerList = await headers();
  const cookieStore = await cookies();
  const cookieLang = langFromCookieStore(cookieStore);

  const cfCountry = (
    headerList.get("cf-ipcountry") ||
    headerList.get("x-vercel-ip-country") ||
    headerList.get("x-country") ||
    ""
  ).toUpperCase();

  const lang = detectLanguageFromHeaders(headerList, cookieLang);

  return NextResponse.json({
    country: cfCountry || "US",
    lang,
  });
}
