import { NextResponse } from "next/server";
import { headers, cookies } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";

export async function GET() {
  const headerList = await headers();
  const cookieStore = await cookies();
  const cookieLang = cookieStore.get("findaro_lang")?.value;

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
