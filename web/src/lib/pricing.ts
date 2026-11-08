import { query } from "./db";

export type PromoOffer = {
  amountUsd: number;
  isPromo: boolean;
  remaining: number;
  soldCount: number;
  promoLimit: number;
  regularPrice: number;
  label: string;
};

export async function currentOffer(): Promise<PromoOffer> {
  const { rows } = await query<{
    sold_count: number;
    promo_limit: number;
    promo_price: string;
    regular_price: string;
  }>("SELECT sold_count, promo_limit, promo_price, regular_price FROM promo_state WHERE id = 1");
  const row = rows[0];
  if (!row) {
    return {
      amountUsd: 59,
      isPromo: true,
      remaining: 1000,
      soldCount: 0,
      promoLimit: 1000,
      regularPrice: 99,
      label: "Lanzamiento · $59 de por vida",
    };
  }
  const sold = Number(row.sold_count);
  const limit = Number(row.promo_limit);
  const promo = Number(row.promo_price);
  const regular = Number(row.regular_price);
  const isPromo = sold < limit;
  const remaining = Math.max(0, limit - sold);
  return {
    amountUsd: isPromo ? promo : regular,
    isPromo,
    remaining,
    soldCount: sold,
    promoLimit: limit,
    regularPrice: regular,
    label: isPromo
      ? `Primeros ${limit}: $${promo} de por vida · quedan ${remaining}`
      : `Licencia de por vida · $${regular}`,
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
