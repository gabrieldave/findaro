"use client";

import { FormEvent, Suspense, useEffect, useState } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { funnel } from "@/config/funnel";
import { readClientLang, writeClientLang, type Lang } from "@/lib/lang";
import styles from "../light.module.css";
import ui from "./comprar.module.css";

type TierKey = "solo" | "personal" | "family";

const REFERRAL_DISCOUNT: Record<TierKey, number> = { solo: 3, personal: 4, family: 6 };

/** Precios fijos desde src/config/funnel.ts (misma fuente que la landing y que lib/pricing.ts). */
const TIER_META = Object.fromEntries(
  funnel.pricing.tiers.map((tier) => [
    tier.checkoutTier,
    {
      seats: tier.seats,
      price: tier.price,
      compareAt: tier.compareAt as number | null,
      discount: REFERRAL_DISCOUNT[tier.checkoutTier],
      discounted: Math.max(1, tier.price - REFERRAL_DISCOUNT[tier.checkoutTier]),
    },
  ]),
) as Record<TierKey, { seats: number; price: number; compareAt: number | null; discount: number; discounted: number }>;

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

  const [lang, setLang] = useState<Lang>(() => {
    if (paramLang === "en" || paramLang === "es") return paramLang;
    return readClientLang() ?? "en";
  });

  // Pro ($39) por defecto: escalón de mejor valor. La landing puede preseleccionar con ?tier=.
  const [selectedTier, setSelectedTier] = useState<TierKey>(() => tierFromParam(paramTier));
  const [referralCode, setReferralCode] = useState(urlRef);
  const [refValid, setRefValid] = useState(false);
  const [refStatus, setRefStatus] = useState<"idle" | "valid" | "invalid">("idle");
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
    const nextLang: Lang = isEn ? "es" : "en";
    setLang(nextLang);
    writeClientLang(nextLang);
  };

  const t = {
    title: isEn ? "Lifetime License" : "Licencia de por vida",
    sub: isEn
      ? "Pay once, keep it forever. Free updates and all future features included. No subscription, no tokens, no cloud."
      : "Pagas una vez y es tuya para siempre. Actualizaciones y nuevas funciones incluidas. Sin suscripción, sin tokens, sin nube.",
    soloTier: "Solo",
    proTier: isEn ? "Pro · Desktop + MacBook" : "Pro · Escritorio + MacBook",
    familyTier: "Family",
    soloDesc: isEn ? "1 Mac lifetime" : "1 Mac de por vida",
    proDesc: isEn ? "2 Macs lifetime" : "2 Macs de por vida",
    familyDesc: isEn ? "5 Macs · priority support" : "5 Macs · soporte prioritario",
    perMac: (v: string) => (isEn ? `${v} per Mac` : `${v} por Mac`),
    popular: isEn ? "Recommended" : "Recomendado",
    launch: isEn
      ? `Founder launch price: Pro $${TIER_META.personal.price} (was $${TIER_META.personal.compareAt}) · Family $${TIER_META.family.price} (was $${TIER_META.family.compareAt})`
      : `Precio de fundador: Pro $${TIER_META.personal.price} (antes $${TIER_META.personal.compareAt}) · Family $${TIER_META.family.price} (antes $${TIER_META.family.compareAt})`,
    tiersLabel: isEn ? "Choose your license" : "Elige tu licencia",
    anchor: isEn ? (
      <>
        A yearly subscription like Path Finder: <s>~${funnel.savings.pathFinderYearMin}–{funnel.savings.pathFinderYearMax}/year</s> → <b>~${funnel.savings.pathFinderYearMin * 3}–{funnel.savings.pathFinderYearMax * 3} over 3 years</b>. Findaro Pro: <b>${funnel.savings.findaroPro} once</b>, for 2 Macs.
      </>
    ) : (
      <>
        Una suscripción anual como Path Finder: <s>~${funnel.savings.pathFinderYearMin}–{funnel.savings.pathFinderYearMax}/año</s> → <b>~${funnel.savings.pathFinderYearMin * 3}–{funnel.savings.pathFinderYearMax * 3} en 3 años</b>. Findaro Pro: <b>${funnel.savings.findaroPro} una vez</b>, para 2 Macs.
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
      ? "Secure payment with Stripe. No subscription, no hidden fees. After you buy, you get a referral link that gives your friends a discount."
      : "Pago seguro con Stripe. Sin suscripción ni cobros ocultos. Al comprar recibes un enlace de recomendación que les da un descuento a tus amigos.",
    terms: isEn ? "Terms of Service" : "Términos de Servicio",
    privacy: isEn ? "Privacy" : "Privacidad",
    refund: isEn ? "Refund Policy" : "Política de Reembolso",
    contact: isEn ? "Contact" : "Contacto",
    support: isEn ? "Support" : "Soporte",
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
          if (typeof j.data?.soloEnabled === "boolean") {
            setSoloEnabled(j.data.soloEnabled);
            if (!j.data.soloEnabled && selectedTier === "solo") {
              setSelectedTier("personal");
            }
          }
        }
      })
      .catch(() => undefined);
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
          {discounted ? <s>${m.price}</s> : m.compareAt ? <s>${m.compareAt}</s> : null}${price}
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
        <div className={styles.top}>
          <Link className={styles.brand} href={isEn ? "/" : "/es"}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo-mark.png" alt="" width={28} height={28} />
            Findaro
          </Link>
          <button type="button" onClick={handleToggleLang} className={styles.langBtn} lang={isEn ? "es" : "en"}>
            {isEn ? "ES" : "EN"}
          </button>
        </div>

        <h1 className={ui.title}>{t.title}</h1>
        <p className={styles.sub}>{t.sub}</p>

        <p className={ui.ladder}>{t.launch}</p>

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
          <Link href={`/soporte?lang=${lang}`}>{t.support}</Link>
          <span>·</span>
          <a href={isEn ? "mailto:support@findaro.iareal.net" : "mailto:soporte@findaro.iareal.net"}>{t.contact}</a>
        </footer>
      </div>
    </main>
  );
}

export default function ComprarClient() {
  return (
    <Suspense fallback={<main className={styles.page} />}>
      <ComprarInner />
    </Suspense>
  );
}
