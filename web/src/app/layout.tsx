import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FINDARO — Explorador de archivos con IA para Mac",
  description:
    "Doble panel, Smart Merge, bandeja tipo Windows, búsqueda y asistente local. Licencia de por vida desde $59 (primeros 1000).",
  applicationName: "FINDARO",
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

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
