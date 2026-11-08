"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

type ConfirmData = {
  downloadUrl: string;
  licenseKey: string;
  name: string;
  seats: number;
  referralCode?: string;
  referralLink?: string;
};

function GraciasInner() {
  const params = useSearchParams();
  const sessionId = params.get("session_id") || "";
  const [data, setData] = useState<ConfirmData | null>(null);
  const [msg, setMsg] = useState("Confirmando tu pago en Stripe…");
  const [copiedKey, setCopiedKey] = useState(false);
  const [copiedRef, setCopiedRef] = useState(false);

  useEffect(() => {
    if (!sessionId) {
      setMsg("Falta session_id. Si ya pagaste, revisa tu correo electrónico.");
      return;
    }
    let tries = 0;
    const tick = async () => {
      tries += 1;
      try {
        const res = await fetch("/api/gracias/confirm", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ sessionId }),
        });
        const json = await res.json();
        if (json.ok && json.data?.downloadUrl) {
          setData(json.data);
          setMsg(`¡Todo listo, ${json.data.name || "amigo"}! Tu licencia y descarga están activas.`);
          return;
        }
      } catch {}

      if (tries < 15) {
        setMsg("Esperando confirmación final de Stripe…");
        setTimeout(tick, 2500);
      } else {
        setMsg("El pago fue recibido. Si la confirmación tarda más de un minuto, refresca esta página o contáctanos.");
      }
    };
    void tick();
  }, [sessionId]);

  const copyKey = () => {
    if (!data?.licenseKey) return;
    navigator.clipboard.writeText(data.licenseKey);
    setCopiedKey(true);
    setTimeout(() => setCopiedKey(false), 2000);
  };

  const copyRef = () => {
    if (!data?.referralLink) return;
    navigator.clipboard.writeText(data.referralLink);
    setCopiedRef(true);
    setTimeout(() => setCopiedRef(false), 2000);
  };

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 540 }}>
        <p className={styles.brand}>FINDARO</p>
        <h1>¡Pago confirmado!</h1>
        <p className={styles.sub}>{msg}</p>

        {data && (
          <div style={{ marginTop: 24, textAlign: "left" }}>
            {/* Clave de Licencia */}
            <div
              style={{
                background: "rgba(15, 23, 42, 0.8)",
                border: "1px solid #334155",
                borderRadius: 10,
                padding: 16,
                marginBottom: 16,
              }}
            >
              <div style={{ fontSize: 13, color: "#94a3b8", marginBottom: 6 }}>
                Tu clave de licencia ({data.seats} {data.seats === 1 ? "Mac" : "Macs"}):
              </div>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  background: "#020617",
                  padding: "10px 14px",
                  borderRadius: 6,
                  fontFamily: "monospace",
                  fontSize: 16,
                  color: "#38bdf8",
                  fontWeight: "bold",
                }}
              >
                <span>{data.licenseKey}</span>
                <button
                  type="button"
                  onClick={copyKey}
                  style={{
                    background: copiedKey ? "#22c55e" : "#1e293b",
                    color: "#fff",
                    border: "none",
                    padding: "6px 12px",
                    borderRadius: 4,
                    cursor: "pointer",
                    fontSize: 12,
                  }}
                >
                  {copiedKey ? "¡Copiada!" : "Copiar"}
                </button>
              </div>
              <p style={{ fontSize: 12, color: "#64748b", marginTop: 8 }}>
                Abre Findaro → Preferencias (⌘,) → Licencia y pega tu clave para activar.
              </p>
            </div>

            {/* Botón de Descarga */}
            <a
              className={styles.cta}
              href={data.downloadUrl}
              style={{ display: "block", textAlign: "center", marginBottom: 20 }}
            >
              ⬇️ Descargar Findaro para macOS
            </a>

            {/* Caja de Referidos y Cashback */}
            {data.referralLink && (
              <div
                style={{
                  background: "rgba(34, 197, 94, 0.08)",
                  border: "1px solid rgba(34, 197, 94, 0.25)",
                  borderRadius: 10,
                  padding: 16,
                }}
              >
                <div style={{ fontSize: 14, fontWeight: "bold", color: "#4ade80", marginBottom: 6 }}>
                  💰 Recupera tu dinero: $10 USD de cashback por amigo
                </div>
                <p style={{ fontSize: 13, color: "#cbd5e1", lineHeight: 1.5, marginBottom: 12 }}>
                  Comparte tu enlace. Tus amigos reciben <strong>10% de descuento ($35 USD)</strong> y nosotros te
                  reembolsamos <strong>$10 USD directo a tu tarjeta</strong> por cada uno. Con 3 amigos, tu Findaro
                  te sale <strong>100% gratis</strong>.
                </p>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 8,
                    background: "#020617",
                    padding: "8px 12px",
                    borderRadius: 6,
                  }}
                >
                  <input
                    readOnly
                    value={data.referralLink}
                    style={{
                      background: "transparent",
                      border: "none",
                      color: "#94a3b8",
                      fontSize: 12,
                      width: "100%",
                      outline: "none",
                    }}
                  />
                  <button
                    type="button"
                    onClick={copyRef}
                    style={{
                      background: copiedRef ? "#22c55e" : "#0284c7",
                      color: "#fff",
                      border: "none",
                      padding: "6px 12px",
                      borderRadius: 4,
                      cursor: "pointer",
                      fontSize: 12,
                      whiteSpace: "nowrap",
                    }}
                  >
                    {copiedRef ? "¡Copiado!" : "Copiar enlace"}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </main>
  );
}

export default function GraciasPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Cargando…</p></main>}>
      <GraciasInner />
    </Suspense>
  );
}
