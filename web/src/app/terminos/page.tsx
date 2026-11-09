import Link from "next/link";
import styles from "../marketing.module.css";

export const metadata = {
  title: "Términos del Servicio — FINDARO",
  description: "Términos y condiciones de uso de la licencia de Findaro para macOS.",
};

export default function TerminosPage() {
  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <p className={styles.brand}>FINDARO</p>
        <h1 style={{ fontSize: "24px", margin: "0 0 16px" }}>Términos del Servicio</h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          Última actualización: Noviembre 2026
        </p>

        <div style={{ fontSize: "14px", lineHeight: "1.7", color: "#cbd5e1" }}>
          <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>1. Concesión de Licencia</h2>
          <p>
            Al adquirir Findaro, se te concede una licencia perpetua, no exclusiva e intransferible para instalar y utilizar el software en sistemas macOS:
          </p>
          <ul style={{ paddingLeft: "20px", margin: "8px 0" }}>
            <li><strong>Plan Personal ($39 USD):</strong> hasta 2 ordenadores Mac simultáneos de tu propiedad.</li>
            <li><strong>Plan Familiar / Pro ($59 USD):</strong> hasta 5 ordenadores Mac simultáneos de tu propiedad o núcleo familiar.</li>
          </ul>
          <p>
            Puedes desactivar cualquier Mac en cualquier momento desde las preferencias de la aplicación para transferir tu cupo a un nuevo equipo.
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

          <h2 style={{ fontSize: "16px", color: "#fff", marginTop: "16px" }}>5. Contacto</h2>
          <p>
            Para consultas legales, facturación o soporte técnico, contáctanos en:{" "}
            <a href="mailto:soporte@findaro.iareal.net" style={{ color: "#38bdf8" }}>
              soporte@findaro.iareal.net
            </a>.
          </p>
        </div>

        <div style={{ marginTop: "28px", paddingTop: "16px", borderTop: "1px solid #1e293b", textAlign: "center" }}>
          <Link href="/comprar" style={{ color: "#38bdf8", fontSize: "13px", textDecoration: "none" }}>
            ← Volver a la página de compra
          </Link>
        </div>
      </div>
    </main>
  );
}
