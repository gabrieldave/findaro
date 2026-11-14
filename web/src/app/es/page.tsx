import type { Metadata, Viewport } from "next";
import LandingPage, { landingMetadata } from "@/components/landing/LandingPage";

export const metadata: Metadata = landingMetadata("es");
export const viewport: Viewport = { themeColor: "#F7F8FA", viewportFit: "cover" };

export default function HomeEs() {
  return <LandingPage lang="es" />;
}
