import Link from "next/link";
import styles from "../marketing.module.css";

export const metadata = {
  title: "Política de Reembolso — FINDARO",
  description: "Garantía de satisfacción de 14 días y política de reembolsos de Findaro para macOS.",
};

export default function ReembolsoPage() {
  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <p className={styles.brand}>FINDARO</p>
        <h1 style={{ fontSize: "24px", margin: "0 0 16px" }}>Garantía y Política de Reembolso</h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          Última actualización: Noviembre 2026
        </p>

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
          <p>
            Incluye:
          </p>
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

        <div style={{ marginTop: "28px", paddingTop: "16px", borderTop: "1px solid #1e293b", textAlign: "center" }}>
          <Link href="/comprar" style={{ color: "#38bdf8", fontSize: "13px", textDecoration: "none" }}>
            ← Volver a la página de compra
          </Link>
        </div>
      </div>
    </main>
  );
}
