import type { Metadata } from "next";
import Link from "next/link";
import SimpleShell from "@/components/landing/SimpleShell";
import s from "@/components/landing/landing.module.css";
import { COPY, funnel, whatsappHref } from "@/config/funnel";
import { resolvePageLang } from "@/lib/page-lang";

type Props = { searchParams: Promise<{ lang?: string }> };

export async function generateMetadata({ searchParams }: Props): Promise<Metadata> {
  const lang = await resolvePageLang(searchParams);
  return {
    title: { absolute: lang === "es" ? "Soporte de Findaro" : "Findaro support" },
    description:
      lang === "es"
        ? "Dudas rápidas por WhatsApp, soporte por correo, activación de licencia y reembolsos de Findaro."
        : "Quick questions on WhatsApp, email support, license activation and refunds for Findaro.",
    alternates: { canonical: `/soporte?lang=${lang}` },
  };
}

export default async function SoportePage({ searchParams }: Props) {
  const lang = await resolvePageLang(searchParams);
  const t = COPY[lang];
  const es = lang === "es";
  const email = funnel.supportEmail[lang];
  return (
    <SimpleShell lang={lang}>
      <div className={s.head}>
        <h1 className={s.h2}>{es ? "¿En qué te ayudamos?" : "How can we help?"}</h1>
        <p className={s.sub}>
          {es
            ? "Somos un estudio pequeño: responde la misma persona que escribe la app."
            : "We're a small studio: the person who answers is the person who writes the app."}
        </p>
      </div>
      <div className={s.toolsGrid}>
        <div className={s.pageCard}>
          <h2 style={{ marginTop: 0 }}>{es ? "Dudas rápidas: WhatsApp" : "Quick questions: WhatsApp"}</h2>
          <p>
            {es
              ? "Solo para dudas rápidas antes de comprar o al activar tu licencia. Para problemas técnicos largos, mejor por correo."
              : "Only for quick questions before buying or while activating your license. For longer technical issues, email works better."}
          </p>
          <p style={{ marginTop: 16 }}>
            <a className={s.btn} href={whatsappHref(t.whatsapp.message)} target="_blank" rel="noopener noreferrer">
              {t.whatsapp.open}
            </a>
          </p>
          <h2>{es ? "Soporte por correo" : "Email support"}</h2>
          <p>
            <a href={`mailto:${email}`}>{email}</a>
          </p>
          <h2>{es ? "Activar tu licencia" : "Activating your license"}</h2>
          <p>
            {es
              ? "En Findaro: Ajustes → Licencia → pega la clave que llegó a tu correo. Para pasar la licencia a otro Mac, libera el puesto desde esa misma hoja."
              : "In Findaro: Settings → License → paste the key from your email. To move the license to another Mac, free the seat from the same sheet."}
          </p>
          <h2>{es ? "Reembolsos" : "Refunds"}</h2>
          <p>
            {es ? "Garantía de 14 días sin preguntas. " : "14-day guarantee, no questions asked. "}
            <Link href={`/reembolso?lang=${lang}`}>{t.footer.links.refund}</Link>
          </p>
        </div>
        <div className={s.pageCard}>
          <h2 style={{ marginTop: 0 }}>{es ? "Datos del instalador" : "Installer details"}</h2>
          <p className={s.mono} style={{ fontSize: 13 }}>
            {t.footer.version} {funnel.version}
            <br />
            {t.footer.team}: {funnel.teamId}
            <br />
            macOS {funnel.minMacOS}+ · Apple Silicon
            {funnel.sha256 ? (
              <>
                <br />
                {t.footer.sha}: {funnel.sha256}
              </>
            ) : null}
          </p>
          <h2>{t.faq.title}</h2>
          {t.faq.items.slice(0, 4).map((item) => (
            <details key={item.q} className={s.qa} style={{ marginTop: 8 }}>
              <summary>{item.q}</summary>
              <p>{item.a}</p>
            </details>
          ))}
        </div>
      </div>
    </SimpleShell>
  );
}
