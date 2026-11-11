"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";

type TierKey = "solo" | "personal" | "family";

type Offer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
};

const TIER_META: Record<
  TierKey,
  { seats: number; price: number; discount: number; discounted: number }
> = {
  solo: { seats: 1, price: 29, discount: 3, discounted: 26 },
  personal: { seats: 2, price: 39, discount: 4, discounted: 35 },
  family: { seats: 5, price: 59, discount: 6, discounted: 53 },
};

function ComprarInner() {
  const searchParams = useSearchParams();
  const urlRef = searchParams.get("ref") || "";
  const paramLang = searchParams.get("lang");

  const [lang, setLang] = useState<"es" | "en">(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    if (typeof document !== "undefined") {
      const match = document.cookie.match(/findaro_lang=(en|es)/);
      if (match) return match[1] as "es" | "en";
    }
    return "en";
  });

  // Pro ($39) por defecto: escalón de mejor valor
  const [selectedTier, setSelectedTier] = useState<TierKey>("personal");
  const [referralCode, setReferralCode] = useState(urlRef);
  const [refValid, setRefValid] = useState(false);
  const [refStatus, setRefStatus] = useState<"idle" | "valid" | "invalid">("idle");
  const [offer, setOffer] = useState<Offer | null>(null);
  const [soloEnabled, setSoloEnabled] = useState(true);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isEn = lang === "en";
  const meta = TIER_META[selectedTier];
  const hasDiscount = refValid;
  const finalPrice = hasDiscount ? meta.discounted : meta.price;

  const handleToggleLang = () => {
    const nextLang = isEn ? "es" : "en";
    setLang(nextLang);
    if (typeof document !== "undefined") {
      document.cookie = `findaro_lang=${nextLang}; path=/; max-age=31536000`;
    }
  };

  const t = {
    title: isEn ? "Lifetime License" : "Licencia de por vida",
    sub: isEn
      ? "One-time payment forever. Free updates and all future features included."
      : "Un solo pago para siempre. Actualizaciones y nuevas funciones incluidas.",
    soloTier: "Personal",
    proTier: "Pro",
    familyTier: isEn ? "Family / Studio" : "Familiar / Studio",
    soloDesc: isEn ? "1 Mac lifetime" : "1 Mac de por vida",
    proDesc: isEn ? "2 Macs lifetime · desktop + MacBook" : "2 Macs de por vida · escritorio + MacBook",
    familyDesc: isEn ? "5 Macs lifetime" : "5 Macs de por vida",
    popular: isEn ? "Most Popular" : "Mejor Valor",
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
    emailPlaceholder: isEn ? "you@email.com" : "tu@email.com",
    refLabel: isEn ? "Referral / Promo code (optional)" : "Código de referido (opcional)",
    refPlaceholder: isEn ? "e.g. DAVE-8F12" : "Ej. DAVE-8F12",
    payButton: (price: number, seats: number) =>
      isEn
        ? `Pay $${price} USD with Stripe (${seats} Mac${seats === 1 ? "" : "s"})`
        : `Pagar $${price} USD con Stripe (${seats} Mac${seats === 1 ? "" : "s"})`,
    busyButton: isEn ? "Redirecting to Stripe…" : "Redirigiendo a Stripe…",
    securityNote: isEn
      ? "🛡️ 100% secure payment with Stripe. No subscriptions or hidden fees. Referral program: share your link to give friends a discount on their purchase."
      : "🛡️ Pago 100% seguro con Stripe. Sin suscripciones ni cobros ocultos. ¿Tienes amigos? Al comprar recibirás tu enlace de recomendación para compartir un descuento directo.",
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
      .then((j) => {
        if (j.ok) {
          setOffer(j.data);
          if (typeof j.data?.soloEnabled === "boolean") {
            setSoloEnabled(j.data.soloEnabled);
            if (!j.data.soloEnabled && selectedTier === "solo") {
              setSelectedTier("personal");
            }
          }
        }
      })
      .catch(() => setOffer(null));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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

      const res = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name,
          email,
          tier: selectedTier,
          lang,
          referralCode: hasDiscount ? referralCode.trim() : undefined,
          utm_source: utmSource || cookieUtm.utm_source,
          utm_medium: utmMedium || cookieUtm.utm_medium,
          utm_campaign: utmCampaign || cookieUtm.utm_campaign,
          utm_content: utmContent || cookieUtm.utm_content,
        }),
      });
      const json = await res.json();
      if (!json.ok || !json.data?.url) {
        throw new Error(json.error || (isEn ? "Could not initiate checkout with Stripe" : "No se pudo iniciar el pago"));
      }
      window.location.href = json.data.url;
    } catch (err) {
      setError(err instanceof Error ? err.message : "Error");
      setBusy(false);
    }
  }

  const tierButton = (
    key: TierKey,
    title: string,
    desc: string,
    accent: string,
    badge?: string,
  ) => {
    const m = TIER_META[key];
    const selected = selectedTier === key;
    const price = hasDiscount && selected ? m.discounted : m.price;
    return (
      <button
        type="button"
        onClick={() => setSelectedTier(key)}
        style={{
          padding: "14px 12px",
          borderRadius: "10px",
          border: selected ? `2px solid ${accent}` : "1px solid #334155",
          background: selected ? `${accent}22` : "rgba(15, 23, 42, 0.6)",
          color: "#fff",
          cursor: "pointer",
          textAlign: "left",
          position: "relative",
        }}
      >
        {badge ? (
          <div
            style={{
              position: "absolute",
              top: -10,
              right: 10,
              background: accent,
              color: "#0b1220",
              fontSize: 10,
              fontWeight: 800,
              letterSpacing: "0.04em",
              textTransform: "uppercase",
              padding: "3px 8px",
              borderRadius: 999,
            }}
          >
            {badge}
          </div>
        ) : null}
        <div style={{ fontSize: "14px", fontWeight: "bold" }}>{title}</div>
        <div style={{ fontSize: "20px", fontWeight: 800, marginTop: "4px" }}>
          ${price}{" "}
          <span style={{ fontSize: "12px", fontWeight: "normal", color: "#94a3b8" }}>USD</span>
        </div>
        <div style={{ fontSize: "12px", color: "#94a3b8", marginTop: "4px" }}>{desc}</div>
      </button>
    );
  };

  return (
    <main className={styles.page}>
      <div className={styles.card} style={{ maxWidth: 640 }}>
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

        {offer && (
          <div style={{ fontSize: "13px", color: "#38bdf8", margin: "14px 0 6px", fontWeight: 500 }}>
            ⚡️{" "}
            {isEn
              ? `Lifetime ladder: $29 / $39 / $59 · ${offer.remaining} launch seats left`
              : `Escalera de por vida: $29 / $39 / $59 · quedan ${offer.remaining} cupos de lanzamiento`}
          </div>
        )}

        <div
          style={{
            display: "grid",
            gridTemplateColumns: soloEnabled ? "1fr 1fr 1fr" : "1fr 1fr",
            gap: "12px",
            margin: "28px 0 10px",
          }}
        >
          {soloEnabled
            ? tierButton("solo", t.soloTier, t.soloDesc, "#38bdf8")
            : null}
          {tierButton("personal", t.proTier, t.proDesc, "#38bdf8", t.popular)}
          {tierButton("family", t.familyTier, t.familyDesc, "#a855f7")}
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
            {t.refValidMsg(referralCode, meta.discount)}
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
            {busy ? t.busyButton : t.payButton(finalPrice, meta.seats)}
          </button>
        </form>

        <p className={styles.note}>{t.securityNote}</p>

        <footer
          style={{
            marginTop: 24,
            paddingTop: 16,
            borderTop: "1px solid #1e293b",
            textAlign: "center",
            fontSize: 12,
            color: "#64748b",
          }}
        >
          <div>{t.footerNote}</div>
          <div style={{ marginTop: 6, display: "flex", justifyContent: "center", gap: 12, flexWrap: "wrap" }}>
            <Link href={`/terminos?lang=${lang}`} style={{ color: "#94a3b8", textDecoration: "underline" }}>
              {t.terms}
            </Link>
            <span>·</span>
            <Link href={`/privacidad?lang=${lang}`} style={{ color: "#94a3b8", textDecoration: "underline" }}>
              {t.privacy}
            </Link>
            <span>·</span>
            <Link href={`/reembolso?lang=${lang}`} style={{ color: "#94a3b8", textDecoration: "underline" }}>
              {t.refund}
            </Link>
            <span>·</span>
            <a
              href={isEn ? "mailto:support@findaro.iareal.net" : "mailto:soporte@findaro.iareal.net"}
              style={{ color: "#94a3b8", textDecoration: "underline" }}
            >
              {t.contact}
            </a>
          </div>
        </footer>
      </div>
    </main>
  );
}

export default function ComprarPage() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <ComprarInner />
    </Suspense>
  );
}
