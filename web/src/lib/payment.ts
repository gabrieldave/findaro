import { APP_ID, PAYMENT_GATEWAY_URL, PUBLIC_APP_URL, PRODUCT_NAME } from "./site";

export type CheckoutInput = {
  amountUsd: number;
  customerEmail: string;
  customerName: string;
  orderId: string;
  isPromo: boolean;
};

export async function createCheckoutSession(input: CheckoutInput): Promise<{
  url: string;
  sessionId: string;
}> {
  const body = {
    appId: APP_ID,
    event: "payment.create_checkout_session",
    data: {
      amount: input.amountUsd,
      currency: "usd",
      serviceTitle: `${PRODUCT_NAME} — licencia de por vida`,
      serviceDescription: input.isPromo
        ? "Precio de lanzamiento (primeros 1000) con actualizaciones incluidas."
        : "Licencia de por vida con actualizaciones incluidas.",
      serviceId: input.orderId,
      customerEmail: input.customerEmail,
      customerName: input.customerName,
      successUrl: `${PUBLIC_APP_URL}/gracias?session_id={CHECKOUT_SESSION_ID}`,
      cancelUrl: `${PUBLIC_APP_URL}/comprar?cancel=1`,
      metadata: {
        purchaseId: input.orderId,
        tradingAppSlug: APP_ID,
      },
    },
  };

  const res = await fetch(PAYMENT_GATEWAY_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });

  const json = (await res.json().catch(() => null)) as
    | { success?: boolean; data?: { url?: string; sessionId?: string }; error?: string }
    | null;

  if (!res.ok || !json?.success || !json.data?.url || !json.data.sessionId) {
    throw new Error(json?.error || "No se pudo crear la sesión de pago");
  }

  return { url: json.data.url, sessionId: json.data.sessionId };
}
