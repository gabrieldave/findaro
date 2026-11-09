import { headers, cookies } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { redirect } from "next/navigation";
import fs from "fs";
import path from "path";

export default async function Home(props: {
  searchParams: Promise<{ ref?: string; lang?: string }>;
}) {
  const searchParams = await props.searchParams;
  const ref = searchParams?.ref;
  const explicitLang = searchParams?.lang;

  const headerList = await headers();
  const cookieStore = await cookies();
  const cookieLang = cookieStore.get("findaro_lang")?.value;

  const lang = detectLanguageFromHeaders(headerList, cookieLang, explicitLang);

  if (ref) {
    redirect(`/comprar?ref=${encodeURIComponent(ref)}&lang=${lang}`);
  }

  // If App Router renders this page (in case rewrite falls through to the server component):
  const fileName = lang === "es" ? "findaro-landing.html" : "findaro-landing-en.html";
  const filePath = path.join(process.cwd(), "public", fileName);
  try {
    const html = fs.readFileSync(filePath, "utf-8");
    return (
      <div
        dangerouslySetInnerHTML={{ __html: html }}
        suppressHydrationWarning
      />
    );
  } catch {
    return null;
  }
}
