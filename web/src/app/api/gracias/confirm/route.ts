import { fail, handle, ok } from "@/lib/api";
import { fulfillPaidOrder } from "@/lib/fulfill";
import { VERIFY_GATEWAY_URL } from "@/lib/site";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    sessionId?: string;
  } | null;
  const sessionId = (body?.sessionId || "").trim();
  if (!sessionId) return fail("sessionId requerido", 400);

  // Recuperación idempotente directa si la orden ya está marcada como 'paid' (ADR-04)
  const { query } = await import("@/lib/db");
  const existingOrder = await query<{ id: string; status: string }>(
    `SELECT id, status FROM orders WHERE stripe_session_id = $1 LIMIT 1`,
    [sessionId],
  );

  if (existingOrder.rows[0]?.status === "paid") {
    const recoveryResult = await fulfillPaidOrder({
      sessionId,
      orderId: existingOrder.rows[0].id,
      appId: "findaro",
    });
    if (recoveryResult) {
      return ok(recoveryResult);
    }
  }

  const secret = process.env.FINDARO_GATEWAY_SECRET || process.env.GATEWAY_SECRET || "";
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret) {
    headers["x-findaro-gateway-secret"] = secret;
  }

  const verifyRes = await fetch(VERIFY_GATEWAY_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({ sessionId }),
  });
  const verifyJson = (await verifyRes.json().catch(() => null)) as {
    success?: boolean;
    data?: {
      paid?: boolean;
      email?: string | null;
      name?: string | null;
      paymentIntent?: string | null;
      orderId?: string | null;
      sessionId?: string;
      amountTotal?: number | null;
      currency?: string | null;
      appId?: string | null;
    };
  } | null;

  if (!verifyRes.ok || !verifyJson?.success || !verifyJson.data?.paid) {
    return fail("Pago aún no confirmado. Si Stripe ya cobró, espera unos segundos.", 402);
  }

  const result = await fulfillPaidOrder({
    sessionId: verifyJson.data.sessionId || sessionId,
    paymentIntent: verifyJson.data.paymentIntent,
    email: verifyJson.data.email,
    name: verifyJson.data.name,
    orderId: verifyJson.data.orderId,
    amountTotal: verifyJson.data.amountTotal,
    currency: verifyJson.data.currency,
    appId: verifyJson.data.appId,
  });
  if (!result) return fail("No se pudo generar descarga", 500);
  return ok(result);
});
