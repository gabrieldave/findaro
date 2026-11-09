import { redirect } from "next/navigation";
import { headers } from "next/headers";

export default async function Home(props: {
  searchParams: Promise<{ ref?: string; lang?: string }>;
}) {
  const searchParams = await props.searchParams;
  const ref = searchParams?.ref;
  const explicitLang = searchParams?.lang;

  const headerList = await headers();
  const acceptLang = headerList.get("accept-language") || "";
  const isEnglish = explicitLang === "en" || (!explicitLang && acceptLang.toLowerCase().startsWith("en"));

  if (ref) {
    redirect(`/comprar?ref=${encodeURIComponent(ref)}${isEnglish ? "&lang=en" : ""}`);
  }

  if (isEnglish) {
    redirect("/findaro-landing-en.html");
  }

  redirect("/findaro-landing.html");
}
