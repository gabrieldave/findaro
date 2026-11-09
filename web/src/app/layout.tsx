import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "FINDARO — AI-Powered Dual-Pane File Manager for Mac",
  description:
    "Dual panes, Smart Merge, on-device AI assistant, familiar cut & paste, and deep recursive search. Built natively for Apple Silicon and macOS 15+.",
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
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
