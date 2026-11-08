import { fail, handle, ok } from "@/lib/api";
import { query } from "@/lib/db";
import { verifyAdminCookie } from "@/lib/download";
import { currentOffer } from "@/lib/pricing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = handle(async (req) => {
  const cookie = req.headers.get("cookie") || "";
  const match = cookie.match(/(?:^|;\s*)findaro_admin=([^;]+)/);
  const email = verifyAdminCookie(match?.[1]);
  if (!email) return fail("No autorizado", 401);

  const offer = await currentOffer();
  const { rows } = await query<{
    id: string;
    email: string;
    name: string;
    created_at: Date;
    order_id: string | null;
    amount_usd: string | null;
    status: string | null;
    paid_at: Date | null;
    promo_slot: boolean | null;
    stripe_session_id: string | null;
  }>(
    `SELECT c.id, c.email, c.name, c.created_at,
            o.id AS order_id, o.amount_usd, o.status, o.paid_at, o.promo_slot,
            o.stripe_session_id
     FROM customers c
     LEFT JOIN LATERAL (
       SELECT * FROM orders WHERE customer_id = c.id
       ORDER BY created_at DESC LIMIT 1
     ) o ON true
     ORDER BY c.created_at DESC
     LIMIT 500`,
  );

  return ok({ admin: email, offer, customers: rows });
});
