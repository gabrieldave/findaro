"use client";

import { FormEvent, Suspense, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

function ProbarInner() {
  const searchParams = useSearchParams();
  const paramLang = searchParams.get("lang");

  const [lang, setLang] = useState<"es" | "en">(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    if (typeof document !== "undefined") {
      const match = document.cookie.match(/findaro_lang=(en|es)/);
      if (match) return match[1] as "es" | "en";
    }
    return "en"; // Global default: English
  });

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

  const isEn = lang === "en";

  const handleToggleLang = () => {
    const nextLang = isEn ? "es" : "en";
    setLang(nextLang);
    if (typeof document !== "undefined") {
      document.cookie = `findaro_lang=${nextLang}; path=/; max-age=31536000`;
    }
  };

  const t = {
    title: isEn ? "Try 5 Days Free" : "Prueba 5 días gratis",
    sub: isEn
      ? "1 Mac · no credit card required. After trial, upgrade to a lifetime license (from $39 USD)."
      : "1 Mac · sin tarjeta. Al terminar, compra Pro de por vida (desde $39 USD).",
    nameLabel: isEn ? "Full Name" : "Nombre",
    emailLabel: isEn ? "Email" : "Correo",
    busyBtn: isEn ? "Preparing trial…" : "Preparando…",
    submitBtn: isEn ? "Download Free Trial" : "Descargar prueba gratis",
    keyLabel: isEn ? "Your license key (1 Mac):" : "Tu clave (1 Mac):",
    downloadBtn: isEn ? "Download Findaro.dmg" : "Descargar Findaro.dmg",
    note: (days: number) =>
      isEn
        ? `In Findaro: Settings → License → paste your key. Your trial lasts ${days} days.`
        : `En Findaro: Ajustes → Licencia → pega la clave. La prueba dura ${days} días.`,
    upgradeBtn: isEn ? "Buy Lifetime License Now" : "Comprar Pro ahora",
  };

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const utmSource = searchParams.get("utm_source");
      const utmMedium = searchParams.get("utm_medium");
      const utmCampaign = searchParams.get("utm_campaign");
      const utmContent = searchParams.get("utm_content");

      let cookieUtm: Record<string, string> = {};
      if (typeof document !== "undefined") {
        try {
          const match = document.cookie.match(/(?:^|; )findaro_utm=([^;]*)/);
          if (match) cookieUtm = JSON.parse(decodeURIComponent(match[1]));
        } catch {}
      }

      const res = await fetch("/api/trial", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          email,
          lang,
          utm_source: utmSource || cookieUtm.utm_source,
          utm_medium: utmMedium || cookieUtm.utm_medium,
          utm_campaign: utmCampaign || cookieUtm.utm_campaign,
          utm_content: utmContent || cookieUtm.utm_content,
        }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error || (isEn ? "Could not create trial" : "No se pudo crear la prueba"));
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
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <button
            type="button"
            onClick={handleToggleLang}
            style={{
              background: "rgba(56, 189, 248, 0.12)",
              border: "1px solid rgba(56, 189, 248, 0.3)",
              color: "#38bdf8",
              borderRadius: "6px",
              padding: "4px 10px",
              fontSize: "12px",
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            🌐 {isEn ? "Español" : "English"}
          </button>
        </div>

        <h1 style={{ marginTop: "12px" }}>{t.title}</h1>
        <p className={styles.sub}>{t.sub}</p>

        {!result ? (
          <form className={styles.form} onSubmit={onSubmit}>
            <label>
              {t.nameLabel}
              <input
                required
                minLength={2}
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoComplete="name"
              />
            </label>
            <label>
              {t.emailLabel}
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
              {busy ? t.busyBtn : t.submitBtn}
            </button>
          </form>
        ) : (
          <div className={styles.priceBox}>
            <p>{result.message}</p>
            {result.licenseKey ? (
              <p>
                <strong>{t.keyLabel}</strong>
                <br />
                <code>{result.licenseKey}</code>
              </p>
            ) : null}
            {result.downloadUrl ? (
              <a className={styles.cta} href={result.downloadUrl}>
                {t.downloadBtn}
              </a>
            ) : null}
            <p className={styles.note}>
              {t.note(result.trialDays ?? 5)}
            </p>
            <Link className={styles.secondary} href={`/comprar?lang=${lang}`}>
              {t.upgradeBtn}
            </Link>
          </div>
        )}
      </div>
    </main>
  );
}

export default function ProbarPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <ProbarInner />
    </Suspense>
  );
}
