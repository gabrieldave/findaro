"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

function ProbarInner() {
  const searchParams = useSearchParams();
  const paramLang = searchParams.get("lang");
  const autoDl = searchParams.get("dl") === "1";

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
  const [downloadStarted, setDownloadStarted] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<{
    licenseKey: string;
    downloadUrl: string;
    message: string;
    trialDays?: number;
  } | null>(null);

  const isEn = lang === "en";
  const directDownloadHref = "/api/download?direct=1";

  useEffect(() => {
    if (!autoDl || downloadStarted) return;
    setDownloadStarted(true);
    const iframe = document.createElement("iframe");
    iframe.style.display = "none";
    iframe.src = directDownloadHref;
    document.body.appendChild(iframe);
    const timer = setTimeout(() => {
      iframe.remove();
    }, 15000);
    return () => clearTimeout(timer);
  }, [autoDl, downloadStarted]);

  const handleToggleLang = () => {
    const nextLang = isEn ? "es" : "en";
    setLang(nextLang);
    if (typeof document !== "undefined") {
      document.cookie = `findaro_lang=${nextLang}; path=/; max-age=31536000`;
    }
  };

  const t = {
    title: isEn ? "Download Findaro — 14 Days Free" : "Descarga Findaro — 14 días gratis",
    sub: isEn
      ? "1-click .dmg installer · Apple Silicon (M1+) · macOS 15+ · No credit card or signup required. Optional lifetime license from $29 USD."
      : "Instalador .dmg en 1 clic · Apple Silicon (M1+) · macOS 15+ · Sin tarjeta ni registro obligatorio. Licencia vitalicia opcional desde $29 USD.",
    directBtn: isEn
      ? "Download Findaro.dmg Now (Free 14-Day Trial)"
      : "Descargar Findaro.dmg ahora (14 días gratis)",
    directHint: downloadStarted
      ? isEn
        ? "Your download is starting… If it didn't start automatically, click the button above."
        : "Tu descarga está comenzando… Si no arrancó sola, haz clic en el botón de arriba."
      : isEn
        ? "Signed with Apple Developer ID & Notarized · Instant launch, no Gatekeeper warnings."
        : "Firmado con Apple Developer ID y notarizado · Arranque directo sin alertas de Gatekeeper.",
    optionalHeading: isEn
      ? "While Findaro downloads: get your Pro Keyboard Cheat Sheet & trial key"
      : "Mientras se descarga Findaro: recibe la guía de atajos Pro y novedades en tu correo",
    optionalSub: isEn
      ? "100% optional. Leave your name and email to receive the keyboard cheat sheet, 14-day key backup, and major release notes."
      : "100% opcional. Déjanos tu nombre y correo para recibir la guía de atajos Pro, respaldo de tu clave de 14 días y novedades.",
    nameLabel: isEn ? "Full Name" : "Nombre",
    emailLabel: isEn ? "Email" : "Correo",
    busyBtn: isEn ? "Sending guide & key…" : "Enviando guía y clave…",
    submitBtn: isEn ? "Send Me the Pro Cheat Sheet & Key" : "Recibir guía de atajos Pro y clave",
    keyLabel: isEn ? "Your license key (1 Mac):" : "Tu clave (1 Mac):",
    downloadBtn: isEn ? "Download Findaro.dmg Again" : "Volver a descargar Findaro.dmg",
    note: (days: number) =>
      isEn
        ? `In Findaro: Settings → License → paste your key. Your trial lasts ${days} days.`
        : `En Findaro: Ajustes → Licencia → pega la clave. La prueba dura ${days} días.`,
    upgradeBtn: isEn ? "Buy Lifetime License (from $29)" : "Comprar licencia de por vida (desde $29)",
    guarantee: isEn
      ? "14-day free trial without card + 14-day no-questions-asked money-back guarantee."
      : "14 días de prueba gratis sin tarjeta + Garantía de reembolso de 14 días sin preguntas.",
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

        <div style={{ margin: "18px 0 22px" }}>
          <a
            className={styles.cta}
            href={directDownloadHref}
            onClick={() => setDownloadStarted(true)}
            style={{ display: "block", textAlign: "center", textDecoration: "none" }}
          >
            {t.directBtn}
          </a>
          <p className={styles.note} style={{ marginTop: 8, textAlign: "center" }}>
            {t.directHint}
          </p>
        </div>

        {!result ? (
          <div
            style={{
              padding: "16px",
              borderRadius: "12px",
              background: "rgba(15, 23, 42, 0.55)",
              border: "1px solid rgba(56, 189, 248, 0.2)",
            }}
          >
            <p style={{ margin: "0 0 6px", fontWeight: 700, fontSize: "14px", color: "#e2e8f0" }}>
              {t.optionalHeading}
            </p>
            <p style={{ margin: "0 0 12px", fontSize: "12.5px", color: "#94a3b8", lineHeight: 1.45 }}>
              {t.optionalSub}
            </p>
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
              <button className={styles.secondary} type="submit" disabled={busy}>
                {busy ? t.busyBtn : t.submitBtn}
              </button>
            </form>
          </div>
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
              {t.note(result.trialDays ?? 14)}
            </p>
            <Link className={styles.secondary} href={`/comprar?lang=${lang}`}>
              {t.upgradeBtn}
            </Link>
          </div>
        )}

        <p className={styles.note} style={{ marginTop: 18, textAlign: "center" }}>
          🛡️ {t.guarantee}
        </p>
      </div>
    </main>
  );
}

export default function ProbarClient() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <ProbarInner />
    </Suspense>
  );
}
