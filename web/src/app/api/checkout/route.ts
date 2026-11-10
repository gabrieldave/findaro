import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { mintReferralCode } from "@/lib/license";
import { createCheckoutSession } from "@/lib/payment";
import { currentOffer, LicenseTier, referralDiscountForTier } from "@/lib/pricing";
import { limitByIp } from "@/lib/ratelimit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const limited = limitByIp(req, "checkout", 10, 60 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
    tier?: LicenseTier;
    lang?: string;
    referralCode?: string;
    utm_source?: string;
    utm_medium?: string;
    utm_campaign?: string;
    utm_content?: string;
  } | null;

  const cookieHeader = req.headers.get("cookie") || "";
  const cookieLangMatch = cookieHeader.match(/(?:^|;\s*)findaro_lang=(en|es)/);
  const lang = detectLanguageFromHeaders(req.headers, cookieLangMatch?.[1], body?.lang);

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim();
  const tier: LicenseTier = body?.tier === "family" ? "family" : "personal";
  const refCode = (body?.referralCode || "").trim().toUpperCase();
  const utmSource = (body?.utm_source || "").trim().slice(0, 128) || null;
  const utmMedium = (body?.utm_medium || "").trim().slice(0, 128) || null;
  const utmCampaign = (body?.utm_campaign || "").trim().slice(0, 128) || null;
  const utmContent = (body?.utm_content || "").trim().slice(0, 128) || null;

  if (!email || !email.includes("@")) {
    return fail(lang === "en" ? "Invalid email address" : "Correo inválido", 400);
  }
  if (name.length < 2) {
    return fail(lang === "en" ? "Name is required" : "Nombre requerido", 400);
  }

  const offer = await currentOffer(tier);
  let finalAmount = offer.amountUsd;
  let discountApplied = 0;
  let hasValidReferral = false;

  // Aplicar descuento dinámico ($4 USD en Personal, $6 USD en Familiar) sobre la oferta vigente
  if (refCode && refCode.length <= 32) {
    const refCheck = await query<{ id: string; email: string }>(
      `SELECT id, email FROM customers WHERE UPPER(referral_code) = $1 LIMIT 1`,
      [refCode],
    );
    if (refCheck.rows[0] && refCheck.rows[0].email !== email) {
      hasValidReferral = true;
      discountApplied = referralDiscountForTier(tier);
      finalAmount = Math.max(1, offer.amountUsd - discountApplied);
    }
  }

  const generatedRef = mintReferralCode(name);
  const customer = await query<{ id: string; referral_code: string }>(
    `INSERT INTO customers (email, name, referral_code, utm_source, utm_medium, utm_campaign, utm_content, first_seen_at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, now())
     ON CONFLICT (email) DO UPDATE
       SET name = EXCLUDED.name,
           referral_code = COALESCE(customers.referral_code, EXCLUDED.referral_code),
           utm_source = COALESCE(customers.utm_source, EXCLUDED.utm_source),
           utm_medium = COALESCE(customers.utm_medium, EXCLUDED.utm_medium),
           utm_campaign = COALESCE(customers.utm_campaign, EXCLUDED.utm_campaign),
           utm_content = COALESCE(customers.utm_content, EXCLUDED.utm_content),
           updated_at = now()
     RETURNING id, referral_code`,
    [email, name, generatedRef, utmSource, utmMedium, utmCampaign, utmContent],
  );
  const customerId = customer.rows[0]?.id;
  if (!customerId) return fail("No se pudo registrar el cliente", 500);

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
    lang,
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
    discountApplied,
  });
});
