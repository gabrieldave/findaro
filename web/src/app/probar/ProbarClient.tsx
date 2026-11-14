"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { funnel } from "@/config/funnel";
import { readClientLang, writeClientLang, type Lang } from "@/lib/lang";
import styles from "../light.module.css";

function ProbarInner() {
  const searchParams = useSearchParams();
  const paramLang = searchParams.get("lang");
  const autoDl = searchParams.get("dl") === "1";

  const [lang, setLang] = useState<Lang>(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    return readClientLang() ?? "en";
  });

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
    const nextLang: Lang = isEn ? "es" : "en";
    setLang(nextLang);
    writeClientLang(nextLang);
  };

  const t = {
    title: isEn ? "Download Findaro, free for 14 days" : "Descarga Findaro, gratis 14 días",
    sub: isEn
      ? `.dmg installer · Apple Silicon (M1 or newer) · macOS ${funnel.minMacOS}+. No card, no account. A lifetime license is optional, from $29 USD.`
      : `Instalador .dmg · Apple Silicon (M1 o posterior) · macOS ${funnel.minMacOS}+. Sin tarjeta ni cuenta. La licencia de por vida es opcional, desde $29 USD.`,
    directBtn: isEn ? "Download Findaro.dmg" : "Descargar Findaro.dmg",
    directHint: downloadStarted
      ? isEn
        ? "Your download is starting. If nothing happens, press the button above."
        : "Tu descarga está empezando. Si no pasa nada, pulsa el botón de arriba."
      : isEn
        ? `Signed with Apple Developer ID (Team ID ${funnel.teamId}) and notarized by Apple: macOS opens it without Gatekeeper warnings.`
        : `Firmado con Apple Developer ID (Team ID ${funnel.teamId}) y notarizado por Apple: macOS lo abre sin alertas de Gatekeeper.`,
    optionalHeading: isEn ? "Optional: get your trial key by email" : "Opcional: recibe tu clave de prueba por correo",
    optionalSub: isEn
      ? "Leave your email and we'll send a backup of your 14-day key, the keyboard cheat sheet and major release notes. You can skip this."
      : "Deja tu correo y te enviamos un respaldo de tu clave de 14 días, la guía de atajos y las novedades importantes. Puedes saltarte esto.",
    emailLabel: isEn ? "Email" : "Correo",
    busyBtn: isEn ? "Sending…" : "Enviando…",
    submitBtn: isEn ? "Email me my trial key" : "Enviarme mi clave de prueba",
    keyLabel: isEn ? "Your trial key (1 Mac):" : "Tu clave de prueba (1 Mac):",
    downloadBtn: isEn ? "Download Findaro.dmg again" : "Volver a descargar Findaro.dmg",
    note: (days: number) =>
      isEn
        ? `In Findaro: Settings → License → paste the key. Your trial lasts ${days} days.`
        : `En Findaro: Ajustes → Licencia → pega la clave. La prueba dura ${days} días.`,
    upgradeBtn: isEn ? "Buy a lifetime license (from $29)" : "Comprar licencia de por vida (desde $29)",
    guarantee: isEn
      ? "14-day trial without a card · 14-day money-back guarantee, no questions asked."
      : "14 días de prueba sin tarjeta · Garantía de reembolso de 14 días, sin preguntas.",
    back: isEn ? "Back to findaro.iareal.net" : "Volver a findaro.iareal.net",
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
          email,
          lang,
          utm_source: utmSource || cookieUtm.utm_source,
          utm_medium: utmMedium || cookieUtm.utm_medium,
          utm_campaign: utmCampaign || cookieUtm.utm_campaign,
          utm_content: utmContent || cookieUtm.utm_content,
        }),
      });
      const json = await res.json();
      if (!json.ok) throw new Error(json.error || (isEn ? "Could not create the trial" : "No se pudo crear la prueba"));
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
        <div className={styles.top}>
          <Link className={styles.brand} href={isEn ? "/" : "/es"} aria-label={t.back}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.png" alt="" width={28} height={28} />
            Findaro
          </Link>
          <button type="button" onClick={handleToggleLang} className={styles.langBtn} lang={isEn ? "es" : "en"}>
            {isEn ? "ES" : "EN"}
          </button>
        </div>

        <h1 className={styles.title}>{t.title}</h1>
        <p className={styles.sub}>{t.sub}</p>

        <div style={{ margin: "22px 0 4px" }}>
          <a className={styles.cta} href={directDownloadHref} onClick={() => setDownloadStarted(true)}>
            {t.directBtn}
          </a>
          <p className={`${styles.note} ${styles.center}`} aria-live="polite">
            {t.directHint}
          </p>
        </div>

        {!result ? (
          <div className={styles.panel}>
            <h2>{t.optionalHeading}</h2>
            <p>{t.optionalSub}</p>
            <form className={styles.form} onSubmit={onSubmit}>
              <label>
                {t.emailLabel}
                <input
                  required
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="email"
                  inputMode="email"
                />
              </label>
              {error && <p className={styles.error}>{error}</p>}
              <button className={styles.secondary} type="submit" disabled={busy}>
                {busy ? t.busyBtn : t.submitBtn}
              </button>
            </form>
          </div>
        ) : (
          <div className={styles.keyBox}>
            <p style={{ margin: 0 }}>{result.message}</p>
            {result.licenseKey ? (
              <p style={{ margin: "12px 0 0" }}>
                <strong>{t.keyLabel}</strong>
                <code>{result.licenseKey}</code>
              </p>
            ) : null}
            {result.downloadUrl ? (
              <a className={styles.cta} href={result.downloadUrl} style={{ marginTop: 14 }}>
                {t.downloadBtn}
              </a>
            ) : null}
            <p className={styles.note}>{t.note(result.trialDays ?? 14)}</p>
            <Link className={styles.secondary} href={`/comprar?lang=${lang}`}>
              {t.upgradeBtn}
            </Link>
          </div>
        )}

        <p className={`${styles.note} ${styles.center}`} style={{ marginTop: 20 }}>
          {t.guarantee}
        </p>
      </div>
    </main>
  );
}

export default function ProbarClient() {
  return (
    <Suspense fallback={<main className={styles.page} />}>
      <ProbarInner />
    </Suspense>
  );
}
