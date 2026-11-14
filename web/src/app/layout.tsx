import type { Metadata, Viewport } from "next";
import { cookies, headers } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { LANG_HEADER, langFromCookieStore, parseLang } from "@/lib/lang";
import { PUBLIC_APP_URL } from "@/lib/site";
import "./globals.css";

const base = PUBLIC_APP_URL.replace(/\/$/, "");

export const metadata: Metadata = {
  metadataBase: new URL(base),
  title: {
    default: "Findaro — Native file manager for macOS",
    template: "%s · Findaro",
  },
  description:
    "Native file manager for macOS: two panes, real ⌘X, Smart Merge with SHA-256 checks, 2-phase batch rename, local voice and AI. 14-day free trial, no card. One payment: Solo $29 · Pro $39 · Family $59.",
  applicationName: "FINDARO",
  robots: {
    index: true,
    follow: true,
    googleBot: { index: true, follow: true, "max-image-preview": "large" },
  },
  openGraph: {
    type: "website",
    siteName: "FINDARO",
    title: "FINDARO — Local AI Native File Manager for macOS",
    description:
      "On-device AI file manager for Mac. 14-day free trial, no credit card. Lifetime licenses from $29.",
    url: `${base}/`,
    images: [{ url: "/og.png", width: 1200, height: 630, alt: "FINDARO" }],
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
  // El middleware fija x-findaro-lang (es en /es, en en /, cookie/país en el resto).
  const lang =
    parseLang(headerList.get(LANG_HEADER)) ??
    detectLanguageFromHeaders(headerList, langFromCookieStore(cookieStore), null);

  return (
    <html lang={lang} suppressHydrationWarning>
      <body>{children}</body>
    </html>
  );
}
