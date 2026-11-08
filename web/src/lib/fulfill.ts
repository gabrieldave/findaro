import { query } from "./db";
import { issueDownloadToken } from "./download";
import { issueProLicense, mintReferralCode } from "./license";
import { incrementPromoIfEligible, LicenseTier } from "./pricing";
import { PUBLIC_APP_URL } from "./site";

export async function fulfillPaidOrder(opts: {
  sessionId: string;
  paymentIntent?: string | null;
  email?: string | null;
  name?: string | null;
  orderId?: string | null;
}) {
  const { rows } = await query<{
    id: string;
    status: string;
    promo_slot: boolean;
    tier: string;
    referral_code: string | null;
    customer_id: string;
    email: string;
    name: string;
    customer_ref: string | null;
  }>(
    `SELECT o.id, o.status, o.promo_slot, COALESCE(o.tier, 'personal') AS tier, o.referral_code, 
            o.customer_id, c.email, c.name, c.referral_code AS customer_ref
     FROM orders o
     JOIN customers c ON c.id = o.customer_id
     WHERE o.stripe_session_id = $1
        OR o.id::text = $2
     LIMIT 1`,
    [opts.sessionId, opts.orderId || ""],
  );

  let order = rows[0];
  if (!order && opts.email) {
    const custRef = mintReferralCode(opts.name || "FIND");
    const created = await query<{
      id: string;
      status: string;
      promo_slot: boolean;
      tier: string;
      referral_code: string | null;
      customer_id: string;
      email: string;
      name: string;
      customer_ref: string | null;
    }>(
      `WITH cust AS (
         INSERT INTO customers (email, name, referral_code)
         VALUES ($1, $2, $3)
         ON CONFLICT (email) DO UPDATE SET 
           name = COALESCE(NULLIF(EXCLUDED.name,''), customers.name),
           referral_code = COALESCE(customers.referral_code, EXCLUDED.referral_code)
         RETURNING id, email, name, referral_code
       )
       INSERT INTO orders (customer_id, amount_usd, status, stripe_session_id, stripe_payment_intent, paid_at, tier)
       SELECT cust.id, 39, 'paid', $4, $5, now(), 'personal' FROM cust
       RETURNING id, status, promo_slot, tier, referral_code, customer_id,
         (SELECT email FROM cust) AS email,
         (SELECT name FROM cust) AS name,
         (SELECT referral_code FROM cust) AS customer_ref`,
      [
        opts.email.toLowerCase(),
        opts.name || "",
        custRef,
        opts.sessionId,
        opts.paymentIntent || null,
      ],
    );
    order = created.rows[0];
  }

  if (!order) return null;

  // Si el cliente aún no tiene referral_code, asignarle uno
  let customerRefCode = order.customer_ref;
  if (!customerRefCode) {
    customerRefCode = mintReferralCode(order.name);
    await query(`UPDATE customers SET referral_code = $1 WHERE id = $2`, [
      customerRefCode,
      order.customer_id,
    ]);
  }

  if (order.status !== "paid") {
    await query(
      `UPDATE orders
       SET status = 'paid',
           paid_at = now(),
           stripe_payment_intent = COALESCE($2, stripe_payment_intent),
           stripe_session_id = COALESCE(stripe_session_id, $1)
       WHERE id = $3`,
      [opts.sessionId, opts.paymentIntent || null, order.id],
    );

    if (order.promo_slot) {
      await incrementPromoIfEligible();
    }

    // Registrar cashback de referido ($10 USD para el referente)
    if (order.referral_code) {
      const referrer = await query<{ id: string; email: string }>(
        `SELECT id, email FROM customers WHERE UPPER(referral_code) = UPPER($1) LIMIT 1`,
        [order.referral_code.trim()],
      );
      if (referrer.rows[0] && referrer.rows[0].id !== order.customer_id) {
        await query(
          `INSERT INTO referrals (referrer_customer_id, referred_order_id, referral_code, discount_applied_usd, commission_amount_usd, status)
           VALUES ($1, $2, $3, 4.00, 10.00, 'pending')
           ON CONFLICT DO NOTHING`,
          [referrer.rows[0].id, order.id, order.referral_code.trim().toUpperCase()],
        );
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

  return {
    orderId: order.id,
    email: order.email,
    name: order.name,
    downloadUrl: `${PUBLIC_APP_URL}/api/download?token=${token}`,
    licenseKey: pro.licenseKey,
    signed: pro.signed,
    seats: pro.seats,
    tier: orderTier,
    referralCode: customerRefCode,
    referralLink: `${PUBLIC_APP_URL}/?ref=${customerRefCode}`,
    plan: "pro" as const,
    alreadyPaid: order.status === "paid",
  };
}
