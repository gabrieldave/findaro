import { query } from "./db";
import { issueDownloadToken } from "./download";
import { sendPurchaseConfirmationEmail } from "./email";
import { recordEvent } from "./events";
import { issueProLicense, mintReferralCode } from "./license";
import { incrementPromoIfEligible, LicenseTier, referralDiscountForTier } from "./pricing";
import { PUBLIC_APP_URL } from "./site";

export async function fulfillPaidOrder(opts: {
  sessionId: string;
  paymentIntent?: string | null;
  email?: string | null;
  name?: string | null;
  orderId?: string | null;
  amountTotal?: number | null;
  currency?: string | null;
  appId?: string | null;
  lang?: "en" | "es" | null;
}) {
  // Validación estricta de metadatos de aplicación
  if (opts.appId && opts.appId !== "findaro") {
    console.warn("[fulfill] Rechazado: appId no corresponde a findaro:", opts.appId);
    return null;
  }

  // Validación estricta de moneda
  if (opts.currency && opts.currency.toLowerCase() !== "usd") {
    console.warn("[fulfill] Rechazado: moneda no es usd:", opts.currency);
    return null;
  }

  const { rows } = await query<{
    id: string;
    status: string;
    promo_slot: boolean;
    tier: string;
    amount_usd: string | number;
    referral_code: string | null;
    customer_id: string;
    email: string;
    name: string;
    customer_ref: string | null;
  }>(
    `SELECT o.id, o.status, o.promo_slot, COALESCE(o.tier, 'personal') AS tier, o.amount_usd, o.referral_code, 
            o.customer_id, c.email, c.name, c.referral_code AS customer_ref
     FROM orders o
     JOIN customers c ON c.id = o.customer_id
     WHERE o.stripe_session_id = $1
        OR o.id::text = $2
     LIMIT 1`,
    [opts.sessionId, opts.orderId || ""],
  );

  const order = rows[0];
  if (!order) {
    console.warn("[fulfill] Rechazado: no existe orden pendiente asociada para la sesión:", opts.sessionId);
    return null;
  }

  // Validación de importe total (en centavos) contra el importe registrado en la orden
  if (typeof opts.amountTotal === "number") {
    const expectedCents = Math.round(Number(order.amount_usd) * 100);
    if (opts.amountTotal !== expectedCents) {
      console.warn(
        `[fulfill] Rechazado: importe recibido (${opts.amountTotal}¢) no coincide con orden (${expectedCents}¢)`,
      );
      return null;
    }
  }

  // Si el cliente aún no tiene referral_code, asignarle uno
  let customerRefCode = order.customer_ref;
  if (!customerRefCode) {
    customerRefCode = mintReferralCode(order.name);
    await query(`UPDATE customers SET referral_code = $1 WHERE id = $2`, [
      customerRefCode,
      order.customer_id,
    ]);
  }

  // Transición atómica de estado: solo de 'pending' a 'paid' (ADR-04)
  let newlyPaid = false;
  if (order.status !== "paid") {
    if (order.status === "failed" || order.status === "refunded") {
      console.warn(`[fulfill] Orden ${order.id} en estado ${order.status}; ignorando intento de cumplimiento.`);
      return null;
    }

    const updateRes = await query<{ id: string }>(
      `UPDATE orders
       SET status = 'paid',
           paid_at = now(),
           stripe_payment_intent = COALESCE($2, stripe_payment_intent),
           stripe_session_id = COALESCE(stripe_session_id, $1)
       WHERE id = $3 AND status = 'pending'
       RETURNING id`,
      [opts.sessionId, opts.paymentIntent || null, order.id],
    );

    if (updateRes.rows.length > 0) {
      newlyPaid = true;
      order.status = "paid";

      if (order.promo_slot) {
        await incrementPromoIfEligible();
      }

      // Registrar evento purchase_confirmed con deduplicación por orden (ADR-05)
      await recordEvent({
        name: "purchase_confirmed",
        subjectType: "order",
        subjectId: order.id,
        occurrenceKey: "once",
        props: {
          tier: order.tier,
          amountUsd: order.amount_usd,
          promoSlot: order.promo_slot,
        },
      });

      // Registrar cashback de referido si aplica
      if (order.referral_code) {
        const referrer = await query<{ id: string; email: string }>(
          `SELECT id, email FROM customers WHERE UPPER(referral_code) = UPPER($1) LIMIT 1`,
          [order.referral_code.trim()],
        );
        if (referrer.rows[0] && referrer.rows[0].id !== order.customer_id) {
          const appliedDiscount = referralDiscountForTier((order.tier as LicenseTier) || "personal");
          await query(
            `INSERT INTO referrals (referrer_customer_id, referred_order_id, referral_code, discount_applied_usd, commission_amount_usd, status)
             VALUES ($1, $2, $3, $4, 10.00, 'pending')
             ON CONFLICT DO NOTHING`,
            [referrer.rows[0].id, order.id, order.referral_code.trim().toUpperCase(), appliedDiscount],
          );
        }
      }
    } else {
      // Releer estado tras concurrencia (ADR-04)
      const current = await query<{ status: string }>(`SELECT status FROM orders WHERE id = $1`, [order.id]);
      if (current.rows[0]?.status !== "paid") {
        console.warn(`[fulfill] Orden ${order.id} no está en estado paid tras reintento:`, current.rows[0]?.status);
        return null;
      }
    }
  }

  const orderTier = (order.tier as LicenseTier) || "personal";
  const pro = await issueProLicense({
    customerId: order.customer_id,
    orderId: order.id,
    email: order.email,
    tier: orderTier,
  });

  const lic = await query<{ id: string }>(
    `SELECT id FROM licenses WHERE license_key = $1`,
    [pro.licenseKey],
  );
  const existing = await query<{ token: string }>(
    `SELECT token FROM download_tokens WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`,
    [order.id],
  );
  const token =
    existing.rows[0]?.token ||
    (await issueDownloadToken(order.id, 30, lic.rows[0]?.id));

  const downloadUrl = `${PUBLIC_APP_URL}/api/download?token=${token}`;
  const referralLink = `${PUBLIC_APP_URL}/?ref=${customerRefCode}`;

  // Reclamar correo antes de enviar para evitar duplicados concurrentes (ADR-04)
  const claim = await query<{ id: string }>(
    `UPDATE orders
     SET email_claimed_at = now()
     WHERE id = $1
       AND email_sent_at IS NULL
       AND (email_claimed_at IS NULL OR email_claimed_at < now() - interval '10 minutes')
     RETURNING id`,
    [order.id],
  );

  if (claim.rows.length > 0) {
    try {
      const emailRes = await sendPurchaseConfirmationEmail({
        to: order.email,
        name: order.name,
        licenseKey: pro.licenseKey,
        downloadUrl,
        referralLink,
        seats: pro.seats,
        tier: orderTier,
        lang: opts.lang === "es" ? "es" : "en",
      });
      if (emailRes.success) {
        await query(`UPDATE orders SET email_sent_at = now() WHERE id = $1`, [order.id]);
      }
    } catch (e) {
      console.error("[fulfill] Error enviando correo de confirmación:", e);
    }
  }

  return {
    orderId: order.id,
    email: order.email,
    name: order.name,
    downloadUrl,
    licenseKey: pro.licenseKey,
    signed: pro.signed,
    seats: pro.seats,
    tier: orderTier,
    referralCode: customerRefCode,
    referralLink,
    plan: "pro" as const,
    alreadyPaid: !newlyPaid,
  };
}
