import type { Metadata } from "next";
import { Suspense } from "react";
import styles from "../marketing.module.css";
import ComprarClient from "./ComprarClient";

type Props = { searchParams: Promise<{ lang?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const sp = await searchParams;
  const lang = sp.lang === "es" ? "es" : "en";
  const isEn = lang === "en";
  const og = isEn ? "https://findaro.iareal.net/og-en.png" : "https://findaro.iareal.net/og-es.png";
  const title = isEn ? "Buy FINDARO — Lifetime License" : "Comprar FINDARO — Licencia de por vida";
  const description = isEn
    ? "Lifetime FINDARO for macOS from $29. Personal 1 Mac, Pro 2 Macs, Family/Studio 5 Macs."
    : "FINDARO de por vida para macOS desde $29. Personal 1 Mac, Pro 2 Macs, Familiar/Studio 5 Macs.";
  return {
    title,
    description,
    openGraph: {
      title,
      description,
      url: `https://findaro.iareal.net/comprar?lang=${lang}`,
      images: [{ url: og, width: 1200, height: 630, alt: "FINDARO" }],
      locale: isEn ? "en_US" : "es_MX",
      type: "website",
    },
    twitter: { card: "summary_large_image", title, description, images: [og] },
  };
}

export default function ComprarPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <ComprarClient />
    </Suspense>
  );
}
