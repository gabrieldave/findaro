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

  const verifyRes = await fetch(VERIFY_GATEWAY_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
  });
  if (!result) return fail("No se pudo generar descarga", 500);
  return ok(result);
});
