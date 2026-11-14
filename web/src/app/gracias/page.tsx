"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";
import { readClientLang } from "@/lib/lang";

type ConfirmData = {
  downloadUrl: string;
  licenseKey: string;
  name: string;
  seats: number;
  referralCode?: string;
  referralLink?: string;
  keyDeliveredByEmail?: boolean;
};

function GraciasInner() {
  const params = useSearchParams();
  const sessionId = params.get("session_id") || "";
  const paramLang = params.get("lang");

  const [lang, setLang] = useState<"es" | "en">(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    if (typeof document !== "undefined") {
      const saved = readClientLang();
      if (saved) return saved;
    }
    return "en"; // Global default: English
  });

  const isEn = lang === "en";

  const [data, setData] = useState<ConfirmData | null>(null);
  const [msg, setMsg] = useState(isEn ? "Confirming payment with Stripe…" : "Confirmando tu pago en Stripe…");
  const [copiedKey, setCopiedKey] = useState(false);
  const [copiedRef, setCopiedRef] = useState(false);

  const t = {
    title: isEn ? "Thank you for your purchase!" : "¡Gracias por tu compra!",
    missingSession: isEn
      ? "Missing session_id. If you already completed payment, check your email."
      : "Falta session_id. Si ya pagaste, revisa tu correo electrónico.",
    readyMsg: (name: string) =>
      isEn
        ? `You're all set, ${name || "friend"}! Your license and download are active.`
        : `¡Todo listo, ${name || "amigo"}! Tu licencia y descarga están activas.`,
    verifying: isEn ? "Verifying…" : "Verificando…",
    keyTitle: (seats: number) =>
      isEn
        ? `Your Lifetime License Key (${seats} Macs included)`
        : `Tu Clave de Licencia (${seats} Macs incluidas)`,
    copied: isEn ? "Copied!" : "¡Copiado!",
    copyKey: isEn ? "Copy License Key" : "Copiar clave",
    keyHelp: isEn
      ? "In Findaro: Settings → License → paste this key."
      : "En Findaro: Ajustes → Licencia → pega esta clave.",
    downloadBtn: isEn ? "Download Findaro.dmg" : "Descargar Findaro.dmg",
    gatekeeperNote: isEn
      ? "FINDARO is signed with Developer ID and notarized by Apple. Open the DMG, drag to Applications, and launch directly with double-click."
      : "FINDARO está firmado con Developer ID y notarizado por Apple. Abre el DMG, arrastra a Aplicaciones y se abre al instante con doble clic.",
    refBoxTitle: isEn ? "Share Findaro with friends" : "Comparte Findaro con amigos",
    refBoxDesc: isEn
      ? "Your referral code applies an instant discount to your friends on their purchase."
      : "Tu código de referido otorga un descuento inmediato a tus amigos en su compra.",
    copyLink: isEn ? "Copy Link" : "Copiar enlace",
  };

  useEffect(() => {
    if (!sessionId) {
      setMsg(t.missingSession);
      return;
    }
    let tries = 0;
    const tick = async () => {
      tries += 1;
      try {
        const res = await fetch("/api/gracias/confirm", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ sessionId, lang: isEn ? "en" : "es" }),
        });
        const json = await res.json();
        if (json.ok && json.data?.downloadUrl) {
          setData(json.data);
          setMsg(t.readyMsg(json.data.name));
          return;
        }
      } catch {}
      if (tries < 15) {
        setTimeout(tick, 1500);
      } else {
        setMsg(
          isEn
            ? "Your payment was registered. We are delivering your license key by email."
            : "Tu pago se registró. Te estamos enviando la clave y enlace por correo."
        );
      }
    };
    tick();
  }, [sessionId, isEn]);

  async function copyToClipboard(text: string, which: "key" | "ref") {
    try {
      await navigator.clipboard.writeText(text);
      if (which === "key") {
        setCopiedKey(true);
        setTimeout(() => setCopiedKey(false), 2000);
      } else {
        setCopiedRef(true);
        setTimeout(() => setCopiedRef(false), 2000);
      }
    } catch {}
  }

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 560 }}>
        <p className={styles.brand}>FINDARO</p>
        <h1>{t.title}</h1>
        <p className={styles.sub}>{msg}</p>

        {data ? (
          <div className={styles.priceBox}>
            <div style={{ textAlign: "left", marginBottom: 16 }}>
              <div style={{ fontSize: 13, color: "#94a3b8", fontWeight: 600 }}>
                {t.keyTitle(data.seats)}
              </div>
              {data.keyDeliveredByEmail || !data.licenseKey ? (
                <div
                  style={{
                    background: "#0b1220",
                    padding: "12px 14px",
                    borderRadius: 8,
                    marginTop: 6,
                    border: "1px solid #334155",
                    fontSize: 13,
                    color: "#cbd5e1",
                  }}
                >
                  {isEn
                    ? "For your security, your license key is only displayed immediately after checkout and has already been delivered to your email inbox."
                    : "Por tu seguridad, la clave de licencia solo se muestra en pantalla justo después del pago y ya fue enviada a tu correo electrónico."}
                </div>
              ) : (
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    background: "#0b1220",
                    padding: "10px 14px",
                    borderRadius: 8,
                    marginTop: 6,
                    border: "1px solid #334155",
                  }}
                >
                  <code style={{ fontSize: 15, fontWeight: "bold", color: "#38bdf8", wordBreak: "break-all" }}>
                    {data.licenseKey}
                  </code>
                  <button
                    type="button"
                    onClick={() => copyToClipboard(data.licenseKey, "key")}
                    style={{
                      marginLeft: 10,
                      background: copiedKey ? "#22c55e" : "#2563eb",
                      color: "#fff",
                      border: "none",
                      padding: "6px 12px",
                      borderRadius: 6,
                      cursor: "pointer",
                      fontSize: 12,
                      fontWeight: 600,
                    }}
                  >
                    {copiedKey ? t.copied : t.copyKey}
                  </button>
                </div>
              )}
              <div style={{ fontSize: 11, color: "#64748b", marginTop: 4 }}>
                {t.keyHelp}
              </div>
            </div>

            <a className={styles.cta} href={data.downloadUrl} style={{ display: "block", textAlign: "center" }}>
              {t.downloadBtn}
            </a>

            <p style={{ fontSize: 12, color: "#94a3b8", marginTop: 12 }}>
              {t.gatekeeperNote}
            </p>

            {data.referralLink && (
              <div
                style={{
                  marginTop: 20,
                  padding: 16,
                  background: "rgba(56, 189, 248, 0.08)",
                  border: "1px solid rgba(56, 189, 248, 0.2)",
                  borderRadius: 10,
                  textAlign: "left",
                }}
              >
                <div style={{ fontSize: 14, fontWeight: "bold", color: "#38bdf8" }}>
                  💰 {t.refBoxTitle}
                </div>
                <div style={{ fontSize: 12, color: "#cbd5e1", marginTop: 4 }}>
                  {t.refBoxDesc}
                </div>
                <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                  <input
                    readOnly
                    value={data.referralLink}
                    style={{
                      flex: 1,
                      background: "#0b1220",
                      border: "1px solid #334155",
                      borderRadius: 6,
                      color: "#94a3b8",
                      padding: "6px 10px",
                      fontSize: 12,
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => copyToClipboard(data.referralLink!, "ref")}
                    style={{
                      background: copiedRef ? "#22c55e" : "#38bdf8",
                      color: "#0f172a",
                      border: "none",
                      padding: "6px 12px",
                      borderRadius: 6,
                      cursor: "pointer",
                      fontSize: 12,
                      fontWeight: 700,
                    }}
                  >
                    {copiedRef ? t.copied : t.copyLink}
                  </button>
                </div>
              </div>
            )}
          </div>
        ) : (
          <div style={{ padding: "40px 0", textAlign: "center", color: "#94a3b8" }}>
            {t.verifying}
          </div>
        )}
      </div>
    </main>
  );
}

export default function GraciasPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <GraciasInner />
    </Suspense>
  );
}
