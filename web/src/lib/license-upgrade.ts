import type { LicenseTier } from "./pricing";

/** Jerarquía de planes Pro: mayor número = mayor plan. */
export const PRO_TIER_RANK: Record<LicenseTier, number> = {
  solo: 1,
  personal: 2,
  family: 3,
};

/** Recompra / upgrade: suma asientos y conserva el tier de mayor jerarquía. */
export function resolveProUpgrade(
  existing: { seats: number; tier: LicenseTier },
  purchased: { seats: number; tier: LicenseTier },
): { updatedSeats: number; upgradedTier: LicenseTier } {
  const existingRank = PRO_TIER_RANK[existing.tier] ?? 0;
  const purchasedRank = PRO_TIER_RANK[purchased.tier] ?? 0;
  const upgradedTier = purchasedRank >= existingRank ? purchased.tier : existing.tier;
  const updatedSeats = existing.seats + purchased.seats;
  return { updatedSeats, upgradedTier };
}
