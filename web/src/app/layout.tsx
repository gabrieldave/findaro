import type { Metadata, Viewport } from "next";
import { cookies, headers } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { PUBLIC_APP_URL } from "@/lib/site";
import "./globals.css";

const base = PUBLIC_APP_URL.replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: new URL(base),
  title: {
    default: "FINDARO — Local AI Native File Manager for macOS",
    template: "%s · FINDARO",
  },
  description:
    "Local AI native file manager for macOS. Dual panes, Smart Merge, on-device semantic search. 14-day free trial — no credit card. Lifetime: Personal $29 · Pro $39 · Family $59.",
  applicationName: "FINDARO",
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  alternates: {
    languages: {
      en: `${base}/?lang=en`,
      es: `${base}/?lang=es`,
      "x-default": `${base}/?lang=en`,
    },
  },
  openGraph: {
    type: "website",
    siteName: "FINDARO",
    title: "FINDARO — Local AI Native File Manager for macOS",
    description:
      "On-device AI file manager for Mac. 14-day free trial, no credit card. Lifetime licenses from $29.",
    url: `${base}/?lang=en`,
    images: [{ url: "/og.png", width: 512, height: 512, alt: "FINDARO" }],
    locale: "en_US",
    alternateLocale: ["es_ES"],
  },
  twitter: {
    card: "summary_large_image",
    title: "FINDARO — Local AI Native File Manager for macOS",
    description:
      "On-device AI file manager for Mac. 14-day free trial, no credit card. Lifetime from $29.",
    images: ["/og.png"],
  },
  appleWebApp: {
    capable: true,
    title: "FINDARO",
    statusBarStyle: "black-translucent",
  },
  manifest: "/manifest.webmanifest",
  icons: {
    icon: [{ url: "/favicon.png", type: "image/png", sizes: "32x32" }],
    apple: [{ url: "/apple-touch-icon.png", sizes: "192x192" }],
  },
};

export const viewport: Viewport = {
  themeColor: "#0B1220",
  viewportFit: "cover",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const headerList = await headers();
  const cookieStore = await cookies();
  const lang = detectLanguageFromHeaders(headerList, cookieStore.get("findaro_lang")?.value, null);

  return (
    <html lang={lang}>
      <body>{children}</body>
    </html>
  );
}
