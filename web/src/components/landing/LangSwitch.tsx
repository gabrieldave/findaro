"use client";

import { landingPath, writeClientLang, type Lang } from "@/lib/lang";
import s from "./landing.module.css";

/** Selector EN | ES. Guarda la cookie `findaro-lang` y navega (recarga completa para actualizar <html lang>). */
export default function LangSwitch({ lang, label, target }: { lang: Lang; label: string; target?: "landing" | "self" }) {
  const go = (next: Lang) => {
    if (next === lang) return;
    writeClientLang(next);
    if (target === "self") {
      const url = new URL(window.location.href);
      url.searchParams.set("lang", next);
      window.location.assign(url.toString());
      return;
    }
    window.location.assign(landingPath(next) + window.location.hash);
  };
  return (
    <div className={s.lang} role="group" aria-label={label}>
      {(["en", "es"] as const).map((l) => (
        <button key={l} type="button" aria-pressed={l === lang} onClick={() => go(l)} lang={l}>
          {l.toUpperCase()}
        </button>
      ))}
    </div>
  );
}
