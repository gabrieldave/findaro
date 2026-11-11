import { query } from "./db";

/**
 * Escalera comercial FINDARO (pago único):
 * - solo     → UI "Personal" · 1 Mac · $29
 * - personal → UI "Pro"      · 2 Macs · $39  (tier histórico en BD; no renombrar)
 * - family   → UI "Familiar" · 5 Macs · $59
 *
 * Los importes se pueden sobreescribir por entorno sin romper el build
 * si falta alguna variable (fallback a los defaults).
 */
export type LicenseTier = "solo" | "personal" | "family";

export type TierInfo = {
  tier: LicenseTier;
  name: string;
  nameEn: string;
  seats: number;
  priceUsd: number;
  discountedUsd: number;
  referralDiscountUsd: number;
  description: string;
  descriptionEn: string;
  badgeEs?: string;
  badgeEn?: string;
};

function envUsd(key: string, fallback: number): number {
  const raw = process.env[key];
  if (raw == null || raw.trim() === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

const SOLO_PRICE = envUsd("FINDARO_PRICE_SOLO_USD", envUsd("STRIPE_PRICE_PERSONAL_USD", 29));
const PRO_PRICE = envUsd("FINDARO_PRICE_PRO_USD", 39);
const FAMILY_PRICE = envUsd("FINDARO_PRICE_FAMILY_USD", 59);

/** Si es "0"/"false", el tier Personal ($29) no se ofrece en checkout (los otros siguen). */
export function isSoloTierEnabled(): boolean {
  const flag = (process.env.FINDARO_ENABLE_SOLO_TIER || "1").trim().toLowerCase();
  if (flag === "0" || flag === "false" || flag === "off") return false;
  // Enlace/Price ID opcional: si se define vacío explícitamente vía DISABLE, ya cubierto arriba.
  // STRIPE_PRICE_PERSONAL / STRIPE_LINK_PERSONAL son opcionales (n8n usa price_data dinámico).
  return true;
}

export const TIERS: Record<LicenseTier, TierInfo> = {
  solo: {
    tier: "solo",
    name: "Personal",
    nameEn: "Personal",
    seats: 1,
    priceUsd: SOLO_PRICE,
    discountedUsd: Math.max(1, SOLO_PRICE - 3),
    referralDiscountUsd: 3,
    description: "1 Mac · De por vida · Actualizaciones automáticas",
    descriptionEn: "1 Mac · Lifetime license · Automatic updates",
  },
  personal: {
    tier: "personal",
    name: "Pro",
    nameEn: "Pro",
    seats: 2,
    priceUsd: PRO_PRICE,
    discountedUsd: Math.max(1, PRO_PRICE - 4),
    referralDiscountUsd: 4,
    description: "2 Macs · De por vida · Ideal escritorio + MacBook",
    descriptionEn: "2 Macs · Lifetime · Ideal for desktop + MacBook",
    badgeEs: "Mejor Valor",
    badgeEn: "Most Popular",
  },
  family: {
    tier: "family",
    name: "Familiar / Studio",
    nameEn: "Family / Studio",
    seats: 5,
    priceUsd: FAMILY_PRICE,
    discountedUsd: Math.max(1, FAMILY_PRICE - 6),
    referralDiscountUsd: 6,
    description: "5 Macs · De por vida · Soporte prioritario",
    descriptionEn: "5 Macs · Lifetime license · Priority support",
  },
};

export function parseLicenseTier(raw: unknown): LicenseTier {
  if (raw === "solo" && isSoloTierEnabled()) return "solo";
  if (raw === "family") return "family";
  return "personal";
}

export function referralDiscountForTier(tier: LicenseTier): number {
  return TIERS[tier]?.referralDiscountUsd ?? 4;
}

/** Importes permitidos por tier (base + referido + post-promo) para validación n8n/servidor. */
export function allowedAmountsForTier(tier: LicenseTier): number[] {
  const info = TIERS[tier];
  const base = info.priceUsd;
  const withRef = Math.max(1, base - info.referralDiscountUsd);
  if (tier === "solo") {
    return Array.from(new Set([base, withRef]));
  }
  if (tier === "family") {
    // Promo vigente: 59/53; post-promo: 79/73 (regular+20 ± referido)
    return Array.from(new Set([base, withRef, base + 20, withRef + 20]));
  }
  // personal/Pro: promo 39/35; post-promo sube a regular histórico 59/55
  return Array.from(new Set([base, withRef, 59, 55]));
}

export type PromoOffer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  soldCount: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
  labelEn: string;
  labelEs: string;
  tiers: Record<LicenseTier, TierInfo>;
};

export async function currentOffer(tier: LicenseTier = "personal"): Promise<PromoOffer> {
  const { rows } = await query<{
    sold_count: number;
    promo_limit: number;
    promo_price: string;
    regular_price: string;
  }>("SELECT sold_count, promo_limit, promo_price, regular_price FROM promo_state WHERE id = 1");
  const row = rows[0];
  if (!row) {
    const defaultEn = `Lifetime from $${TIERS.solo.priceUsd} · Pro $${TIERS.personal.priceUsd} (2 Macs) · Family $${TIERS.family.priceUsd}`;
    const defaultEs = `Desde $${TIERS.solo.priceUsd} · Pro $${TIERS.personal.priceUsd} (2 Macs) · Familiar $${TIERS.family.priceUsd}`;
    return {
      amountUsd: TIERS[tier].priceUsd,
      isPromo: true,
      remaining: 1000,
      soldCount: 0,
      promoLimit: 1000,
      regularPrice: 59,
      label: defaultEn,
      labelEn: defaultEn,
      labelEs: defaultEs,
      tiers: TIERS,
    };
  }
  const sold = Number(row.sold_count);
  const limit = Number(row.promo_limit);
  const promo = Number(row.promo_price);
  const regular = Number(row.regular_price);
  const isPromo = sold < limit;
  const remaining = Math.max(0, limit - sold);

  // Solo siempre a su precio de entrada.
  // Pro (personal): durante promo usa promo_price ($39); al agotarse sube a regular ($59).
  // Familiar: durante promo = regular ($59); post-promo = regular+20 ($79).
  let basePrice: number;
  if (tier === "solo") {
    basePrice = TIERS.solo.priceUsd;
  } else if (isPromo) {
    basePrice = tier === "family" ? regular : promo;
  } else {
    basePrice = tier === "family" ? regular + 20 : regular;
  }

  const labelEn = isPromo
    ? `Launch price: $${basePrice} USD (${TIERS[tier].seats} Mac${TIERS[tier].seats === 1 ? "" : "s"})`
    : `Lifetime License: $${basePrice} USD (${TIERS[tier].seats} Mac${TIERS[tier].seats === 1 ? "" : "s"})`;
  const labelEs = isPromo
    ? `Precio de lanzamiento: $${basePrice} USD (${TIERS[tier].seats} Mac${TIERS[tier].seats === 1 ? "" : "s"})`
    : `Licencia de por vida: $${basePrice} USD (${TIERS[tier].seats} Mac${TIERS[tier].seats === 1 ? "" : "s"})`;

  return {
    amountUsd: basePrice,
    isPromo,
    remaining,
    soldCount: sold,
    promoLimit: limit,
    regularPrice: regular,
    label: labelEn,
    labelEn,
    labelEs,
    tiers: TIERS,
  };
}

/** Reserva un cupo promo de forma atómica al marcar paid. */
export async function incrementPromoIfEligible(): Promise<boolean> {
  const { rows } = await query<{ sold_count: number }>(
    `UPDATE promo_state
     SET sold_count = sold_count + 1, updated_at = now()
     WHERE id = 1 AND sold_count < promo_limit
     RETURNING sold_count`,
  );
  return rows.length > 0;
}
