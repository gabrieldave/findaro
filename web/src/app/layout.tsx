import type { Metadata, Viewport } from "next";
import { cookies, headers } from "next/headers";
import { detectLanguageFromHeaders } from "@/lib/geo";
import "./globals.css";

export const metadata: Metadata = {
  title: "FINDARO — AI-Powered Dual-Pane File Manager for Mac",
  description:
    "Dual panes, Smart Merge, on-device AI assistant, familiar cut & paste, and deep recursive search. Built natively for Apple Silicon and macOS 15+.",
  applicationName: "FINDARO",
  alternates: {
    languages: {
      en: "https://findaro.iareal.net/?lang=en",
      es: "https://findaro.iareal.net/?lang=es",
      "x-default": "https://findaro.iareal.net/?lang=en",
    },
  },
  appleWebApp: {
    capable: true,
    title: "FINDARO",
    statusBarStyle: "black-translucent",
  },
  manifest: "/manifest.webmanifest",
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
