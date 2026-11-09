import { redirect } from "next/navigation";
import { headers, cookies } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";

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

  if (lang === "en") {
    redirect("/findaro-landing-en.html");
  }

  redirect("/findaro-landing.html");
}
