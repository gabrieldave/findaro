import { createHmac, timingSafeEqual } from "crypto";
import { fail, handle, ok } from "@/lib/api";
import { fulfillPaidOrder } from "@/lib/fulfill";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function verifyStripeSignature(
  rawBody: string,
  header: string | null,
  secret: string,
): boolean {
  if (!header) return false;
  const parts = Object.fromEntries(
    header.split(",").map((p) => {
      const [k, v] = p.split("=");
      return [k.trim(), v];
    }),
  );
  const ts = parts.t;
  const v1 = parts.v1;
  if (!ts || !v1) return false;
  // Rechazar firmas > 5 min
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;
  const signed = createHmac("sha256", secret)
    .update(`${ts}.${rawBody}`)
    .digest("hex");
  try {
    return timingSafeEqual(Buffer.from(signed), Buffer.from(v1));
  } catch {
    return false;
  }
}

export const POST = handle(async (req) => {
  const secret = process.env.STRIPE_WEBHOOK_SECRET || "";
  const rawBody = await req.text();
  const sig = req.headers.get("stripe-signature");

  if (secret) {
    if (!verifyStripeSignature(rawBody, sig, secret)) {
      return fail("Firma inválida", 400);
    }
  } else if (process.env.NODE_ENV === "production") {
    // En prod exigir secreto; permitir modo interno con header de servicio.
    const internal = req.headers.get("x-findaro-fulfill-secret");
    if (!internal || internal !== process.env.FULFILL_SECRET) {
      return fail("Webhook no configurado", 503);
    }
  }

  const event = JSON.parse(rawBody) as {
    id?: string;
    type?: string;
    data?: { object?: Record<string, unknown> };
  };

  // Deduplicación en tabla stripe_events (ADR-04)
  if (event.id) {
    const { query } = await import("@/lib/db");
    const inserted = await query<{ event_id: string }>(
      `INSERT INTO stripe_events (event_id) VALUES ($1) ON CONFLICT (event_id) DO NOTHING RETURNING event_id`,
      [event.id],
    );
    if (inserted.rows.length === 0) {
      return ok({ ignored: true, reason: "duplicate_event" });
    }
  }

  if (event.type !== "checkout.session.completed") {
    return ok({ ignored: true });
  }

  const session = event.data?.object || {};
  const sessionId = String(session.id || "");
  const paymentIntent =
    typeof session.payment_intent === "string"
      ? session.payment_intent
      : null;
  const metadata = (session.metadata || {}) as Record<string, string>;
  const email =
    (session.customer_details as { email?: string } | undefined)?.email ||
    metadata.customer_email ||
    (typeof session.customer_email === "string" ? session.customer_email : null);
  const name =
    (session.customer_details as { name?: string } | undefined)?.name ||
    metadata.customer_name ||
    null;

  const result = await fulfillPaidOrder({
    sessionId,
    paymentIntent,
    email,
    name,
    orderId: metadata.service_id || metadata.purchase_id || null,
    amountTotal: typeof session.amount_total === "number" ? session.amount_total : null,
    currency: typeof session.currency === "string" ? session.currency : null,
    appId: metadata.app_id || metadata.tradingAppSlug || null,
  });

  return ok({ fulfilled: Boolean(result), orderId: result?.orderId ?? null });
});
