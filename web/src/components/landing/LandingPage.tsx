import type { Metadata } from "next";
import Link from "next/link";
import type { CSSProperties } from "react";
import { COPY, buyHref, funnel, trialHref } from "@/config/funnel";
import { MATRIX, MATRIX_APPS, type MatrixValue } from "@/content/compare-matrix";
import type { Lang } from "@/lib/lang";
import HeroMerge from "./HeroMerge";
import KineticTitle from "./KineticTitle";
import LangSwitch from "./LangSwitch";
import LiteYouTubeFacade from "./LiteYouTubeFacade";
import MiniTools from "./MiniTools";
import RenameDemo from "./RenameDemo";
import Reveal from "./Reveal";
import StickyStory from "./StickyStory";
import WhatsAppSupportBubble from "./WhatsAppSupportBubble";
import { mono, sans } from "./fonts";
import s from "./landing.module.css";

const ROOT_ID = "findaro-landing";

/** Activa el estado inicial del revelado antes del primer pintado; si React no monta en 3,5 s, lo deshace. */
const REVEAL_BOOT = `(function(){try{var r=document.currentScript&&document.currentScript.parentElement;if(!r||window.matchMedia('(prefers-reduced-motion: reduce)').matches)return;r.setAttribute('data-rv-ready','');setTimeout(function(){if(!window.__fxReveal)r.removeAttribute('data-rv-ready')},3500)}catch(e){}})();`;

const i = (n: number) => ({ "--i": n }) as CSSProperties;

export function landingMetadata(lang: Lang): Metadata {
  const t = COPY[lang].meta;
  const base = funnel.siteUrl;
  const url = lang === "es" ? `${base}/es` : `${base}/`;
  return {
    title: { absolute: t.title },
    description: t.description,
    alternates: {
      canonical: url,
      languages: { en: `${base}/`, es: `${base}/es`, "x-default": `${base}/` },
    },
    openGraph: {
      type: "website",
      siteName: "Findaro",
      title: t.title,
      description: t.description,
      url,
      locale: t.ogLocale,
      alternateLocale: [lang === "es" ? "en_US" : "es_MX"],
      images: [{ url: t.ogImage, width: 1200, height: 630, alt: "Findaro" }],
    },
    twitter: { card: "summary_large_image", title: t.title, description: t.description, images: [t.ogImage] },
  };
}

function jsonLd(lang: Lang) {
  const t = COPY[lang];
  return {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Findaro",
    operatingSystem: `macOS ${funnel.minMacOS}+`,
    applicationCategory: "UtilitiesApplication",
    softwareVersion: funnel.version,
    description: t.meta.description,
    url: lang === "es" ? `${funnel.siteUrl}/es` : `${funnel.siteUrl}/`,
    inLanguage: lang,
    offers: funnel.pricing.tiers.map((tier) => ({
      "@type": "Offer",
      name: `Findaro ${t.pricing.names[tier.key]}`,
      price: tier.price.toFixed(2),
      priceCurrency: funnel.pricing.currency,
      url: `${funnel.siteUrl}${buyHref(tier.checkoutTier, lang)}`,
      availability: "https://schema.org/InStock",
    })),
  };
}

