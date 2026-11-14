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
        title: "Privacy Policy — FINDARO",
        description: "Privacy and local-first data protection policy for Findaro on macOS.",
      }
    : {
        title: "Política de Privacidad — FINDARO",
        description: "Política de privacidad y protección de datos de Findaro para macOS.",
      };
}

export default async function PrivacidadPage({ searchParams }: PageProps) {
  const lang = await resolveLang(searchParams);
  const isEn = lang === "en";
  const otherLang = isEn ? "es" : "en";

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <Link
            href={`/privacidad?lang=${otherLang}`}
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
          {isEn ? "Privacy Policy" : "Política de Privacidad"}
        </h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          {isEn ? "Last updated: November 2026" : "Última actualización: Noviembre 2026"}
        </p>

        {isEn ? (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Local-First Philosophy (Your Files Never Leave Your Mac)</h2>
            <p>
              Findaro is a native macOS application built on a <strong>100% local-first</strong> architecture. We do not collect, index, or transmit the contents of your files, folders, images, or documents to any cloud or external server.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. On-Device AI Assistant</h2>
            <p>
              Findaro&apos;s assistant runs via local models hosted on your own Mac (through Ollama) or deterministic built-in rules. Neither your prompts nor your filenames are sent to third-party servers for training or analysis.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Data Collected Upon Purchase or Trial</h2>
            <p>
              When you request a trial or purchase a license on our website, we collect only the minimum data necessary to deliver the service:
            </p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Name and Email Address:</strong> to issue your license key and send your receipt.</li>
              <li><strong>Mac Hardware Identifier:</strong> upon activating a license, the app sends your Mac&apos;s hardware UUID (IOPlatformUUID) and computer name solely to enforce seat limits (1, 2 or 5 Macs depending on your plan). For free trials, we store only a salted cryptographic hash of that identifier so each Mac gets one trial.</li>
              <li><strong>Updates:</strong> the app periodically checks our signed update feed for new releases without sending personal data or file paths.</li>
              <li><strong>Website Cookies:</strong> we use a language preference cookie (<code>findaro-lang</code>, 1 year) and a first-touch campaign attribution cookie (<code>findaro_utm</code>, 30 days). We do not use third-party ad tracking cookies.</li>
            </ul>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Trusted Infrastructure Providers</h2>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Stripe:</strong> PCI-DSS Level 1 certified payment processor.</li>
              <li><strong>Resend:</strong> transactional email delivery for your license key.</li>
              <li><strong>Dedicated automation gateway (n8n):</strong> processes Stripe checkout verification and transactional email delivery.</li>
            </ul>
            <p>
              <strong>We never sell, rent, or share your personal information with third parties for advertising or marketing purposes.</strong>
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>5. Contact & Data Rights</h2>
            <p>
              You may request access, correction, or deletion of your customer records at any time by emailing:{" "}
              <a href="mailto:support@findaro.iareal.net" style={{ color: "#38bdf8" }}>
                support@findaro.iareal.net
              </a>.
            </p>
          </div>
        ) : (
          <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Filosofía Local-First (Tus archivos nunca salen de tu Mac)</h2>
            <p>
              Findaro es una aplicación nativa diseñada con arquitectura <strong>100% local</strong>. No recopilamos, indexamos ni transmitimos el contenido de tus archivos, carpetas, imágenes o documentos a ningún servidor externo o en la nube.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>2. Asistente de Inteligencia Artificial</h2>
            <p>
              El asistente inteligente de Findaro funciona mediante modelos locales alojados en tu propia máquina (a través de Ollama) o mediante analizadores basados en reglas internas. Ningún texto que ingreses en el asistente ni los nombres de tus archivos son enviados a servidores de terceros para entrenamiento o análisis.
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>3. Datos recopilados al realizar una compra</h2>
            <p>
              Cuando adquieres una licencia en nuestro sitio web, recopilamos únicamente los datos mínimos indispensables para prestar el servicio:
            </p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Nombre y Correo Electrónico:</strong> para emitir tu clave de licencia y enviarte el recibo de compra.</li>
              <li><strong>Identificador de tu Mac:</strong> al activar la licencia, la app envía el identificador de hardware de tu Mac (IOPlatformUUID) y el nombre del equipo. Los usamos solo para contar cuántas Macs tienen activada tu licencia (1, 2 o 5 según tu plan) y evitar el uso no autorizado. Para la prueba gratuita guardamos únicamente un código cifrado (hash con sal) de ese identificador, para que cada Mac tenga una sola prueba.</li>
              <li><strong>Prueba gratuita:</strong> al abrir la app por primera vez, la app envía el identificador de tu Mac a nuestro servidor, que guarda solo un código cifrado (hash con sal) para registrar el inicio de los 14 días de prueba.</li>
              <li><strong>Actualizaciones:</strong> la app consulta periódicamente nuestro servidor para saber si hay una versión nueva. Esa consulta no incluye tus datos personales ni tus archivos.</li>
              <li><strong>Cookies del sitio web:</strong> usamos una cookie de idioma (<code>findaro-lang</code>, 1 año) y una cookie de atribución de campañas (<code>findaro_utm</code>, 30 días) que guarda de qué anuncio o enlace llegaste. No usamos cookies de publicidad de terceros.</li>
            </ul>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>4. Terceros de Confianza</h2>
            <p>
              Utilizamos servicios de infraestructura reconocidos con los más altos estándares de seguridad:
            </p>
            <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
              <li><strong>Stripe:</strong> pasarela de pago certificada PCI-DSS Nivel 1.</li>
              <li><strong>Resend:</strong> envío seguro de correos transaccionales con tu clave de licencia.</li>
              <li><strong>Servidor de automatización propio (n8n):</strong> procesa la creación del pago con Stripe, la verificación del pago y el envío de correos.</li>
            </ul>
            <p>
              <strong>Nunca vendemos, alquilamos ni compartimos tus datos personales con terceros para fines comerciales o de publicidad.</strong>
            </p>

            <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>5. Contacto</h2>
            <p>
              Puedes ejercer tus derechos de acceso, rectificación o eliminación de tus datos de cliente escribiendo a:{" "}
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
