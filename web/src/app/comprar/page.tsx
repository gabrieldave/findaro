import type { Metadata } from "next";
import { Suspense } from "react";
import { mono, sans } from "@/components/landing/fonts";
import styles from "../light.module.css";
import ComprarClient from "./ComprarClient";

type Props = { searchParams: Promise<{ lang?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const sp = await searchParams;
  const lang = sp.lang === "es" ? "es" : "en";
  const isEn = lang === "en";
  const og = isEn ? "https://findaro.iareal.net/og-en.png" : "https://findaro.iareal.net/og-es.png";
  const title = isEn ? "Buy FINDARO — Lifetime License" : "Comprar FINDARO — Licencia de por vida";
  const description = isEn
    ? "Lifetime Findaro for macOS, one payment: Solo $29 (1 Mac), Pro $39 (2 Macs), Family $59 (5 Macs)."
    : "Findaro de por vida para macOS, pago único: Solo $29 (1 Mac), Pro $39 (2 Macs), Family $59 (5 Macs).";
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
    <div className={`${sans.variable} ${mono.variable}`} data-light="">
      <Suspense fallback={<main className={styles.page} />}>
        <ComprarClient />
      </Suspense>
    </div>
  );
}
