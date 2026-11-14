import type { Metadata } from "next";
import { Suspense } from "react";
import { mono, sans } from "@/components/landing/fonts";
import styles from "../light.module.css";
import ProbarClient from "./ProbarClient";

type Props = { searchParams: Promise<{ lang?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const sp = await searchParams;
  const lang = sp.lang === "es" ? "es" : "en";
  const isEn = lang === "en";
  const og = isEn ? "https://findaro.iareal.net/og-en.png" : "https://findaro.iareal.net/og-es.png";
  const title = isEn ? "Try FINDARO Free — 14 Days" : "Probar FINDARO gratis — 14 días";
  const description = isEn
    ? "Download FINDARO for macOS free for 14 days. No credit card required."
    : "Descarga FINDARO para macOS gratis 14 días. Sin tarjeta de crédito.";
  return {
    title,
    description,
    openGraph: {
      title,
      description,
      url: `https://findaro.iareal.net/probar?lang=${lang}`,
      images: [{ url: og, width: 1200, height: 630, alt: "FINDARO" }],
      locale: isEn ? "en_US" : "es_MX",
      type: "website",
    },
    twitter: { card: "summary_large_image", title, description, images: [og] },
  };
}

export default function ProbarPage() {
  return (
    <div className={`${sans.variable} ${mono.variable}`} data-light="">
      <Suspense fallback={<main className={styles.page} />}>
        <ProbarClient />
      </Suspense>
    </div>
  );
}
