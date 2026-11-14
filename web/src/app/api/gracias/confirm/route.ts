import { fail, handle, ok } from "@/lib/api";
import { fulfillPaidOrder } from "@/lib/fulfill";
import { detectLanguageFromHeaders } from "@/lib/geo";
import { limitByIp } from "@/lib/ratelimit";
import { VERIFY_GATEWAY_URL } from "@/lib/site";
import { langFromCookieHeader } from "@/lib/lang";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const STRIPE_SESSION_REGEX = /^cs_(test|live)_[A-Za-z0-9]{10,120}$/;
const LICENSE_EXPOSURE_WINDOW_MS = 30 * 60 * 1000;

export const POST = handle(async (req) => {
  const limited = limitByIp(req, "gracias-confirm", 30, 10 * 60_000);
  if (limited) return limited;

  const body = (await req.json().catch(() => null)) as {
    sessionId?: string;
    lang?: string;
  } | null;

  const cookieHeader = req.headers.get("cookie") || "";
  const lang = detectLanguageFromHeaders(req.headers, langFromCookieHeader(cookieHeader), body?.lang);

  const sessionId = (body?.sessionId || "").trim();
  if (!sessionId || !STRIPE_SESSION_REGEX.test(sessionId)) {
    return fail(lang === "en" ? "Invalid sessionId" : "sessionId inválido", 400);
  }

  const { query } = await import("@/lib/db");
  const existingOrder = await query<{ id: string; status: string; paid_at: Date | null }>(
    `SELECT id, status, paid_at FROM orders WHERE stripe_session_id = $1 LIMIT 1`,
    [sessionId],
  );

  if (existingOrder.rows[0]?.status === "paid") {
    const recoveryResult = await fulfillPaidOrder({
      sessionId,
      orderId: existingOrder.rows[0].id,
      appId: "findaro",
      lang,
    });
    if (recoveryResult) {
      const paidAtMs = existingOrder.rows[0].paid_at
        ? new Date(existingOrder.rows[0].paid_at).getTime()
        : Date.now();
      if (Date.now() - paidAtMs > LICENSE_EXPOSURE_WINDOW_MS) {
        return ok({
          ...recoveryResult,
          licenseKey: "",
          signed: "",
          keyDeliveredByEmail: true,
        });
      }
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
      lang?: "en" | "es" | null;
    };
  } | null;

  if (!verifyRes.ok || !verifyJson?.success || !verifyJson.data?.paid) {
    return fail(
      lang === "en"
        ? "Payment not yet confirmed. If Stripe already charged you, please wait a few seconds."
        : "Pago aún no confirmado. Si Stripe ya cobró, espera unos segundos.",
      402,
    );
  }

  const verifiedSessionId = verifyJson.data.sessionId || sessionId;
  if (!STRIPE_SESSION_REGEX.test(verifiedSessionId)) {
    return fail("Sesión de verificación inválida", 400);
  }

  const result = await fulfillPaidOrder({
    sessionId: verifiedSessionId,
    paymentIntent: verifyJson.data.paymentIntent,
    email: verifyJson.data.email,
    name: verifyJson.data.name,
    orderId: verifyJson.data.orderId,
    amountTotal: verifyJson.data.amountTotal,
    currency: verifyJson.data.currency,
    appId: verifyJson.data.appId,
    lang: verifyJson.data.lang || lang,
  });
  if (!result) return fail(lang === "en" ? "Could not generate download" : "No se pudo generar descarga", 500);
  return ok(result);
});
