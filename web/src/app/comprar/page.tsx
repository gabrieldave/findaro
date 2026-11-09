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
  const initialLang = searchParams.get("lang") === "en" ? "en" : "es";

  const [lang, setLang] = useState<"es" | "en">(initialLang);
  const [selectedTier, setSelectedTier] = useState<TierKey>("personal");
  const [referralCode, setReferralCode] = useState(urlRef);
  const [refValid, setRefValid] = useState(false);
  const [refStatus, setRefStatus] = useState<"idle" | "valid" | "invalid">("idle");
  const [offer, setOffer] = useState<Offer | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isEn = lang === "en";
  const t = {
    title: isEn ? "Lifetime License" : "Licencia de por vida",
    sub: isEn
      ? "One-time payment forever. Free updates and all future features included."
      : "Un solo pago para siempre. Actualizaciones y nuevas funciones incluidas.",
    personalTier: "Personal",
    familyTier: isEn ? "Family / Pro" : "Familiar / Pro",
    personalDesc: isEn ? "2 Macs lifetime" : "2 Macs de por vida",
    familyDesc: isEn ? "5 Macs lifetime" : "5 Macs de por vida",
    refValidMsg: (code: string, discount: number) =>
      isEn
        ? `✓ Referral coupon active: ${code} (-$${discount} USD discount applied)`
        : `✓ Cupón de referido activo: ${code} (-$${discount} USD descuento aplicado)`,
    refInvalidMsg: (code: string) =>
      isEn
        ? `✕ Code ${code} not found. Regular price will apply.`
        : `✕ Código ${code} no encontrado. Se aplicará el precio regular.`,
    nameLabel: isEn ? "Full Name" : "Nombre",
    namePlaceholder: isEn ? "Your name" : "Tu nombre",
    emailLabel: isEn ? "Email" : "Correo",
    emailPlaceholder: "tu@email.com",
    refLabel: isEn ? "Referral / Promo code (optional)" : "Código de referido (opcional)",
    refPlaceholder: isEn ? "e.g. DAVE-8F12" : "Ej. DAVE-8F12",
    payButton: (price: number, tier: string) =>
      isEn
        ? `Pay $${price} USD with Stripe (${tier === "family" ? "5 Macs" : "2 Macs"})`
        : `Pagar $${price} USD con Stripe (${tier === "family" ? "5 Macs" : "2 Macs"})`,
    busyButton: isEn ? "Redirecting to Stripe…" : "Redirigiendo a Stripe…",
    securityNote: isEn
      ? "🛡️ 100% secure payment with Stripe. No subscriptions or hidden fees. Referral rewards: share your link to earn $10 USD directly to your card for each recommendation."
      : "🛡️ Pago 100% seguro con Stripe. Sin suscripciones ni cobros ocultos. ¿Tienes amigos? Al comprar recibirás tu enlace para ganar $10 USD directo a tu tarjeta por cada recomendación.",
    footerNote: isEn
      ? "Findaro for macOS · 14-day satisfaction guarantee"
      : "Findaro para macOS · Garantía de satisfacción de 14 días",
    terms: isEn ? "Terms of Service" : "Términos de Servicio",
    privacy: isEn ? "Privacy" : "Privacidad",
    refund: isEn ? "Refund Policy" : "Política de Reembolso",
    contact: isEn ? "Contact" : "Contacto",
  };

  useEffect(() => {
    if (urlRef) setReferralCode(urlRef);
  }, [urlRef]);

  useEffect(() => {
    const trimmed = referralCode.trim();
    if (!trimmed) {
      setRefStatus("idle");
      setRefValid(false);
      return;
    }
    const timer = setTimeout(() => {
      fetch(`/api/promo/validate?code=${encodeURIComponent(trimmed)}`)
        .then((r) => r.json())
        .then((j) => {
          if (j.ok && j.data?.valid) {
            setRefValid(true);
            setRefStatus("valid");
          } else {
            setRefValid(false);
            setRefStatus("invalid");
          }
        })
        .catch(() => {
          setRefValid(false);
          setRefStatus("idle");
        });
    }, 400);
    return () => clearTimeout(timer);
  }, [referralCode]);

  useEffect(() => {
    fetch("/api/promo")
      .then((r) => r.json())
      .then((j) => j.ok && setOffer(j.data))
      .catch(() => setOffer(null));
  }, []);

  const basePrice = selectedTier === "family" ? 59 : 39;
  const hasDiscount = refValid;
  const discountAmount = selectedTier === "family" ? 6 : 4;
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
          referralCode: hasDiscount ? referralCode.trim() : undefined,
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
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <button
            type="button"
            onClick={() => setLang(isEn ? "es" : "en")}
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
        <p className={styles.sub}>
          {t.sub}
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
            <div style={{ fontSize: "14px", fontWeight: "bold" }}>{t.personalTier}</div>
            <div style={{ fontSize: "20px", fontWeight: 800, marginTop: "4px" }}>
              ${hasDiscount ? 35 : 39} <span style={{ fontSize: "12px", fontWeight: "normal", color: "#94a3b8" }}>USD</span>
            </div>
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>{t.personalDesc}</div>
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
            <div style={{ fontSize: "14px", fontWeight: "bold" }}>{t.familyTier}</div>
            <div style={{ fontSize: "20px", fontWeight: 800, marginTop: "4px" }}>
              ${hasDiscount ? 53 : 59} <span style={{ fontSize: "12px", fontWeight: "normal", color: "#94a3b8" }}>USD</span>
            </div>
            <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>{t.familyDesc}</div>
          </button>
        </div>

        {refStatus === "valid" && (
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
            {t.refValidMsg(referralCode, discountAmount)}
          </div>
        )}

        {refStatus === "invalid" && (
          <div
            style={{
              background: "rgba(239, 68, 68, 0.12)",
              border: "1px solid rgba(239, 68, 68, 0.3)",
              color: "#f87171",
              padding: "10px 14px",
              borderRadius: "8px",
              fontSize: "13px",
              marginBottom: "16px",
            }}
          >
            {t.refInvalidMsg(referralCode)}
          </div>
        )}

        <form className={styles.form} onSubmit={onSubmit}>
          <label>
            {t.nameLabel}
            <input
              required
              minLength={2}
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={t.namePlaceholder}
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
              placeholder={t.emailPlaceholder}
              autoComplete="email"
            />
          </label>
          <label>
            {t.refLabel}
            <input
              value={referralCode}
              onChange={(e) => setReferralCode(e.target.value.toUpperCase())}
              placeholder={t.refPlaceholder}
            />
          </label>

          {error && <p className={styles.error}>{error}</p>}

          <button type="submit" disabled={busy} className={styles.cta}>
            {busy ? t.busyButton : t.payButton(finalPrice, selectedTier)}
          </button>
        </form>

        <p className={styles.note}>
          {t.securityNote}
        </p>

        <footer style={{ marginTop: 24, paddingTop: 16, borderTop: "1px solid #1e293b", textAlign: "center", fontSize: 12, color: "#64748b" }}>
          <div>{t.footerNote}</div>
          <div style={{ marginTop: 6, display: "flex", justifyContent: "center", gap: 12, flexWrap: "wrap" }}>
            <Link href="/terminos" style={{ color: "#94a3b8", textDecoration: "underline" }}>{t.terms}</Link>
            <span>·</span>
            <Link href="/privacidad" style={{ color: "#94a3b8", textDecoration: "underline" }}>{t.privacy}</Link>
            <span>·</span>
            <Link href="/reembolso" style={{ color: "#94a3b8", textDecoration: "underline" }}>{t.refund}</Link>
            <span>·</span>
            <a href="mailto:david.del.rio.colin@gmail.com" style={{ color: "#94a3b8", textDecoration: "underline" }}>{t.contact}</a>
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
