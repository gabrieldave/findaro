import { resolveProUpgrade } from "./license-upgrade";

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

// Upgrade solo(1) + personal(2) → personal, seats 1+2=3
{
  const r = resolveProUpgrade(
    { seats: 1, tier: "solo" },
    { seats: 2, tier: "personal" },
  );
  assert(r.upgradedTier === "personal", `tier want personal got ${r.upgradedTier}`);
  assert(r.updatedSeats === 3, `seats want 3 got ${r.updatedSeats}`);
}

// Same-tier repurchase personal + personal → personal, seats sum
{
  const r = resolveProUpgrade(
    { seats: 2, tier: "personal" },
    { seats: 2, tier: "personal" },
  );
  assert(r.upgradedTier === "personal", "same tier kept");
  assert(r.updatedSeats === 4, `seats want 4 got ${r.updatedSeats}`);
}

// Buying lower tier still keeps higher + sums seats
{
  const r = resolveProUpgrade(
    { seats: 5, tier: "family" },
    { seats: 1, tier: "solo" },
  );
  assert(r.upgradedTier === "family", "family wins");
  assert(r.updatedSeats === 6, `seats want 6 got ${r.updatedSeats}`);
}

console.log("license-upgrade.test.ts: OK");
