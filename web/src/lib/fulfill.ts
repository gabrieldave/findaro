import { query } from "./db";
import { issueDownloadToken } from "./download";
import { incrementPromoIfEligible } from "./pricing";
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
    customer_id: string;
    email: string;
    name: string;
  }>(
    `SELECT o.id, o.status, o.promo_slot, o.customer_id, c.email, c.name
     FROM orders o
     JOIN customers c ON c.id = o.customer_id
     WHERE o.stripe_session_id = $1
        OR o.id::text = $2
     LIMIT 1`,
    [opts.sessionId, opts.orderId || ""],
  );

  let order = rows[0];
  if (!order && opts.email) {
    const created = await query<{
      id: string;
      status: string;
      promo_slot: boolean;
      customer_id: string;
      email: string;
      name: string;
    }>(
      `WITH cust AS (
         INSERT INTO customers (email, name)
         VALUES ($1, $2)
         ON CONFLICT (email) DO UPDATE SET name = COALESCE(NULLIF(EXCLUDED.name,''), customers.name)
         RETURNING id, email, name
       )
       INSERT INTO orders (customer_id, amount_usd, status, stripe_session_id, stripe_payment_intent, paid_at)
       SELECT cust.id, 59, 'paid', $3, $4, now() FROM cust
       RETURNING id, status, promo_slot, customer_id,
         (SELECT email FROM cust) AS email,
         (SELECT name FROM cust) AS name`,
      [
        opts.email.toLowerCase(),
        opts.name || "",
        opts.sessionId,
        opts.paymentIntent || null,
      ],
    );
    order = created.rows[0];
  }

  if (!order) return null;
  if (order.status === "paid") {
    const existing = await query<{ token: string }>(
      `SELECT token FROM download_tokens WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [order.id],
    );
    const token = existing.rows[0]?.token || (await issueDownloadToken(order.id));
    return {
      orderId: order.id,
      email: order.email,
      name: order.name,
      downloadUrl: `${PUBLIC_APP_URL}/api/download?token=${token}`,
      alreadyPaid: true,
    };
  }

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

  const token = await issueDownloadToken(order.id);
  return {
    orderId: order.id,
    email: order.email,
    name: order.name,
    downloadUrl: `${PUBLIC_APP_URL}/api/download?token=${token}`,
    alreadyPaid: false,
  };
}
