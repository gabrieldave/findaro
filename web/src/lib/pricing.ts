import { funnel } from "@/config/funnel";
import { query } from "./db";

/**
 * Escalera comercial FINDARO (pago único de por vida, precios FIJOS):
 * - solo     → UI "Solo"   · 1 Mac  · $29
 * - personal → UI "Pro"    · 2 Macs · $39  (tier histórico en BD; no renombrar) · antes $59
 * - family   → UI "Family" · 5 Macs · $59  · antes $79
 *
 * Los defaults salen de src/config/funnel.ts (misma fuente que la landing).
 * Se pueden sobreescribir por entorno, pero el precio YA NO sube solo por conteo
 * de ventas: lo que ve el cliente es lo que cobra Stripe.
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
  /** Precio regular tachado (Founder Launch Price). null = sin tachado. */
  compareAtUsd: number | null;
};

function envUsd(key: string, fallback: number): number {
  const raw = process.env[key];
  if (raw == null || raw.trim() === "") return fallback;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

const FUNNEL_TIER = Object.fromEntries(funnel.pricing.tiers.map((t) => [t.checkoutTier, t])) as Record<
  LicenseTier,
  (typeof funnel.pricing.tiers)[number]
>;

const SOLO_PRICE = envUsd("FINDARO_PRICE_SOLO_USD", envUsd("STRIPE_PRICE_PERSONAL_USD", FUNNEL_TIER.solo.price));
const PRO_PRICE = envUsd("FINDARO_PRICE_PRO_USD", FUNNEL_TIER.personal.price);
const FAMILY_PRICE = envUsd("FINDARO_PRICE_FAMILY_USD", FUNNEL_TIER.family.price);

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
    name: "Solo",
    nameEn: "Solo",
    seats: 1,
    priceUsd: SOLO_PRICE,
    discountedUsd: Math.max(1, SOLO_PRICE - 3),
    referralDiscountUsd: 3,
    description: "1 Mac · De por vida · Actualizaciones automáticas",
    descriptionEn: "1 Mac · Lifetime license · Automatic updates",
    compareAtUsd: FUNNEL_TIER.solo.compareAt,
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
    badgeEs: "Recomendado",
    badgeEn: "Recommended",
    compareAtUsd: FUNNEL_TIER.personal.compareAt,
  },
  family: {
    tier: "family",
    name: "Family",
    nameEn: "Family",
    seats: 5,
    priceUsd: FAMILY_PRICE,
    discountedUsd: Math.max(1, FAMILY_PRICE - 6),
    referralDiscountUsd: 6,
    description: "5 Macs · De por vida · Soporte prioritario",
    descriptionEn: "5 Macs · Lifetime license · Priority support",
    compareAtUsd: FUNNEL_TIER.family.compareAt,
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

/** Importes permitidos por tier (base + referido) para validación n8n/servidor. Precios fijos. */
export function allowedAmountsForTier(tier: LicenseTier): number[] {
  const info = TIERS[tier];
  const base = info.priceUsd;
  const withRef = Math.max(1, base - info.referralDiscountUsd);
  return Array.from(new Set([base, withRef]));
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
  // Precio fijo por tier. promo_state solo se lee para estadísticas internas (soldCount);
  // ya no cambia el importe ni genera urgencia artificial en la web.
  let sold = 0;
  let limit = 0;
  try {
    const { rows } = await query<{ sold_count: number; promo_limit: number }>(
      "SELECT sold_count, promo_limit FROM promo_state WHERE id = 1",
    );
    if (rows[0]) {
      sold = Number(rows[0].sold_count) || 0;
      limit = Number(rows[0].promo_limit) || 0;
    }
  } catch {
    // Sin BD (build/preview): seguimos con los precios fijos.
  }
  const info = TIERS[tier];
  const basePrice = info.priceUsd;
  const compareAt = info.compareAtUsd;
  const seatsLabel = `${info.seats} Mac${info.seats === 1 ? "" : "s"}`;
  const labelEn = compareAt
    ? `Founder launch price: $${basePrice} USD (was $${compareAt}) · ${seatsLabel}`
    : `Lifetime license: $${basePrice} USD · ${seatsLabel}`;
  const labelEs = compareAt
    ? `Precio de fundador: $${basePrice} USD (antes $${compareAt}) · ${seatsLabel}`
    : `Licencia de por vida: $${basePrice} USD · ${seatsLabel}`;

  return {
    amountUsd: basePrice,
    isPromo: compareAt != null,
    remaining: Math.max(0, limit - sold),
    soldCount: sold,
    promoLimit: limit,
    regularPrice: compareAt ?? basePrice,
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
