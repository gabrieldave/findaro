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
        title: "Refund Policy — FINDARO",
        description: "14-day no-questions-asked satisfaction guarantee and refund policy for Findaro.",
      }
    : {
        title: "Política de Reembolso — FINDARO",
        description: "Garantía de satisfacción de 14 días y política de reembolsos de Findaro para macOS.",
      };
}

export default async function ReembolsoPage({ searchParams }: PageProps) {
  const lang = await resolveLang(searchParams);
  const isEn = lang === "en";
  const otherLang = isEn ? "es" : "en";

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <Link
            href={`/reembolso?lang=${otherLang}`}
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
          {isEn ? "14-Day Money-Back Guarantee & Refund Policy" : "Garantía y Política de Reembolso"}
        </h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          {isEn ? "Last updated: November 2026" : "Última actualización: Noviembre 2026"}
        </p>

        {isEn ? (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <div
              style={{
                background: "rgba(34, 197, 94, 0.1)",
                border: "1px solid rgba(34, 197, 94, 0.3)",
                color: "#4ade80",
                padding: "14px 18px",
                borderRadius: "10px",
                marginBottom: "20px",
                fontWeight: 600,
              }}
            >
              🛡️ 100% risk-free 14-day satisfaction guarantee.
            </div>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Refund Window (14 Calendar Days)</h2>
            <p>
              We want you to buy with total confidence. If Findaro doesn&apos;t meet your expectations, runs into any technical issue on your Mac, or simply isn&apos;t the right fit for your workflow, you may request a full refund within <strong>14 calendar days</strong> of your purchase date.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. How to Request a Refund</h2>
            <p>
              No awkward questions or hoops to jump through. Simply email us at:
            </p>
            <p style={{ margin: "10px 0" }}>
              📧{" "}
              <a href="mailto:support@findaro.iareal.net" style={{ color: "#38bdf8", fontWeight: "bold" }}>
                support@findaro.iareal.net
              </a>
            </p>
            <p>Include:</p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li>The email address used during checkout.</li>
              <li>Your license key or Stripe transaction receipt ID.</li>
            </ul>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Processing Time</h2>
            <p>
              We issue the refund immediately through Stripe back to your original payment method. Depending on your bank or card issuer, funds typically appear on your statement within <strong>3 to 5 business days</strong>.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Effect on Your License</h2>
            <p>
              Once a full refund is processed, the associated license key is automatically deactivated in our licensing server and the app returns to read-only mode.
            </p>
          </div>
        ) : (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <div
              style={{
                background: "rgba(34, 197, 94, 0.1)",
                border: "1px solid rgba(34, 197, 94, 0.3)",
                color: "#4ade80",
                padding: "14px 18px",
                borderRadius: "10px",
                marginBottom: "20px",
                fontWeight: 600,
              }}
            >
              🛡️ Garantía de Satisfacción 100% libre de riesgo durante 14 días.
            </div>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Plazo de Reembolso (14 Días)</h2>
            <p>
              Queremos que compres con total tranquilidad. Si Findaro no cumple tus expectativas, presenta algún conflicto técnico en tu Mac o simplemente decides que no es para ti, puedes solicitar un reembolso completo dentro de los <strong>14 días naturales</strong> posteriores a la fecha de tu compra.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. Cómo solicitar el reembolso</h2>
            <p>
              No te haremos preguntas incómodas ni pondremos trabas. Solo envíanos un correo a:
            </p>
            <p style={{ margin: "10px 0" }}>
              📧{" "}
              <a href="mailto:soporte@findaro.iareal.net" style={{ color: "#38bdf8", fontWeight: "bold" }}>
                soporte@findaro.iareal.net
              </a>
            </p>
            <p>Incluye:</p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li>El correo electrónico con el que realizaste la compra.</li>
              <li>Tu clave de licencia o el ID de transacción de Stripe.</li>
            </ul>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Plazo de Acreditación</h2>
            <p>
              Procesamos la devolución inmediatamente en nuestro panel de Stripe. El dinero es devuelto a la misma tarjeta de crédito o débito utilizada. Dependiendo de tu entidad bancaria, el saldo se refleja habitualmente entre <strong>3 y 5 días hábiles</strong>.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Efecto del Reembolso en la Licencia</h2>
            <p>
              Una vez procesado el reembolso, la clave de licencia asociada queda revocada en nuestro sistema de licencias y el software pasará a estado inactivo.
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
