import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { mintReferralCode } from "@/lib/license";
import { createCheckoutSession } from "@/lib/payment";
import { currentOffer, LicenseTier, TIERS } from "@/lib/pricing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
    tier?: LicenseTier;
    referralCode?: string;
  } | null;

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim();
  const tier: LicenseTier = body?.tier === "family" ? "family" : "personal";
  const refCode = (body?.referralCode || "").trim().toUpperCase();

  if (!email || !email.includes("@")) return fail("Correo inválido", 400);
  if (name.length < 2) return fail("Nombre requerido", 400);

  const tierInfo = TIERS[tier];
  let finalAmount = tierInfo.priceUsd;
  let hasValidReferral = false;

  // Si hay código de referido, validar y aplicar descuento de $4 USD ($35 en Personal, $53 en Family)
  if (refCode) {
    const refCheck = await query<{ id: string; email: string }>(
      `SELECT id, email FROM customers WHERE UPPER(referral_code) = $1 LIMIT 1`,
      [refCode],
    );
    if (refCheck.rows[0] && refCheck.rows[0].email !== email) {
      hasValidReferral = true;
      finalAmount = tierInfo.discountedUsd;
    }
  }

  // Asignar o mantener código de referido único para este cliente
  const generatedRef = mintReferralCode(name);
  const customer = await query<{ id: string; referral_code: string }>(
    `INSERT INTO customers (email, name, referral_code)
     VALUES ($1, $2, $3)
     ON CONFLICT (email) DO UPDATE 
       SET name = EXCLUDED.name, 
           referral_code = COALESCE(customers.referral_code, EXCLUDED.referral_code),
           updated_at = now()
     RETURNING id, referral_code`,
    [email, name, generatedRef],
  );
  const customerId = customer.rows[0]?.id;
  if (!customerId) return fail("No se pudo registrar el cliente", 500);

  const offer = await currentOffer(tier);

  const order = await query<{ id: string }>(
    `INSERT INTO orders (customer_id, amount_usd, currency, status, promo_slot, tier, referral_code)
     VALUES ($1, $2, 'usd', 'pending', $3, $4, $5)
     RETURNING id`,
    [customerId, finalAmount, offer.isPromo, tier, hasValidReferral ? refCode : null],
  );
  const orderId = order.rows[0]?.id;
  if (!orderId) return fail("No se pudo crear la orden", 500);

  const session = await createCheckoutSession({
    amountUsd: finalAmount,
    customerEmail: email,
    customerName: name,
    orderId,
    isPromo: offer.isPromo,
    tier,
  });

  await query(`UPDATE orders SET stripe_session_id = $1 WHERE id = $2`, [
    session.sessionId,
    orderId,
  ]);

  return ok({
    url: session.url,
    sessionId: session.sessionId,
    amountUsd: finalAmount,
    tier,
    isPromo: offer.isPromo,
    discountApplied: hasValidReferral ? 4 : 0,
  });
});
