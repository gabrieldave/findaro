import type { Metadata } from "next";
import { CompareMatrix } from "@/components/landing/LandingPage";
import SimpleShell from "@/components/landing/SimpleShell";
import s from "@/components/landing/landing.module.css";
import { COPY, buyHref, trialHref } from "@/config/funnel";
import { resolvePageLang } from "@/lib/page-lang";

type Props = { searchParams: Promise<{ lang?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const lang = await resolvePageLang(searchParams);
  const title = lang === "es" ? "Findaro frente a otros gestores de archivos para Mac" : "Findaro compared with other Mac file managers";
  const description =
    lang === "es"
      ? "Matriz técnica de 52 funciones: Findaro, Finder, ForkLift 4, Bloom, QSpace Pro y Path Finder."
      : "52-feature technical matrix: Findaro, Finder, ForkLift 4, Bloom, QSpace Pro and Path Finder.";
  return { title: { absolute: title }, description, alternates: { canonical: `/comparar?lang=${lang}` } };
}

export default async function CompararPage({ searchParams }: Props) {
  const lang = await resolvePageLang(searchParams);
  const t = COPY[lang];
  return (
    <SimpleShell lang={lang}>
      <div className={s.head}>
        <h1 className={s.h2}>{lang === "es" ? "Findaro frente a los demás, función por función." : "Findaro against the rest, feature by feature."}</h1>
        <p className={s.sub}>
          {lang === "es"
            ? "Matriz documental de 52 funciones. Incluye también lo que otros hacen y Findaro todavía no (conexiones remotas, sincronización, terminal integrado)."
            : "A 52-feature documentation matrix. It also lists what others do and Findaro doesn't yet (remote connections, sync, embedded terminal)."}
        </p>
      </div>
      <div className={s.pageCard}>
        <CompareMatrix lang={lang} />
        <p className={s.footnote}>{t.compare.footnote}</p>
      </div>
      <div className={s.ctas}>
        <a className={s.btn} href={trialHref(lang)}>
          {t.hero.primary}
        </a>
        <a className={s.btnGhost} href={buyHref("personal", lang)}>
          {t.final.secondary}
        </a>
      </div>
    </SimpleShell>
  );
}
