import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import Link from "next/link";
import { detectLanguageFromHeaders } from "@/lib/geo";
import styles from "../marketing.module.css";
import { langFromCookieStore } from "@/lib/lang";

type PageProps = {
  searchParams: Promise<{ lang?: string }>;
};

async function resolveLang(searchParams: Promise<{ lang?: string }>): Promise<"en" | "es"> {
  const sp = await searchParams;
  const headerList = await headers();
  const cookieStore = await cookies();
  return detectLanguageFromHeaders(headerList, langFromCookieStore(cookieStore), sp?.lang);
}

export async function generateMetadata({ searchParams }: PageProps): Promise<Metadata> {
  const lang = await resolveLang(searchParams);
  return lang === "en"
    ? {
        title: "Terms of Service — FINDARO",
        description: "Terms and conditions for your Findaro for macOS lifetime license.",
      }
    : {
        title: "Términos del Servicio — FINDARO",
        description: "Términos y condiciones de uso de la licencia de Findaro para macOS.",
      };
}

export default async function TerminosPage({ searchParams }: PageProps) {
  const lang = await resolveLang(searchParams);
  const isEn = lang === "en";
  const otherLang = isEn ? "es" : "en";

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <Link
            href={`/terminos?lang=${otherLang}`}
            style={{
              background: "rgba(56, 189, 248, 0.12)",
              border: "1px solid rgba(56, 189, 248, 0.3)",
              color: "#38bdf8",
              borderRadius: "6px",
              padding: "4px 10px",
              fontSize: "12px",
              fontWeight: 600,
              textDecoration: "none",
            }}
          >
            🌐 {isEn ? "Español" : "English"}
          </Link>
        </div>

        <h1 style={{ fontSize: "24px", margin: "8px 0 16px" }}>
          {isEn ? "Terms of Service" : "Términos del Servicio"}
        </h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          {isEn ? "Last updated: November 2026" : "Última actualización: Noviembre 2026"}
        </p>

        {isEn ? (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. License Grant</h2>
            <p>
              Upon purchasing Findaro, you are granted a perpetual, non-exclusive, non-transferable license to install and use the software on macOS computers:
            </p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Personal Plan ($29 USD launch):</strong> 1 Mac computer owned by you.</li>
              <li><strong>Pro Plan ($39 USD launch):</strong> up to 2 simultaneous Mac computers owned by you.</li>
              <li><strong>Family / Studio Plan ($59 USD launch):</strong> up to 5 simultaneous Mac computers owned by you or your household.</li>
            </ul>
            <p>
              You may free a seat anytime from <strong>Settings → License</strong> on your Mac, or by contacting support after a wipe/reformat or hardware change.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. No Subscriptions</h2>
            <p>
              Findaro is sold under a <strong>one-time lifetime payment</strong> model. There are no monthly fees, annual renewals, or hidden charges. Standard minor and major updates are included.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Payment Processing</h2>
            <p>
              Payments are processed securely through <strong>Stripe, Inc.</strong> We never store or have access to your full credit or debit card numbers.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Referral Program</h2>
            <p>
              Customers receive a unique referral link upon purchase. Every valid referred order grants the friend an instant discount at checkout. Self-referrals and abusive use are prohibited.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>5. Uninstall</h2>
            <p>
              To remove Findaro from a Mac, open the app and choose <strong>Findaro → Uninstall Findaro…</strong>.
              The uninstaller frees this Mac&apos;s license seat, removes local license/trial data from the Keychain,
              restores Finder if Findaro was set as the default file viewer, and moves the app to the Trash.
              Your personal files are never deleted. Your purchase key remains valid on another Mac.
              To free a seat without removing the app, use <strong>Settings → Deactivate this Mac</strong>.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>6. Contact</h2>
            <p>
              For legal inquiries, billing, or technical support, reach us at:{" "}
              <a href="mailto:support@findaro.iareal.net" style={{ color: "#38bdf8" }}>
                support@findaro.iareal.net
              </a>.
            </p>
          </div>
        ) : (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Concesión de Licencia</h2>
            <p>
              Al adquirir Findaro, se te concede una licencia perpetua, no exclusiva e intransferible para instalar y utilizar el software en sistemas macOS:
            </p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Plan Personal ($29 USD lanzamiento):</strong> 1 ordenador Mac de tu propiedad.</li>
              <li><strong>Plan Pro ($39 USD lanzamiento):</strong> hasta 2 ordenadores Mac simultáneos de tu propiedad.</li>
              <li><strong>Plan Familiar / Studio ($59 USD lanzamiento):</strong> hasta 5 ordenadores Mac simultáneos de tu propiedad o núcleo familiar.</li>
            </ul>
            <p>
              Puedes liberar un equipo desde <strong>Ajustes → Licencia</strong> en tu Mac, o solicitándolo a soporte en caso de formateo o cambio de equipo.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. Sin Suscripciones</h2>
            <p>
              Findaro se vende bajo el modelo de <strong>pago único de por vida</strong>. No existen cuotas mensuales, anuales ni cobros ocultos de ningún tipo. Las actualizaciones menores y mayores estándar están incluidas.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Procesamiento de Pagos</h2>
            <p>
              Los pagos se procesan de manera segura a través de <strong>Stripe, Inc.</strong> No almacenamos ni tenemos acceso a los números completos de tu tarjeta de crédito o débito.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Programa de Referidos</h2>
            <p>
              Los compradores reciben un enlace de recomendación único. Por cada venta válida referida, el comprador recomendado recibe un descuento directo aplicable al momento del checkout. El uso fraudulento o auto-referido se encuentra prohibido.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>5. Desinstalación</h2>
            <p>
              Para quitar Findaro de una Mac, abre la app y elige <strong>Findaro → Desinstalar Findaro…</strong>.
              El desinstalador libera el asiento de esta Mac, borra datos locales de licencia/prueba del Llavero,
              restaura Finder si Findaro era el explorador por defecto y mueve la app a la Papelera.
              Tus archivos personales no se borran. La clave de compra sigue válida en otra Mac.
              Si solo quieres liberar un asiento sin desinstalar: <strong>Ajustes → Desactivar esta Mac</strong>.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>6. Contacto</h2>
            <p>
              Para consultas legales, facturación o soporte técnico, contáctanos en:{" "}
              <a href="mailto:soporte@findaro.iareal.net" style={{ color: "#38bdf8" }}>
                soporte@findaro.iareal.net
              </a>.
            </p>
          </div>
        )}

        <div style={{ marginTop: "28px", paddingTop: "16px", borderTop: "1px solid #1e293b", textAlign: "center" }}>
          <Link href={`/comprar?lang=${lang}`} style={{ color: "#38bdf8", fontSize: "13px", textDecoration: "none" }}>
            {isEn ? "← Back to checkout" : "← Volver a la página de compra"}
          </Link>
        </div>
      </div>
    </main>
  );
}
