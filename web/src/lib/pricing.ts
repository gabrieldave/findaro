import { query } from "./db";

export type LicenseTier = "personal" | "family";

export type TierInfo = {
  tier: LicenseTier;
  name: string;
  seats: number;
  priceUsd: number;
  discountedUsd: number;
  description: string;
};

export const TIERS: Record<LicenseTier, TierInfo> = {
  personal: {
    tier: "personal",
    name: "Plan Personal",
    seats: 2,
    priceUsd: 39,
    discountedUsd: 35,
    description: "2 Macs incluidas · De por vida · Actualizaciones automáticas",
  },
  family: {
    tier: "family",
    name: "Plan Familiar",
    seats: 5,
    priceUsd: 59,
    discountedUsd: 53,
    description: "5 Macs incluidas · De por vida · Soporte prioritario",
  },
};

export type PromoOffer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  soldCount: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
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
    return {
      amountUsd: TIERS[tier].priceUsd,
      isPromo: true,
      remaining: 1000,
      soldCount: 0,
      promoLimit: 1000,
      regularPrice: 59,
      label: "Lanzamiento · $39 de por vida (2 Macs)",
      tiers: TIERS,
    };
  }
  const sold = Number(row.sold_count);
  const limit = Number(row.promo_limit);
  const promo = Number(row.promo_price);
  const regular = Number(row.regular_price);
  const isPromo = sold < limit;
  const remaining = Math.max(0, limit - sold);

  const basePrice = tier === "family" ? regular : promo;

  return {
    amountUsd: basePrice,
    isPromo,
    remaining,
    soldCount: sold,
    promoLimit: limit,
    regularPrice: regular,
    label: isPromo
      ? `Lanzamiento: $${basePrice} USD (${TIERS[tier].seats} Macs) · quedan ${remaining} cupos`
      : `Licencia de por vida: $${basePrice} USD (${TIERS[tier].seats} Macs)`,
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
