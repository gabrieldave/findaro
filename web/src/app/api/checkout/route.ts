import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { createCheckoutSession } from "@/lib/payment";
import { currentOffer } from "@/lib/pricing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = handle(async (req) => {
  const body = (await req.json().catch(() => null)) as {
    email?: string;
    name?: string;
  } | null;

  const email = (body?.email || "").trim().toLowerCase();
  const name = (body?.name || "").trim();
  if (!email || !email.includes("@")) return fail("Correo inválido", 400);
  if (name.length < 2) return fail("Nombre requerido", 400);

  const offer = await currentOffer();

  const customer = await query<{ id: string }>(
    `INSERT INTO customers (email, name)
     VALUES ($1, $2)
     ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, updated_at = now()
     RETURNING id`,
    [email, name],
  );
  const customerId = customer.rows[0]?.id;
  if (!customerId) return fail("No se pudo registrar el cliente", 500);

  const order = await query<{ id: string }>(
    `INSERT INTO orders (customer_id, amount_usd, currency, status, promo_slot)
     VALUES ($1, $2, 'usd', 'pending', $3)
     RETURNING id`,
    [customerId, offer.amountUsd, offer.isPromo],
  );
  const orderId = order.rows[0]?.id;
  if (!orderId) return fail("No se pudo crear la orden", 500);

  const session = await createCheckoutSession({
    amountUsd: offer.amountUsd,
    customerEmail: email,
    customerName: name,
    orderId,
    isPromo: offer.isPromo,
  });

  await query(`UPDATE orders SET stripe_session_id = $1 WHERE id = $2`, [
    session.sessionId,
    orderId,
  ]);

  return ok({
    url: session.url,
    sessionId: session.sessionId,
    amountUsd: offer.amountUsd,
    isPromo: offer.isPromo,
  });
});