function Check({ color = "#0e9f6e" }: { color?: string }) {
  return (
    <svg width="15" height="15" viewBox="0 0 16 16" aria-hidden="true">
      <circle cx="8" cy="8" r="7.25" fill="none" stroke={color} strokeWidth="1.5" opacity=".35" />
      <path d="M4.8 8.3l2.2 2.2 4.3-4.6" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CtaCheck() {
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
      <path d="M3 8.4l3.1 3.1L13 4.6" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

const glyph: Record<MatrixValue, { g: string; cls: string }> = {
  y: { g: "✓", cls: s.vy },
  s: { g: "~", cls: s.vs },
  n: { g: "—", cls: s.vn },
};

export function CompareMatrix({ lang }: { lang: Lang }) {
  const t = COPY[lang].compare;
  let lastGroup = "";
  return (
    <>
      <p className={s.legend}>{t.legend}</p>
      <div className={s.mxScroll}>
        <table className={s.mx}>
          <thead>
            <tr>
              <th scope="col">{t.feature}</th>
              {MATRIX_APPS.map((a) => (
                <th key={a.key} scope="col" className={a.key === "findaro" ? s.colMe : undefined}>
                  {a.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {MATRIX.flatMap((row) => {
              const group = lang === "es" ? row.groupEs : row.groupEn;
              const out = [];
              if (group !== lastGroup) {
                lastGroup = group;
                out.push(
                  <tr key={`g-${row.id}`} className={s.mxGroup}>
                    <td colSpan={MATRIX_APPS.length + 1}>{group}</td>
                  </tr>,
                );
              }
              out.push(
                <tr key={row.id}>
                  <th scope="row" style={{ fontWeight: 500 }}>
                    {lang === "es" ? row.es : row.en}
                  </th>
                  {MATRIX_APPS.map((a) => {
                    const v = glyph[row.v[a.key]];
                    return (
                      <td key={a.key} className={`${v.cls} ${a.key === "findaro" ? s.colMe : ""}`}>
                        {v.g}
                      </td>
                    );
                  })}
                </tr>,
              );
              return out;
            })}
          </tbody>
        </table>
      </div>
    </>
  );
}

export default function LandingPage({ lang }: { lang: Lang }) {
  const t = COPY[lang];
  const sv = funnel.savings;
  const suiteYear = sv.suiteMonthly * 12;
  const range = `~$${sv.pathFinderYearMin}–${sv.pathFinderYearMax}`;
  const rangeTotal = `~$${sv.pathFinderYearMin * 3}–${sv.pathFinderYearMax * 3}`;

  return (
    <div id={ROOT_ID} className={`${s.root} ${sans.variable} ${mono.variable}`} data-landing="" suppressHydrationWarning>
      <script dangerouslySetInnerHTML={{ __html: REVEAL_BOOT }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd(lang)) }} />
      <a className={s.skip} href="#content">
        {t.skip}
      </a>
      <div className={s.grain} aria-hidden="true" />

      <header className={s.nav}>
        <div className={`${s.wrap} ${s.navIn}`}>
          <Link className={s.brand} href={lang === "es" ? "/es" : "/"} aria-label="Findaro">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.png" alt="" width={28} height={28} />
            Findaro
          </Link>
          <nav className={s.navLinks} aria-label="Findaro">
            <a href="#features">{t.nav.features}</a>
            <a href="#tools">{t.nav.tools}</a>
            <a href="#compare">{t.nav.compare}</a>
            <a href="#pricing">{t.nav.pricing}</a>
            <a href="#faq">{t.nav.faq}</a>
          </nav>
          <div className={s.navRight}>
            <LangSwitch lang={lang} label={t.nav.langLabel} />
            <a className={`${s.btn} ${s.btnSm} ${s.navCta}`} href={trialHref(lang)}>
              {t.nav.download}
            </a>
          </div>
        </div>
      </header>

      <main id="content" className={s.main}>
        {/* ------------------------------- Hero ------------------------------- */}
        <section className={s.hero} aria-labelledby="hero-title">
          <div className={`${s.wrap} ${s.heroGrid}`}>
            <div>
              <span className={`${s.eyebrow} ${s.enter}`} style={i(0)}>
                <span className={s.dot} aria-hidden="true" />
                <span className={s.tnum}>{t.hero.eyebrow}</span>
              </span>
              <KineticTitle id="hero-title" text={t.hero.title} className={`${s.title} ${s.enterWords}`} mode="enter" />
              <p className={`${s.lead} ${s.enter}`} style={i(4)}>
                {t.hero.sub}
              </p>
              <div className={`${s.ctas} ${s.enter}`} style={i(5)}>
                <a className={s.btn} href={trialHref(lang)}>
                  <CtaCheck />
                  {t.hero.primary}
                </a>
                <a className={s.btnGhost} href="#pricing">
                  {t.hero.secondary}
                </a>
              </div>
              <ul className={`${s.trust} ${s.enter}`} style={i(6)}>
                {t.hero.trust.map((item) => (
                  <li key={item}>
                    <Check />
                    {item}
                  </li>
                ))}
              </ul>
            </div>
            <div className={s.enter} style={i(3)}>
              <HeroMerge lang={lang} />
              <p className={s.demoNote}>{t.hero.demoNote}</p>
            </div>
          </div>
        </section>

        {/* ------------------------------- Facts ------------------------------ */}
        <section className={s.facts} aria-label="Findaro">
          <div className={`${s.wrap} ${s.factGrid}`}>
            {t.facts.map((f, n) => (
              <div key={f.v} className={s.fact} data-rv="" style={i(n)}>
                <b>{f.k}</b>
                <span>{f.v}</span>
              </div>
            ))}
          </div>
        </section>

        {/* ------------------------------- Story ------------------------------ */}
        <section id="features" className={s.section} aria-labelledby="story-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="story-title" text={t.story.title} className={`${s.h2} ${s.title2}`} />
              <p className={s.sub} data-rv="" style={i(2)}>
                {t.story.sub}
              </p>
            </div>
            <StickyStory lang={lang} />
          </div>
        </section>

        {/* ----------------------------- Pro tools ---------------------------- */}
        <section id="tools" className={s.section} aria-labelledby="tools-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="tools-title" text={t.tools.title} className={`${s.h2} ${s.title2}`} />
              <p className={s.sub} data-rv="" style={i(2)}>
                {t.tools.sub}
              </p>
            </div>
            <div className={s.toolsGrid}>
              <RenameDemo lang={lang} />
              <MiniTools lang={lang} />
            </div>
          </div>
        </section>

        {/* ------------------------------- Tour ------------------------------- */}
        <section id="tour" className={s.section} aria-labelledby="tour-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="tour-title" text={t.tour.title} className={`${s.h2} ${s.title2}`} />
            </div>
            <div data-rv="lift">
              <LiteYouTubeFacade lang={lang} videoId={funnel.youtubeTutorialId} />
            </div>
          </div>
        </section>

        {/* ------------------------------ Compare ----------------------------- */}
        <section id="compare" className={s.section} aria-labelledby="compare-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="compare-title" text={t.compare.title} className={`${s.h2} ${s.title2}`} />
              <p className={s.sub} data-rv="" style={i(2)}>
                {t.compare.sub}
              </p>
            </div>
            <div className={s.tableCard} data-rv="lift">
              <div className={s.tableScroll}>
                <table className={s.cmp}>
                  <thead>
                    <tr>
                      <th scope="col">{t.compare.cols.app}</th>
                      <th scope="col" className={s.num}>
                        {t.compare.cols.y1}
                      </th>
                      <th scope="col" className={s.num}>
                        {t.compare.cols.y2}
                      </th>
                      <th scope="col" className={s.num}>
                        {t.compare.cols.y3}
                      </th>
                      <th scope="col" className={s.num}>
                        {t.compare.cols.total}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr className={s.cmpMe}>
                      <th scope="row">
                        <span className={s.cmpName}>{t.compare.rows.findaro.name}</span>
                        <span className={s.cmpNote}>{t.compare.rows.findaro.note}</span>
                      </th>
                      <td className={s.num}>${sv.findaroPro}</td>
                      <td className={s.num}>$0</td>
                      <td className={s.num}>$0</td>
                      <td className={`${s.num} ${s.cmpTotal}`}>
                        $<span data-count={sv.findaroPro}>{sv.findaroPro}</span>
                      </td>
                    </tr>
                    <tr>
                      <th scope="row">
                        <span className={s.cmpName}>{t.compare.rows.pathfinder.name}</span>
                        <span className={s.cmpNote}>{t.compare.rows.pathfinder.note}</span>
                      </th>
                      <td className={s.num}>{range}</td>
                      <td className={s.num}>{range}</td>
                      <td className={s.num}>{range}</td>
                      <td className={`${s.num} ${s.cmpTotal}`}>{rangeTotal}</td>
                    </tr>
                    <tr>
                      <th scope="row">
                        <span className={s.cmpName}>{t.compare.rows.suite.name}</span>
                        <span className={s.cmpNote}>
                          ${sv.suiteMonthly.toFixed(2)}
                          {t.compare.perMonth} · {t.compare.rows.suite.note}
                        </span>
                      </th>
                      <td className={s.num}>${suiteYear.toFixed(2)}</td>
                      <td className={s.num}>${suiteYear.toFixed(2)}</td>
                      <td className={s.num}>${suiteYear.toFixed(2)}</td>
                      <td className={`${s.num} ${s.cmpTotal}`}>
                        $<span data-count={(suiteYear * 3).toFixed(2)} data-decimals="2">{(suiteYear * 3).toFixed(2)}</span>
                      </td>
                    </tr>
                    <tr>
                      <th scope="row">
                        <span className={s.cmpName}>{t.compare.rows.finder.name}</span>
                        <span className={s.cmpNote}>{t.compare.rows.finder.note}</span>
                      </th>
                      <td className={s.num}>$0</td>
                      <td className={s.num}>$0</td>
                      <td className={s.num}>$0</td>
                      <td className={`${s.num} ${s.cmpTotal}`}>$0</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
            <p className={s.footnote}>{t.compare.footnote}</p>
            <details className={s.matrix} data-rv="">
              <summary>{t.compare.matrixToggle}</summary>
              <div className={s.matrixBody}>
                <CompareMatrix lang={lang} />
                <p className={s.footnote}>
                  <Link href={`/comparar?lang=${lang}`}>{t.compare.fullPage}</Link>
                </p>
              </div>
            </details>
          </div>
        </section>

        {/* ------------------------------ Pricing ----------------------------- */}
        <section id="pricing" className={s.section} aria-labelledby="pricing-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="pricing-title" text={t.pricing.title} className={`${s.h2} ${s.title2}`} />
              <p className={s.sub} data-rv="" style={i(2)}>
                {t.pricing.sub}
              </p>
            </div>
            <div className={s.plans}>
              {funnel.pricing.tiers.map((tier, n) => {
                const per = tier.seats > 1 ? `$${(tier.price / tier.seats).toFixed(2)}` : "";
                return (
                  <div key={tier.key} className={`${s.plan} ${tier.recommended ? s.planAnchor : ""}`} data-rv="" style={i(n)}>
                    {tier.recommended ? <span className={s.planTag}>{t.pricing.recommended}</span> : null}
                    {tier.compareAt ? <span className={s.planLaunch}>{t.pricing.launch}</span> : null}
                    <span className={s.planName}>{t.pricing.names[tier.key]}</span>
                    <div className={s.planAmt}>
                      <span className={s.planPrice}>
                        $<span data-count={tier.price}>{tier.price}</span>
                      </span>
                      <span className={s.planOnce}>{t.pricing.once}</span>
                      {tier.compareAt ? <span className={`${s.planWas} ${s.tnum}`}>{t.pricing.was(tier.compareAt)}</span> : null}
                    </div>
                    <span className={s.planSeats}>{t.pricing.seats[tier.key]}</span>
                    {per ? <span className={`${s.planPer} ${s.tnum}`}>{t.pricing.perMac(per)}</span> : null}
                    <ul className={s.planList}>
                      {t.pricing.includes.map((line) => (
                        <li key={line}>
                          <Check />
                          {line}
                        </li>
                      ))}
                      {tier.key === "family" ? (
                        <li>
                          <Check />
                          {t.pricing.familyExtra}
                        </li>
                      ) : null}
                    </ul>
                    <div className={s.planGo}>
                      <a className={tier.recommended ? s.btn : s.btnLine} href={buyHref(tier.checkoutTier, lang)}>
                        {t.pricing.cta[tier.key]}
                      </a>
                    </div>
                  </div>
                );
              })}
            </div>
            <div className={s.guarantee} data-rv="">
              <span>
                <Check /> {t.pricing.sub}
              </span>
              <a className={s.btnGhost} href={trialHref(lang)} style={{ minHeight: 0 }}>
                {t.pricing.trialCta}
              </a>
            </div>
          </div>
        </section>

        {/* -------------------------------- FAQ -------------------------------- */}
        <section id="faq" className={s.section} aria-labelledby="faq-title">
          <div className={s.wrap}>
            <div className={s.head}>
              <KineticTitle as="h2" id="faq-title" text={t.faq.title} className={`${s.h2} ${s.title2}`} />
            </div>
            <div className={s.faq}>
              {t.faq.items.map((item, n) => (
                <details key={item.q} className={s.qa} data-rv="" style={i(n)}>
                  <summary>{item.q}</summary>
                  <p>{item.a}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

        {/* ------------------------------- Final ------------------------------- */}
        <div className={s.wrap}>
          <section className={s.final} aria-labelledby="final-title" data-rv="lift">
            <h2 className={s.h2} id="final-title">
              {t.final.title}
            </h2>
            <p className={s.sub}>{t.final.sub}</p>
            <div className={s.ctas}>
              <a className={`${s.btn} ${s.btnLight}`} href={trialHref(lang)}>
                {t.final.primary}
              </a>
              <a className={s.btnGhost} href={buyHref("personal", lang)}>
                {t.final.secondary}
              </a>
            </div>
          </section>
        </div>
      </main>

      <footer className={s.footer}>
        <div className={`${s.wrap} ${s.footGrid}`}>
          <div>
            <Link className={s.brand} href={lang === "es" ? "/es" : "/"}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/logo-mark.png" alt="" width={28} height={28} />
              Findaro
            </Link>
            <p style={{ margin: "10px 0 0", maxWidth: "40ch" }}>{t.footer.tagline}</p>
          </div>
          <nav className={s.footLinks} aria-label="Legal">
            <Link href={`/comparar?lang=${lang}`}>{t.footer.links.compare}</Link>
            <Link href={`/soporte?lang=${lang}`}>{t.footer.links.support}</Link>
            <Link href={`/privacidad?lang=${lang}`}>{t.footer.links.privacy}</Link>
            <Link href={`/terminos?lang=${lang}`}>{t.footer.links.terms}</Link>
            <Link href={`/reembolso?lang=${lang}`}>{t.footer.links.refund}</Link>
          </nav>
          <div className={s.footMeta}>
            <span>
              {t.footer.version} {funnel.version}
            </span>
            <span>
              {t.footer.team}: {funnel.teamId}
            </span>
            {funnel.sha256 ? (
              <span>
                {t.footer.sha}: {funnel.sha256}
              </span>
            ) : null}
            <span>
              © {new Date().getFullYear()} {t.footer.rights}
            </span>
          </div>
        </div>
      </footer>

      <WhatsAppSupportBubble lang={lang} />
      <Reveal rootId={ROOT_ID} />
    </div>
  );
}
