import styles from "./page.module.css";

const WHATSAPP = "https://wa.me/525645674407";

export default function Home() {
  return (
    <main className={styles.page}>
      <div className={styles.atmosphere} aria-hidden />
      <header className={styles.hero}>
        <p className={styles.brand}>FINDARO</p>
        <h1 className={styles.headline}>Tus archivos, bajo control.</h1>
        <p className={styles.sub}>
          Explorador avanzado para macOS. Doble panel, Smart Merge, bandeja y
          búsqueda recursiva — nativo, rápido y profesional.
        </p>
        <div className={styles.actions}>
          <a className={styles.primary} href="#descargar">
            Descargar para Mac
          </a>
          <a className={styles.secondary} href={WHATSAPP} target="_blank" rel="noreferrer">
            Hablar por WhatsApp
          </a>
        </div>
      </header>

      <section className={styles.section} aria-labelledby="feats">
        <h2 id="feats">Hecho para quien vive en el Finder</h2>
        <ul className={styles.list}>
          <li>Doble panel Origen → Destino con transferencias verificadas</li>
          <li>Smart Merge con SHA-256 y rollback de lotes</li>
          <li>FSEvents: la lista se actualiza al instante</li>
          <li>Asistente local (reglas + Ollama opcional) y voz on-device</li>
        </ul>
      </section>

      <section className={styles.section} id="descargar" aria-labelledby="dl">
        <h2 id="dl">macOS 15+ · Apple Silicon</h2>
        <p className={styles.sub}>
          Empaquetado como aplicación nativa. Actualizaciones por canal HTTPS
          firmado cuando dirección autorice la publicación.
        </p>
        <a className={styles.primary} href="https://ordena.iareal.net/downloads/Findaro-latest.dmg">
          Obtener Findaro
        </a>
      </section>

      <footer className={styles.footer}>
        <span>FINDARO</span>
        <span>Encuentra. Organiza. Avanza.</span>
      </footer>
    </main>
  );
}
