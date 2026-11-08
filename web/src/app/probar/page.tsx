"use client";

import { FormEvent, useState } from "react";
import styles from "../marketing.module.css";

export default function ProbarPage() {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{
    licenseKey: string;
    downloadUrl: string;
    message: string;
    trialDays?: number;
  } | null>(null);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/trial", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error || "No se pudo crear la prueba");
      setResult({
        licenseKey: json.data.licenseKey,
        downloadUrl: json.data.downloadUrl,
        message: json.data.message,
        trialDays: json.data.trialDays,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className={styles.page}>
      <div className={styles.card}>
        <p className={styles.brand}>FINDARO</p>
        <h1>Prueba 5 días gratis</h1>
        <p className={styles.sub}>
          1 Mac · sin tarjeta. Al terminar, compra Pro de por vida (desde $39 USD primeros 1000).
        </p>

        {!result ? (
          <form className={styles.form} onSubmit={onSubmit}>
            <label>
              Nombre
              <input
                required
                minLength={2}
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoComplete="name"
              />
            </label>
            <label>
              Correo
              <input
                required
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </label>
            {error && <p className={styles.error}>{error}</p>}
            <button className={styles.cta} type="submit" disabled={busy}>
              {busy ? "Preparando…" : "Descargar prueba gratis"}
            </button>
          </form>
        ) : (
          <div className={styles.priceBox}>
            <p>{result.message}</p>
            <p>
              <strong>Tu clave (1 Mac):</strong>
              <br />
              <code>{result.licenseKey}</code>
            </p>
            <a className={styles.cta} href={result.downloadUrl}>
              Descargar Findaro.dmg
            </a>
            <p className={styles.note}>
              En Findaro: Ajustes → Licencia → pega la clave. La prueba dura{" "}
              {result.trialDays ?? 5} días.
            </p>
            <a className={styles.secondary} href="/comprar">
              Comprar Pro ahora
            </a>
          </div>
        )}
      </div>
    </main>
  );
}
