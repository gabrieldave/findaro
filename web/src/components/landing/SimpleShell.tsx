import Link from "next/link";
import type { ReactNode } from "react";
import { COPY, trialHref } from "@/config/funnel";
import type { Lang } from "@/lib/lang";
import LangSwitch from "./LangSwitch";
import WhatsAppSupportBubble from "./WhatsAppSupportBubble";
import { mono, sans } from "./fonts";
import s from "./landing.module.css";

/** Marco común para páginas secundarias (/comparar, /soporte) con la línea visual "Mesa de luz". */
export default function SimpleShell({ lang, children }: { lang: Lang; children: ReactNode }) {
  const t = COPY[lang];
  return (
    <div className={`${s.root} ${sans.variable} ${mono.variable}`} data-landing="">
      <header className={s.nav}>
        <div className={`${s.wrap} ${s.navIn}`}>
          <Link className={s.brand} href={lang === "es" ? "/es" : "/"}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.png" alt="" width={28} height={28} />
            Findaro
          </Link>
          <div className={s.navRight}>
            <LangSwitch lang={lang} label={t.nav.langLabel} target="self" />
            <a className={`${s.btn} ${s.btnSm} ${s.navCta}`} href={trialHref(lang)}>
              {t.nav.download}
            </a>
          </div>
        </div>
      </header>
      <main className={`${s.main} ${s.page}`}>
        <div className={s.wrap}>{children}</div>
      </main>
      <footer className={s.footer}>
        <div className={`${s.wrap} ${s.footLinks}`}>
          <Link href={lang === "es" ? "/es" : "/"}>Findaro</Link>
          <Link href={`/comparar?lang=${lang}`}>{t.footer.links.compare}</Link>
          <Link href={`/soporte?lang=${lang}`}>{t.footer.links.support}</Link>
          <Link href={`/privacidad?lang=${lang}`}>{t.footer.links.privacy}</Link>
          <Link href={`/terminos?lang=${lang}`}>{t.footer.links.terms}</Link>
          <Link href={`/reembolso?lang=${lang}`}>{t.footer.links.refund}</Link>
        </div>
      </footer>
      <WhatsAppSupportBubble lang={lang} />
    </div>
  );
}
