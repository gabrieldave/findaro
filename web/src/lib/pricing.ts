import { query } from "./db";

export type LicenseTier = "personal" | "family";

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
};

export const TIERS: Record<LicenseTier, TierInfo> = {
  personal: {
    tier: "personal",
    name: "Plan Personal",
    nameEn: "Personal Plan",
    seats: 2,
    priceUsd: 39,
    discountedUsd: 35,
    referralDiscountUsd: 4,
    description: "2 Macs incluidas · De por vida · Actualizaciones automáticas",
    descriptionEn: "2 Macs included · Lifetime license · Automatic updates",
  },
  family: {
    tier: "family",
    name: "Plan Familiar",
    nameEn: "Family Plan",
    seats: 5,
    priceUsd: 59,
    discountedUsd: 53,
    referralDiscountUsd: 6,
    description: "5 Macs incluidas · De por vida · Soporte prioritario",
    descriptionEn: "5 Macs included · Lifetime license · Priority support",
  },
};

export function referralDiscountForTier(tier: LicenseTier): number {
  return TIERS[tier]?.referralDiscountUsd ?? 4;
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
    const defaultEn = "Launch special · $39 lifetime (2 Macs included)";
    const defaultEs = "Lanzamiento · $39 de por vida (2 Macs incluidas)";
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

  // Durante la promo: Personal = promo ($39), Familiar = regular ($59).
  // Cuando se agota la promo: Personal sube a regular ($59) y Familiar mantiene diferencial (+$20 = $79).
  const basePrice = isPromo
    ? tier === "family"
      ? regular
      : promo
    : tier === "family"
      ? regular + 20
      : regular;

  const labelEn = isPromo
    ? `Launch price: $${basePrice} USD (${TIERS[tier].seats} Macs)`
    : `Lifetime License: $${basePrice} USD (${TIERS[tier].seats} Macs)`;
  const labelEs = isPromo
    ? `Precio de lanzamiento: $${basePrice} USD (${TIERS[tier].seats} Macs)`
    : `Licencia de por vida: $${basePrice} USD (${TIERS[tier].seats} Macs)`;

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
