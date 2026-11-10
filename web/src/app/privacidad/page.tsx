import Link from "next/link";
import styles from "../marketing.module.css";

export const metadata = {
  title: "Política de Privacidad — FINDARO",
  description: "Política de privacidad y protección de datos de Findaro para macOS.",
};

export default function PrivacidadPage() {
  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640, textAlign: "left" }}>
        <p className={styles.brand}>FINDARO</p>
        <h1 style={{ fontSize: "24px", margin: "0 0 16px" }}>Política de Privacidad</h1>
        <p style={{ fontSize: "12px", color: "#94a3b8", marginBottom: "20px" }}>
          Última actualización: Noviembre 2026
        </p>

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
            <li><strong>Identificador de tu Mac:</strong> al activar la licencia, la app envía el identificador de hardware de tu Mac (IOPlatformUUID) y el nombre del equipo. Los usamos solo para contar cuántas Macs tienen activada tu licencia (2 o 5 según tu plan) y evitar el uso no autorizado. Para la prueba gratuita guardamos únicamente un código cifrado (hash con sal) de ese identificador, para que cada Mac tenga una sola prueba.</li>
            <li><strong>Prueba gratuita:</strong> al abrir la app por primera vez, se envía el identificador cifrado de tu Mac a nuestro servidor para registrar el inicio de los 5 días de prueba.</li>
            <li><strong>Actualizaciones:</strong> la app consulta periódicamente nuestro servidor para saber si hay una versión nueva. Esa consulta no incluye tus datos personales ni tus archivos.</li>
            <li><strong>Cookies del sitio web:</strong> usamos una cookie de idioma (findaro_lang, 1 año) y una cookie de atribución de campañas (findaro_utm, 30 días) que guarda de qué anuncio o enlace llegaste. No usamos cookies de publicidad de terceros.</li>
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

        <div style={{ marginTop: "28px", paddingTop: "16px", borderTop: "1px solid #1e293b", textAlign: "center" }}>
          <Link href="/comprar" style={{ color: "#38bdf8", fontSize: "13px", textDecoration: "none" }}>
            ← Volver a la página de compra
          </Link>
        </div>
      </div>
    </main>
  );
}
