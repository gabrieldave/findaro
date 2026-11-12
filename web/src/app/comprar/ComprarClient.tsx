"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import styles from "../marketing.module.css";
import ui from "./comprar.module.css";

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

/** Acepta ?tier=solo|personal|pro|family desde la landing. "pro" es alias UI de "personal". */
function tierFromParam(raw: string | null): TierKey {
  const v = (raw || "").trim().toLowerCase();
  if (v === "solo") return "solo";
  if (v === "family" || v === "familiar" || v === "studio") return "family";
  return "personal";
}

function formatPerMac(total: number, seats: number, isEn: boolean): string {
  const per = total / seats;
  const fixed = Number.isInteger(per) ? String(per) : per.toFixed(2);
  return isEn ? `$${fixed}` : `$${fixed.replace(".", ",")}`;
}

function ComprarInner() {
  const searchParams = useSearchParams();
  const urlRef = searchParams.get("ref") || "";
  const paramLang = searchParams.get("lang");
  const paramTier = searchParams.get("tier");

  const [lang, setLang] = useState<"es" | "en">(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    if (typeof document !== "undefined") {
      const match = document.cookie.match(/findaro_lang=(en|es)/);
      if (match) return match[1] as "es" | "en";
    }
    return "en";
  });

  // Pro ($39) por defecto: escalón de mejor valor. La landing puede preseleccionar con ?tier=.
  const [selectedTier, setSelectedTier] = useState<TierKey>(() => tierFromParam(paramTier));
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
      ? "Pay once, keep it forever. Free updates and all future features included. No subscription, no tokens, no cloud."
      : "Pagas una vez y es tuya para siempre. Actualizaciones y nuevas funciones incluidas. Sin suscripción, sin tokens, sin nube.",
    soloTier: "Personal",
    proTier: isEn ? "Pro · Desktop + MacBook" : "Pro · Escritorio + MacBook",
    familyTier: isEn ? "Family / Studio" : "Familiar / Studio",
    soloDesc: isEn ? "1 Mac lifetime" : "1 Mac de por vida",
    proDesc: isEn ? "2 Macs lifetime" : "2 Macs de por vida",
    familyDesc: isEn ? "5 Macs · priority support" : "5 Macs · soporte prioritario",
    perMac: (v: string) => (isEn ? `${v} per Mac` : `${v} por Mac`),
    popular: isEn ? "The smart buy" : "La compra inteligente",
    tiersLabel: isEn ? "Choose your license" : "Elige tu licencia",
    anchor: isEn ? (
      <>
        A subscription like Path Finder: <s>$32/year</s> → <b>$96 over 3 years</b>. FINDARO Pro: <b>$39 once</b>, for 2 Macs.
      </>
    ) : (
      <>
        Una suscripción como Path Finder: <s>$32/año</s> → <b>$96 en 3 años</b>. FINDARO Pro: <b>$39 una vez</b>, para 2 Macs.
      </>
    ),
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
    emailLabel: isEn ? "Email (your license key arrives here)" : "Correo (aquí llega tu clave de licencia)",
    emailPlaceholder: isEn ? "you@email.com" : "tu@email.com",
    refLabel: isEn ? "Referral / Promo code (optional)" : "Código de referido (opcional)",
    refPlaceholder: isEn ? "e.g. DAVE-8F12" : "Ej. DAVE-8F12",
    payButton: (price: number, seats: number) =>
      isEn
        ? `Pay $${price} USD once with Stripe (${seats} Mac${seats === 1 ? "" : "s"})`
        : `Pagar $${price} USD una vez con Stripe (${seats} Mac${seats === 1 ? "" : "s"})`,
    busyButton: isEn ? "Redirecting to Stripe…" : "Redirigiendo a Stripe…",
    seal: isEn
      ? ["✓ 14-Day Free Trial (No Card)", "✓ 14-Day Money-Back Guarantee", "✓ One-time payment"]
      : ["✓ 14 días gratis sin tarjeta", "✓ Reembolso 14 días sin preguntas", "✓ Pago único"],
    securityNote: isEn
      ? "🛡️ 100% secure payment with Stripe. No subscriptions or hidden fees. After purchase you get a referral link to give friends a discount."
      : "🛡️ Pago 100% seguro con Stripe. Sin suscripciones ni cobros ocultos. Al comprar recibirás tu enlace de recomendación para compartir un descuento.",
    terms: isEn ? "Terms of Service" : "Términos de Servicio",
    privacy: isEn ? "Privacy" : "Privacidad",
    refund: isEn ? "Refund Policy" : "Política de Reembolso",
    contact: isEn ? "Contact" : "Contacto",
  };

  useEffect(() => {
    if (urlRef) {
      setReferralCode(urlRef);
      return;
    }
    if (typeof document === "undefined") return;
    const match = document.cookie.match(/(?:^|; )findaro_ref=([^;]*)/);
    if (match?.[1]) {
      try {
        setReferralCode(decodeURIComponent(match[1]).toUpperCase());
      } catch {
        setReferralCode(match[1].toUpperCase());
      }
    }
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

  const tierButton = (key: TierKey, title: string, desc: string, extraClass: string, badge?: string) => {
    const m = TIER_META[key];
    const selected = selectedTier === key;
    const discounted = hasDiscount && selected;
    const price = discounted ? m.discounted : m.price;
    const className = [ui.tier, extraClass, selected ? ui.tierSelected : ""].filter(Boolean).join(" ");
    return (
      <button
        key={key}
        type="button"
        role="radio"
        aria-checked={selected}
        onClick={() => setSelectedTier(key)}
        className={className}
      >
        {badge ? <span className={ui.badge}>{badge}</span> : null}
        <span className={ui.tierName}>{title}</span>
        <span className={ui.tierPrice}>
          {discounted ? <s>${m.price}</s> : null}${price}
          <small>USD</small>
        </span>
        <span className={ui.tierDesc}>{desc}</span>
        {m.seats > 1 ? <span className={ui.tierPer}>{t.perMac(formatPerMac(price, m.seats, isEn))}</span> : null}
      </button>
    );
  };

  return (
    <main className={styles.page}>
      <div className={`${styles.card} ${ui.card}`}>
        <div className={ui.header}>
          <p className={styles.brand} style={{ margin: 0 }}>FINDARO</p>
          <button type="button" onClick={handleToggleLang} className={ui.langBtn}>
            🌐 {isEn ? "Español" : "English"}
          </button>
        </div>

        <h1 className={ui.title}>{t.title}</h1>
        <p className={styles.sub}>{t.sub}</p>

        {offer && (
          <p className={ui.ladder}>
            ⚡️{" "}
            {isEn
              ? `Lifetime ladder: $29 / $39 / $59 · ${offer.remaining} launch seats left`
              : `Escalera de por vida: $29 / $39 / $59 · quedan ${offer.remaining} cupos de lanzamiento`}
          </p>
        )}

        <div
          role="radiogroup"
          aria-label={t.tiersLabel}
          className={soloEnabled ? ui.tiers : `${ui.tiers} ${ui.tiersTwo}`}
        >
          {soloEnabled ? tierButton("solo", t.soloTier, t.soloDesc, "") : null}
          {tierButton("personal", t.proTier, t.proDesc, ui.tierPro, t.popular)}
          {tierButton("family", t.familyTier, t.familyDesc, ui.tierFamily)}
        </div>

        {selectedTier === "personal" && <p className={ui.anchor}>{t.anchor}</p>}

        {refStatus === "valid" && <div className={ui.alertOk}>{t.refValidMsg(referralCode, meta.discount)}</div>}

        {refStatus === "invalid" && <div className={ui.alertErr}>{t.refInvalidMsg(referralCode)}</div>}

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
              inputMode="email"
            />
          </label>
          <label>
            {t.refLabel}
            <input
              value={referralCode}
              onChange={(e) => setReferralCode(e.target.value.toUpperCase())}
              placeholder={t.refPlaceholder}
              autoCapitalize="characters"
            />
          </label>

          {error && <p className={styles.error}>{error}</p>}

          <button type="submit" disabled={busy} className={styles.cta}>
            {busy ? t.busyButton : t.payButton(finalPrice, meta.seats)}
          </button>
        </form>

        <ul className={ui.seal} aria-label={isEn ? "Guarantees" : "Garantías"}>
          {t.seal.map((s) => (
            <li key={s}>{s}</li>
          ))}
        </ul>

        <p className={styles.note}>{t.securityNote}</p>

        <footer className={ui.footer}>
          <Link href={`/terminos?lang=${lang}`}>{t.terms}</Link>
          <span>·</span>
          <Link href={`/privacidad?lang=${lang}`}>{t.privacy}</Link>
          <span>·</span>
          <Link href={`/reembolso?lang=${lang}`}>{t.refund}</Link>
          <span>·</span>
          <a href={isEn ? "mailto:support@findaro.iareal.net" : "mailto:soporte@findaro.iareal.net"}>{t.contact}</a>
        </footer>
      </div>
    </main>
  );
}

export default function ComprarClient() {
  return (
    <Suspense fallback={<main className={styles.page}><p>Loading…</p></main>}>
      <ComprarInner />
    </Suspense>
  );
}
