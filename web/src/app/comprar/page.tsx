"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

type TierKey = "personal" | "family";

type Offer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
};

function ComprarInner() {
  const searchParams = useSearchParams();
  const urlRef = searchParams.get("ref") || "";

  const [selectedTier, setSelectedTier] = useState<TierKey>("personal");
  const [referralCode, setReferralCode] = useState(urlRef);
  const [offer, setOffer] = useState<Offer | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (urlRef) setReferralCode(urlRef);
  }, [urlRef]);

  useEffect(() => {
    fetch("/api/promo")
      .then((r) => r.json())
      .then((j) => j.ok && setOffer(j.data))
      .catch(() => setOffer(null));
  }, []);

  const basePrice = selectedTier === "family" ? 59 : 39;
  const hasDiscount = Boolean(referralCode.trim());
  const finalPrice = hasDiscount ? (selectedTier === "family" ? 53 : 35) : basePrice;

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          email,
          tier: selectedTier,
          referralCode: referralCode.trim() || undefined,
        }),
      });
      const json = await res.json();
      if (!json.ok || !json.data?.url) {
        throw new Error(json.error || "No se pudo iniciar el pago");
      }
      window.location.href = json.data.url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error");
      setBusy(false);
    }
  }

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 520 }}>
        <p className={styles.brand}>FINDARO</p>
        <h1>Licencia de por vida</h1>
        <p className={styles.sub}>
          Un solo pago para siempre. Actualizaciones y nuevas funciones incluidas.
        </p>

        {offer && (
          <div style={{ fontSize: "13px", color: "#38bdf8", margin: "14px 0 6px", fontWeight: 500 }}>
            ⚡ {offer.label}
          </div>
        )}

        {/* Selector de Plan */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "12px", margin: "20px 0 10px" }}>
          <button
            type="button"
            onClick={() => setSelectedTier("personal")}
            style={{
              padding: "14px 12px",
              borderRadius: "10px",
              border: selectedTier === "personal" ? "2px solid #38bdf8" : "1px solid #334155",
              background: selectedTier === "personal" ? "rgba(56, 189, 248, 0.12)" : "rgba(15, 23, 42, 0.6)",
              color: "#fff",
              cursor: "pointer",
              textAlign: "left",
            }}
          >
            <div style={{ fontSize: "14px", fontWeight: "bold" }}>Personal</div>
            <div style={{ fontSize: "20px", fontWeight: 800, marginTop: "4px" }}>
              ${hasDiscount ? 35 : 39} <span style={{ fontSize: "12px", fontWeight: "normal", color: "#94a3b8" }}>USD</span>
            </div>
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>2 Macs de por vida</div>
          </button>

          <button
            type="button"
            onClick={() => setSelectedTier("family")}
            style={{
              padding: "14px 12px",
              borderRadius: "10px",
              border: selectedTier === "family" ? "2px solid #a855f7" : "1px solid #334155",
              background: selectedTier === "family" ? "rgba(168, 85, 247, 0.12)" : "rgba(15, 23, 42, 0.6)",
              color: "#fff",
              cursor: "pointer",
              textAlign: "left",
            }}
          >
            <div style={{ fontSize: "14px", fontWeight: "bold" }}>Familiar / Pro</div>
            <div style={{ fontSize: "20px", fontWeight: 800, marginTop: "4px" }}>
              ${hasDiscount ? 53 : 59} <span style={{ fontSize: "12px", fontWeight: "normal", color: "#94a3b8" }}>USD</span>
            </div>
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>5 Macs de por vida</div>
          </button>
        </div>

        {hasDiscount && (
          <div
            style={{
              background: "rgba(34, 197, 94, 0.12)",
              border: "1px solid rgba(34, 197, 94, 0.3)",
              color: "#4ade80",
              padding: "10px 14px",
              borderRadius: "8px",
              fontSize: "13px",
              marginBottom: "16px",
            }}
          >
            ✓ Cupón de referido activo: <strong>{referralCode}</strong> (-$4 USD descuento aplicado)
          </div>
        )}

        <form className={styles.form} onSubmit={onSubmit}>
          <label>
            Nombre
            <input
              required
              minLength={2}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Tu nombre"
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
              placeholder="tu@email.com"
              autoComplete="email"
            />
          </label>
          <label>
            Código de referido (opcional)
            <input
              value={referralCode}
              onChange={(e) => setReferralCode(e.target.value.toUpperCase())}
              placeholder="Ej. DAVE-8F12"
            />
          </label>

          {error && <p className={styles.error}>{error}</p>}

          <button type="submit" disabled={busy} className={styles.cta}>
            {busy ? "Redirigiendo a Stripe…" : `Pagar $${finalPrice} USD con Stripe (${selectedTier === "family" ? "5 Macs" : "2 Macs"})`}
          </button>
        </form>

        <p className={styles.note}>
          🛡️ Pago 100% seguro con Stripe. Sin suscripciones ni cobros ocultos.
          <br />
          ¿Tienes amigos? Al comprar recibirás tu enlace para ganar <strong>$10 USD directo a tu tarjeta</strong> por cada recomendación.
        </p>

        <footer style={{ marginTop: 24, paddingTop: 16, borderTop: "1px solid #1e293b", textAlign: "center", fontSize: 12, color: "#64748b" }}>
          <div>Findaro para macOS · Garantía de satisfacción de 14 días</div>
          <div style={{ marginTop: 6, display: "flex", justifyContent: "center", gap: 12, flexWrap: "wrap" }}>
            <Link href="/terminos" style={{ color: "#94a3b8", textDecoration: "underline" }}>Términos de Servicio</Link>
            <span>·</span>
            <Link href="/privacidad" style={{ color: "#94a3b8", textDecoration: "underline" }}>Privacidad</Link>
            <span>·</span>
            <Link href="/reembolso" style={{ color: "#94a3b8", textDecoration: "underline" }}>Política de Reembolso</Link>
            <span>·</span>
            <a href="mailto:david.del.rio.colin@gmail.com" style={{ color: "#94a3b8", textDecoration: "underline" }}>Contacto</a>
          </div>
        </footer>
      </div>
    </main>
  );
}

export default function ComprarPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Cargando…</p></main>}>
      <ComprarInner />
    </Suspense>
  );
}
