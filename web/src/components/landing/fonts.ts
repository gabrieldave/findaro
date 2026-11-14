import { Martian_Mono, Schibsted_Grotesk } from "next/font/google";

/** Tipografías de la línea visual "Mesa de luz" (prohibido Inter/Roboto/Arial por WEB_FACTORY). */
export const sans = Schibsted_Grotesk({ subsets: ["latin"], variable: "--font-sans", display: "swap" });
export const mono = Martian_Mono({ subsets: ["latin"], variable: "--font-mono", display: "swap" });
